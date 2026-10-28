-- 0029: aviso al administrador por cada registro nuevo + contador de visitas para el panel.

-- 1) Aviso (campanita + notificación) a cada administrador cuando alguien se registra.
alter table public.avisos drop constraint if exists avisos_tipo_check;
alter table public.avisos add constraint avisos_tipo_check check (tipo in ('pedido','chat','perfil','anuncio','registro'));

create or replace function public.avisar_registro() returns trigger
language plpgsql security definer set search_path = public as $$
declare adm record;
begin
  for adm in select id from public.profiles where is_admin and id <> new.id loop
    perform public.avisar(adm.id, '🆕 Nuevo registro: @' || new.username || ' (' || new.city || ')', 'registro', new.id);
  end loop;
  return new;
exception when others then
  return new; -- avisar nunca debe impedir un registro
end $$;
revoke all on function public.avisar_registro() from public, anon, authenticated;
drop trigger if exists profiles_avisar_registro on public.profiles;
create trigger profiles_avisar_registro after insert on public.profiles
  for each row execute function public.avisar_registro();

-- 2) Visitas: una fila por visita (sesión de la app). Sin nombre ni IP.
create table if not exists interno.visitas (
  id bigint generated always as identity primary key,
  creado timestamptz not null default now(),
  sesion text not null unique,
  disp text,                -- solo si la persona aceptó las cookies de estadística
  origen text not null,     -- instagram, whatsapp, tiktok, google, invitación, directo…
  ruta text not null,       -- app, inicio, anuncio, tienda
  plataforma text not null, -- web, android, ios
  user_id uuid              -- si inició sesión en esa visita
);
create index if not exists visitas_creado on interno.visitas (creado);
revoke all on interno.visitas from public, anon, authenticated;

create or replace function public.registrar_visita(p_sesion text, p_disp text, p_origen text, p_ruta text, p_plataforma text)
returns void language plpgsql security definer set search_path = public, interno as $$
declare limpio text := '^[a-z0-9._-]{1,40}$';
begin
  p_origen := lower(coalesce(p_origen, 'directo'));
  if p_sesion !~ '^[a-zA-Z0-9]{8,40}$' or p_origen !~ '^[a-z0-9.áéíóúñ _-]{1,40}$'
     or p_ruta !~ limpio or p_plataforma !~ limpio
     or (p_disp is not null and p_disp !~ '^[a-f0-9]{16}$') then
    return;
  end if;
  -- Las visitas de los administradores no cuentan.
  if exists (select 1 from public.profiles where id = auth.uid() and is_admin) then
    delete from interno.visitas where sesion = p_sesion;
    return;
  end if;
  -- Freno ante abusos: como mucho 50.000 visitas por día.
  if (select count(*) from interno.visitas where creado > now() - interval '1 day') > 50000 then return; end if;
  insert into interno.visitas (sesion, disp, origen, ruta, plataforma, user_id)
  values (p_sesion, p_disp, p_origen, p_ruta, p_plataforma, auth.uid())
  on conflict (sesion) do update set user_id = coalesce(interno.visitas.user_id, excluded.user_id),
                                     disp = coalesce(interno.visitas.disp, excluded.disp);
end $$;
revoke all on function public.registrar_visita(text, text, text, text, text) from public;
grant execute on function public.registrar_visita(text, text, text, text, text) to anon, authenticated;

-- Resumen para el panel (hora de Venezuela).
create or replace function public.admin_visitas(p_dias int default 14)
returns jsonb language plpgsql security definer stable set search_path = public, interno as $$
declare d int := least(greatest(coalesce(p_dias, 14), 1), 90);
        hoy date := (now() at time zone 'America/Caracas')::date;
        desde timestamptz := ((hoy - (d - 1))::timestamp) at time zone 'America/Caracas';
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  return jsonb_build_object(
    'hoy', jsonb_build_object(
       'visitas', (select count(*) from interno.visitas where (creado at time zone 'America/Caracas')::date = (now() at time zone 'America/Caracas')::date),
       'registros', (select count(*) from public.profiles where (created_at at time zone 'America/Caracas')::date = (now() at time zone 'America/Caracas')::date),
       'ahora', (select count(*) from interno.visitas where creado > now() - interval '30 minutes')),
    'total', jsonb_build_object(
       'visitas', (select count(*) from interno.visitas where creado >= desde),
       'unicos', (select count(distinct coalesce(disp, sesion)) from interno.visitas where creado >= desde),
       'registros', (select count(*) from public.profiles where created_at >= desde),
       'usuarios', (select count(*) from public.profiles)),
    'dias', (select coalesce(jsonb_agg(x order by x.dia), '[]') from (
       select g::date as dia,
              (select count(*) from interno.visitas v where (v.creado at time zone 'America/Caracas')::date = g::date) as visitas,
              (select count(*) from public.profiles p where (p.created_at at time zone 'America/Caracas')::date = g::date) as registros
         from generate_series((hoy - (d - 1))::timestamp, hoy::timestamp, interval '1 day') g) x),
    'origenes', (select coalesce(jsonb_agg(x), '[]') from (
       select origen, count(*) as visitas, count(distinct user_id) as con_cuenta
         from interno.visitas where creado >= desde group by origen order by count(*) desc limit 12) x),
    'rutas', (select coalesce(jsonb_agg(x), '[]') from (
       select ruta, count(*) as visitas from interno.visitas where creado >= desde group by ruta order by count(*) desc) x),
    'plataformas', (select coalesce(jsonb_agg(x), '[]') from (
       select plataforma, count(*) as visitas from interno.visitas where creado >= desde group by plataforma order by count(*) desc) x),
    'nuevos', (select coalesce(jsonb_agg(x), '[]') from (
       select p.username, p.city, p.created_at,
              (select v.origen from interno.visitas v where v.user_id = p.id order by v.creado limit 1) as origen
         from public.profiles p order by p.created_at desc limit 20) x)
  );
end $$;
revoke all on function public.admin_visitas(int) from public, anon;
grant execute on function public.admin_visitas(int) to authenticated;

-- Se borran las visitas de más de 13 meses.
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'limpiar_visitas';
    perform cron.schedule('limpiar_visitas', '40 4 * * *', $c$delete from interno.visitas where creado < now() - interval '13 months'$c$);
  end if;
exception when others then null; end $$;
