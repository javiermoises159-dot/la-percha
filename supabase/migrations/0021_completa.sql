-- 0021: lo que le faltaba para estar a la altura de Vinted.
--  1. Marca en los anuncios (y se puede buscar por marca).
--  2. Editar un anuncio ya publicado (precio, talla, textos, marca).
--  3. Estadísticas para el vendedor: vistas y favoritos de cada anuncio.
--  4. "Subir arriba" gratis una vez por semana por anuncio.
--  5. Alertas de búsqueda: avisan cuando publican algo que buscas.
--  6. Vendedor verificado (lo marca el equipo de Pavito).
--  7. Invita a un amigo: quien invita gana un destacado gratis cuando su invitado publica.

-- ============ 1 y 2. Marca y edición ============
alter table public.listings add column if not exists brand text;
do $$ begin
  alter table public.listings add constraint listings_brand_largo check (brand is null or char_length(brand) <= 40);
exception when duplicate_object then null; end $$;
grant select (brand) on public.listings to anon, authenticated;
grant insert (brand) on public.listings to authenticated;
grant update (brand) on public.listings to authenticated;

-- ============ 4. Subir arriba ============
alter table public.listings add column if not exists bumped_at timestamptz;
alter table public.listings add column if not exists orden timestamptz;
update public.listings set orden = coalesce(bumped_at, created_at) where orden is null;
alter table public.listings alter column orden set default now();
create index if not exists listings_orden on public.listings (status, orden desc);
grant select (bumped_at, orden) on public.listings to anon, authenticated;

create or replace function public.listings_orden() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.bumped_at := null;
    new.orden := now();
  else
    new.orden := coalesce(new.bumped_at, old.orden, new.created_at);
    if new.bumped_at is distinct from old.bumped_at
       and coalesce(current_setting('lapercha.sistema', true), '') <> '1' then
      new.bumped_at := old.bumped_at;
      new.orden := old.orden;
    end if;
  end if;
  return new;
end $$;
revoke all on function public.listings_orden() from public, anon, authenticated;
drop trigger if exists listings_orden on public.listings;
create trigger listings_orden before insert or update on public.listings
  for each row execute function public.listings_orden();

create or replace function public.subir_anuncio(p_listing uuid) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare l public.listings;
begin
  if auth.uid() is null or public.is_blocked() then raise exception 'No autorizado'; end if;
  select * into l from public.listings where id = p_listing for update;
  if l.id is null or l.seller_id <> auth.uid() then raise exception 'No autorizado'; end if;
  if l.status <> 'active' then raise exception 'Solo puedes subir anuncios activos'; end if;
  if coalesce(l.bumped_at, l.created_at) > now() - interval '7 days' then
    raise exception 'Podrás volver a subirlo el %',
      to_char((coalesce(l.bumped_at, l.created_at) + interval '7 days') at time zone 'America/Caracas', 'DD/MM "a las" HH24:MI');
  end if;
  perform set_config('lapercha.sistema', '1', true);
  update public.listings set bumped_at = now() where id = l.id;
  perform set_config('lapercha.sistema', '', true);
  return now();
end $$;
revoke all on function public.subir_anuncio(uuid) from public, anon;
grant execute on function public.subir_anuncio(uuid) to authenticated;

-- ============ 3. Vistas y estadísticas ============
create table if not exists public.vistas (
  listing_id uuid not null references public.listings(id) on delete cascade,
  quien text not null,
  dia date not null default (now() at time zone 'America/Caracas')::date,
  primary key (listing_id, quien, dia)
);
alter table public.vistas enable row level security;
revoke all on public.vistas from anon, authenticated;

-- Cuenta una vista por persona (o por dispositivo, si no tiene cuenta) y día. Quien vende no cuenta.
create or replace function public.registrar_vista(p_listing uuid, p_dispositivo text default null) returns void
language plpgsql security definer set search_path = public as $$
declare quien text := coalesce(auth.uid()::text, 'd:' || left(regexp_replace(coalesce(p_dispositivo, ''), '[^A-Za-z0-9-]', '', 'g'), 40));
begin
  if quien = 'd:' then return; end if;
  if exists (select 1 from public.listings where id = p_listing and seller_id = auth.uid()) then return; end if;
  insert into public.vistas (listing_id, quien) values (p_listing, quien) on conflict do nothing;
exception when foreign_key_violation then null;
end $$;
revoke all on function public.registrar_vista(uuid, text) from public;
grant execute on function public.registrar_vista(uuid, text) to anon, authenticated;

-- Para quien vende: vistas y favoritos de sus anuncios.
create or replace function public.mis_estadisticas() returns table (listing_id uuid, vistas bigint, favoritos bigint)
language sql stable security definer set search_path = public as $$
  select l.id,
         (select count(*) from public.vistas v where v.listing_id = l.id),
         (select count(*) from public.favorites f where f.listing_id = l.id)
  from public.listings l where l.seller_id = auth.uid()
$$;
revoke all on function public.mis_estadisticas() from public, anon;
grant execute on function public.mis_estadisticas() to authenticated;

-- ============ 6. Vendedor verificado ============
alter table public.profiles add column if not exists verificado boolean not null default false;
grant select (verificado) on public.profiles to anon, authenticated;

create or replace function public.admin_set_verificado(p_user uuid, p_si boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  update public.profiles set verificado = coalesce(p_si, false) where id = p_user;
  perform interno.registrar(case when p_si then 'verificar' else 'quitar_verificado' end, p_user, null);
  if p_si then
    perform public.avisar(p_user, '¡Tu perfil ya está verificado! Ahora muestra la insignia de vendedor verificado.', 'perfil', null);
  end if;
end $$;
revoke all on function public.admin_set_verificado(uuid, boolean) from public, anon;
grant execute on function public.admin_set_verificado(uuid, boolean) to authenticated;

-- ============ 5. Alertas de búsqueda ============
do $$ begin
  alter table public.avisos drop constraint if exists avisos_tipo_check;
  alter table public.avisos add constraint avisos_tipo_check check (tipo in ('pedido','chat','perfil','anuncio'));
end $$;

create table if not exists public.alertas_busqueda (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  q text not null default '' check (char_length(q) <= 60),
  categoria text,
  talla text check (talla is null or char_length(talla) <= 20),
  ciudad text check (ciudad is null or char_length(ciudad) <= 40),
  precio_max numeric(10,2) check (precio_max is null or precio_max > 0),
  creado timestamptz not null default now()
);
create index if not exists alertas_usuario on public.alertas_busqueda (user_id);
alter table public.alertas_busqueda enable row level security;
revoke all on public.alertas_busqueda from anon, authenticated;
grant select, delete on public.alertas_busqueda to authenticated;
grant insert (q, categoria, talla, ciudad, precio_max) on public.alertas_busqueda to authenticated;
alter table public.alertas_busqueda alter column user_id set default auth.uid();
drop policy if exists alertas_propias on public.alertas_busqueda;
create policy alertas_propias on public.alertas_busqueda for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function public.alertas_limite() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.user_id := auth.uid();
  if new.user_id is null then raise exception 'No autorizado'; end if;
  if (select count(*) from public.alertas_busqueda where user_id = new.user_id) >= 10 then
    raise exception 'Puedes tener hasta 10 alertas. Borra una para crear otra.';
  end if;
  if coalesce(btrim(new.q), '') = '' and new.categoria is null and new.talla is null then
    raise exception 'Escribe qué buscas o elige una categoría o talla';
  end if;
  new.q := btrim(coalesce(new.q, ''));
  return new;
end $$;
revoke all on function public.alertas_limite() from public, anon, authenticated;
drop trigger if exists alertas_limite on public.alertas_busqueda;
create trigger alertas_limite before insert on public.alertas_busqueda
  for each row execute function public.alertas_limite();

-- Al publicarse un anuncio, avisa a quienes tienen una alerta que coincide (máx. 1 aviso por anuncio y persona).
create or replace function public.alertas_avisar() returns trigger
language plpgsql security definer set search_path = public as $$
declare a record; texto text;
begin
  if new.status <> 'active' then return new; end if;
  texto := public.lp_sin_tildes(new.title || ' ' || coalesce(new.brand, '') || ' ' || new.description || ' ' || new.category);
  for a in
    select distinct on (al.user_id) al.user_id, al.q from public.alertas_busqueda al
    where al.user_id <> new.seller_id
      and (al.categoria is null or al.categoria = new.category)
      and (al.talla is null or lower(al.talla) = lower(new.size))
      and (al.ciudad is null or public.lp_sin_tildes(al.ciudad) = public.lp_sin_tildes(new.city))
      and (al.precio_max is null or new.price <= al.precio_max)
      and (al.q = '' or texto like '%' || public.lp_sin_tildes(al.q) || '%')
    limit 500
  loop
    perform public.avisar(a.user_id, 'Nuevo para tu alerta' || case when a.q <> '' then ' "' || a.q || '"' else '' end
      || ': ' || left(new.title, 60) || ' · $' || to_char(new.price, 'FM999990.00'), 'anuncio', new.id);
  end loop;
  return new;
end $$;
revoke all on function public.alertas_avisar() from public, anon, authenticated;
drop trigger if exists alertas_avisar on public.listings;
create trigger alertas_avisar after insert on public.listings
  for each row execute function public.alertas_avisar();

-- ============ 7. Invita a un amigo ============
alter table public.profiles add column if not exists invitado_por uuid references public.profiles(id) on delete set null;
alter table public.profiles add column if not exists premio_invitacion boolean not null default false;

create or replace function public.usar_invitacion(p_username text) returns void
language plpgsql security definer set search_path = public as $$
declare quien uuid;
begin
  if auth.uid() is null then return; end if;
  select id into quien from public.profiles where lower(username) = lower(btrim(p_username));
  if quien is null or quien = auth.uid() then return; end if;
  update public.profiles set invitado_por = quien
    where id = auth.uid() and invitado_por is null and created_at > now() - interval '3 days';
end $$;
revoke all on function public.usar_invitacion(text) from public, anon;
grant execute on function public.usar_invitacion(text) to authenticated;

create or replace function public.invitacion_premio() returns trigger
language plpgsql security definer set search_path = public as $$
declare p public.profiles;
begin
  select * into p from public.profiles where id = new.seller_id;
  if p.invitado_por is null or p.premio_invitacion then return new; end if;
  update public.profiles set premio_invitacion = true where id = p.id;
  update public.profiles set destacados_gratis = least(destacados_gratis + 1, 20)
    where id = p.invitado_por and not coalesce(blocked, false);
  perform public.avisar(p.invitado_por, '@' || p.username || ' publicó su primera prenda. Ganaste 1 destacado gratis por invitarle.', 'perfil', null);
  return new;
end $$;
revoke all on function public.invitacion_premio() from public, anon, authenticated;
drop trigger if exists invitacion_premio on public.listings;
create trigger invitacion_premio after insert on public.listings
  for each row execute function public.invitacion_premio();

create or replace function public.mis_invitados() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.profiles where invitado_por = auth.uid()
$$;
revoke all on function public.mis_invitados() from public, anon;
grant execute on function public.mis_invitados() to authenticated;

-- ============ Buscador: ahora también por marca, y ordena por "subido" ============
create or replace function public.buscar_anuncios(p_q text, p_cat text default null, p_lim int default 60)
returns setof public.listings
language sql stable security invoker set search_path = public as $$
  with q as (
    select '%' || replace(replace(public.lp_sin_tildes(left(btrim(coalesce(p_q, '')), 60)), '%', ''), '_', '') || '%' as patron
  )
  select l.* from public.listings l, q
  where l.status = 'active'
    and (p_cat is null or p_cat = '' or l.category = p_cat)
    and (
      coalesce(btrim(p_q), '') = ''
      or public.lp_sin_tildes(l.title) like q.patron
      or public.lp_sin_tildes(l.brand) like q.patron
      or public.lp_sin_tildes(l.description) like q.patron
      or public.lp_sin_tildes(l.category) like q.patron
      or exists (select 1 from public.profiles p
                 where p.id = l.seller_id and public.lp_sin_tildes(p.username) like q.patron)
    )
  order by (l.featured_until is not null and l.featured_until > now()) desc, l.orden desc
  limit least(greatest(coalesce(p_lim, 60), 1), 200)
$$;
revoke all on function public.buscar_anuncios(text, text, int) from public;
grant execute on function public.buscar_anuncios(text, text, int) to anon, authenticated;

-- ============ Rebaja: avisa a quienes lo tienen en favoritos ============
create or replace function public.avisar_rebaja() returns trigger
language plpgsql security definer set search_path = public as $$
declare f record;
begin
  if new.status <> 'active' or new.price >= old.price then return new; end if;
  for f in select user_id from public.favorites where listing_id = new.id and user_id <> new.seller_id limit 1000 loop
    perform public.avisar(f.user_id, 'Bajó de precio: ' || left(new.title, 60) || ' ahora a $'
      || to_char(new.price, 'FM999990.00') || ' (antes $' || to_char(old.price, 'FM999990.00') || ').', 'anuncio', new.id);
  end loop;
  return new;
end $$;
revoke all on function public.avisar_rebaja() from public, anon, authenticated;
drop trigger if exists avisar_rebaja on public.listings;
create trigger avisar_rebaja after update of price on public.listings
  for each row execute function public.avisar_rebaja();
