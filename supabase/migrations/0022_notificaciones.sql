-- 0022: notificaciones al teléfono (Web Push), también con la app cerrada.
-- Cada aviso nuevo se envía a los dispositivos donde la persona activó las notificaciones.
-- El envío lo hace la función "push" del servidor; la clave privada vive solo allí.

create table if not exists public.push_subs (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique check (endpoint like 'https://%' and char_length(endpoint) < 1000),
  p256dh text not null check (char_length(p256dh) < 200),
  auth text not null check (char_length(auth) < 100),
  creado timestamptz not null default now()
);
create index if not exists push_subs_usuario on public.push_subs (user_id);
alter table public.push_subs enable row level security;
revoke all on public.push_subs from anon, authenticated;
grant select (id, creado) on public.push_subs to authenticated;
drop policy if exists push_propias on public.push_subs;
create policy push_propias on public.push_subs for select to authenticated using (user_id = auth.uid());

-- Guarda este dispositivo para la persona (si el dispositivo era de otra cuenta, pasa a esta).
create or replace function public.guardar_push(p_endpoint text, p_p256dh text, p_auth text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;
  delete from public.push_subs where endpoint = p_endpoint;
  insert into public.push_subs (user_id, endpoint, p256dh, auth) values (auth.uid(), p_endpoint, p_p256dh, p_auth);
  delete from public.push_subs where user_id = auth.uid() and id not in (
    select id from public.push_subs where user_id = auth.uid() order by creado desc limit 10);
end $$;
revoke all on function public.guardar_push(text, text, text) from public, anon;
grant execute on function public.guardar_push(text, text, text) to authenticated;

create or replace function public.quitar_push(p_endpoint text) returns void
language sql security definer set search_path = public as $$
  delete from public.push_subs where endpoint = p_endpoint and user_id = auth.uid()
$$;
revoke all on function public.quitar_push(text) from public, anon;
grant execute on function public.quitar_push(text) to authenticated;

-- Último texto enviado por notificación (los avisos de chat se actualizan con cada mensaje).
alter table public.avisos add column if not exists push_texto text;

-- Lo usa SOLO la función de envío (con permisos de servidor): toma el aviso si aún no se
-- envió ese texto y es reciente. Así, aunque alguien llame a la función, nada se repite.
create or replace function public.push_tomar(p_aviso bigint)
returns table (user_id uuid, texto text, tipo text, ref_id uuid)
language sql security definer set search_path = public as $$
  update public.avisos a set push_texto = a.texto
  where a.id = p_aviso and a.push_texto is distinct from a.texto
    and a.creado > now() - interval '15 minutes' and not a.leido
  returning a.user_id, a.texto, a.tipo, a.ref_id
$$;
revoke all on function public.push_tomar(bigint) from public, anon, authenticated;
do $$ begin
  execute 'grant execute on function public.push_tomar(bigint) to service_role';
exception when others then null; end $$;

-- Cada aviso nuevo (y cada mensaje nuevo de un chat) llama a la función de envío.
create or replace function public.avisos_push() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and (new.texto is not distinct from old.texto or new.leido) then return new; end if;
  if not exists (select 1 from public.push_subs where user_id = new.user_id) then return new; end if;
  if to_regproc('net.http_post') is null then return new; end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
    using 'https://udhyuyokrxggdnnepbmr.supabase.co/functions/v1/push',
          jsonb_build_object('aviso', new.id),
          '{"Content-Type": "application/json"}'::jsonb;
  return new;
exception when others then
  return new; -- un fallo al notificar nunca debe frenar la app
end $$;
revoke all on function public.avisos_push() from public, anon, authenticated;
drop trigger if exists avisos_push on public.avisos;
create trigger avisos_push after insert or update of texto on public.avisos
  for each row execute function public.avisos_push();
