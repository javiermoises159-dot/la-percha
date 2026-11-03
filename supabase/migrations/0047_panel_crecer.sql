-- 0047: panel para crecer y lanzar
--  1. Lista de usuarios para activarlos (cuántas prendas tienen, contacto).
--  2. Mensajes (avisos + notificación) a todos o a un grupo.
--  3. Abrir los pagos y poner los datos de cobro desde el panel, sin tocar el código.

-- ===== 3. Configuración pública de la app =====
create table if not exists public.config_app (
  clave text primary key,
  valor text not null default '',
  actualizado timestamptz not null default now()
);
alter table public.config_app enable row level security;
revoke all on public.config_app from anon, authenticated;
grant select on public.config_app to anon, authenticated;
drop policy if exists config_app_leer on public.config_app;
create policy config_app_leer on public.config_app for select using (true);

insert into public.config_app (clave, valor) values
  ('pagos_abiertos', 'false'),
  ('pm_banco', ''), ('pm_cedula', ''), ('pm_telefono', ''),
  ('binance_id', ''), ('binance_nombre', ''),
  ('zinli_correo', ''), ('zinli_nombre', '')
on conflict (clave) do nothing;

create or replace function public.pagos_abiertos() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select valor = 'true' from public.config_app where clave = 'pagos_abiertos'), false)
$$;
grant execute on function public.pagos_abiertos() to anon, authenticated;

create or replace function public.admin_set_config(p_clave text, p_valor text)
returns void language plpgsql security definer set search_path = public, interno as $$
declare v text := btrim(coalesce(p_valor, ''));
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  if p_clave not in ('pagos_abiertos','pm_banco','pm_cedula','pm_telefono','binance_id','binance_nombre','zinli_correo','zinli_nombre') then
    raise exception 'Ajuste no válido';
  end if;
  if char_length(v) > 80 then raise exception 'Máximo 80 caracteres'; end if;
  if p_clave = 'pagos_abiertos' then
    if v not in ('true','false') then raise exception 'Valor no válido'; end if;
    if v = 'true' and not exists (
         select 1 from public.config_app c
          where (c.clave = 'pm_telefono' and c.valor <> '' and exists (select 1 from public.config_app b where b.clave = 'pm_banco' and b.valor <> '')
                                         and exists (select 1 from public.config_app d where d.clave = 'pm_cedula' and d.valor <> ''))
             or (c.clave = 'binance_id' and c.valor <> '')
             or (c.clave = 'zinli_correo' and c.valor <> '')) then
      raise exception 'Antes de abrir los pagos pon los datos reales de al menos un método de cobro';
    end if;
  end if;
  update public.config_app set valor = v, actualizado = now() where clave = p_clave;
  insert into interno.auditoria (actor, accion, detalle) values (auth.uid(), 'config_' || p_clave, jsonb_build_object('valor', v));
end $$;
revoke all on function public.admin_set_config(text, text) from public, anon;
grant execute on function public.admin_set_config(text, text) to authenticated;

-- El servidor también impide comprar mientras los pagos estén cerrados.
create or replace function public.orders_pagos_cerrados() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.pagos_abiertos() then
    raise exception 'Los pagos en Pavito abren muy pronto. Mientras tanto, guarda la prenda en favoritos.';
  end if;
  return new;
end $$;
revoke all on function public.orders_pagos_cerrados() from public, anon, authenticated;
drop trigger if exists orders_aa_pagos_cerrados on public.orders;
create trigger orders_aa_pagos_cerrados before insert on public.orders
  for each row execute function public.orders_pagos_cerrados();

-- ===== 1. Usuarios para activar =====
create or replace function public.admin_usuarios_activacion(p_solo_sin_prendas boolean default false)
returns table (id uuid, username text, city text, creado timestamptz, prendas int, fundador int,
               telefono text, correo text, ultima_visita timestamptz)
language plpgsql security definer stable set search_path = public, interno as $$
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  return query
    select p.id, p.username, p.city, p.created_at,
           (select count(*)::int from public.listings l where l.seller_id = p.id and l.status in ('active','reserved')),
           p.fundador_n,
           pp.phone,
           (to_jsonb(u) ->> 'email'),
           (select max(v.creado) from interno.visitas v where v.user_id = p.id)
      from public.profiles p
      left join public.private_profiles pp on pp.id = p.id
      left join auth.users u on u.id = p.id
     where not p.is_admin and not p.blocked
       and (not p_solo_sin_prendas or not exists (
             select 1 from public.listings l where l.seller_id = p.id and l.status in ('active','reserved')))
     order by p.created_at desc
     limit 500;
end $$;
revoke all on function public.admin_usuarios_activacion(boolean) from public, anon;
grant execute on function public.admin_usuarios_activacion(boolean) to authenticated;

-- ===== 2. Mensajes a usuarios =====
alter table public.avisos drop constraint if exists avisos_tipo_check;
alter table public.avisos add constraint avisos_tipo_check
  check (tipo in ('pedido','chat','perfil','anuncio','registro','pavito'));

create table if not exists interno.comunicados (
  id bigint generated always as identity primary key,
  creado timestamptz not null default now(),
  admin_id uuid not null,
  texto text not null,
  grupo text not null,
  ciudad text,
  enviados int not null
);
revoke all on interno.comunicados from public, anon, authenticated;

-- p_grupo: todos · sin_prendas · con_prendas · fundadores · ciudad · usuario
-- p_simular = true solo cuenta a cuántas personas le llegaría.
create or replace function public.admin_enviar_aviso(p_texto text, p_grupo text, p_ciudad text default null,
                                                     p_usuario uuid default null, p_simular boolean default false)
returns int language plpgsql security definer set search_path = public, interno as $$
declare t text := btrim(coalesce(p_texto, '')); n int := 0; r record;
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  if p_grupo not in ('todos','sin_prendas','con_prendas','fundadores','ciudad','usuario') then raise exception 'Grupo no válido'; end if;
  if p_grupo = 'ciudad' and coalesce(btrim(p_ciudad), '') = '' then raise exception 'Indica la ciudad'; end if;
  if p_grupo = 'usuario' and p_usuario is null then raise exception 'Indica el usuario'; end if;
  if not p_simular then
    if char_length(t) < 5 or char_length(t) > 160 then raise exception 'El mensaje debe tener entre 5 y 160 caracteres'; end if;
    if p_grupo <> 'usuario' and (select count(*) from interno.comunicados
         where grupo <> 'usuario' and creado > now() - interval '1 day') >= 5 then
      raise exception 'Máximo 5 mensajes masivos por día, para no cansar a la gente';
    end if;
  end if;
  for r in
    select p.id from public.profiles p
     where not p.is_admin and not p.blocked
       and case p_grupo
             when 'todos' then true
             when 'sin_prendas' then not exists (select 1 from public.listings l where l.seller_id = p.id and l.status in ('active','reserved'))
             when 'con_prendas' then exists (select 1 from public.listings l where l.seller_id = p.id and l.status in ('active','reserved'))
             when 'fundadores' then p.fundador_n is not null
             when 'ciudad' then public.lp_sin_tildes(p.city) = public.lp_sin_tildes(btrim(p_ciudad))
             when 'usuario' then p.id = p_usuario
           end
  loop
    n := n + 1;
    if not p_simular then
      insert into public.avisos (user_id, texto, tipo, ref_id) values (r.id, t, 'pavito', null);
    end if;
  end loop;
  if not p_simular then
    insert into interno.comunicados (admin_id, texto, grupo, ciudad, enviados)
    values (auth.uid(), t, p_grupo, nullif(btrim(coalesce(p_ciudad, '')), ''), n);
  end if;
  return n;
end $$;
revoke all on function public.admin_enviar_aviso(text, text, text, uuid, boolean) from public, anon;
grant execute on function public.admin_enviar_aviso(text, text, text, uuid, boolean) to authenticated;

create or replace function public.admin_comunicados()
returns table (creado timestamptz, admin text, texto text, grupo text, ciudad text, enviados int)
language sql security definer stable set search_path = public, interno as $$
  select c.creado, p.username, c.texto, c.grupo, c.ciudad, c.enviados
    from interno.comunicados c left join public.profiles p on p.id = c.admin_id
   where public.is_admin() order by c.creado desc limit 50
$$;
revoke all on function public.admin_comunicados() from public, anon;
grant execute on function public.admin_comunicados() to authenticated;
