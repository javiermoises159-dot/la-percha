-- 0017: programa "Vendedor fundador" y limpieza de permisos.
-- Los primeros 200 vendedores que publican reciben una insignia con su número
-- y 3 destacados gratis de 7 días.

alter table public.profiles add column if not exists fundador_n int;
alter table public.profiles add column if not exists destacados_gratis int not null default 0;
do $$ begin
  alter table public.profiles add constraint profiles_fundador_unico unique (fundador_n);
exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin
  alter table public.profiles add constraint profiles_destacados_gratis_ok check (destacados_gratis between 0 and 20);
exception when duplicate_object then null; end $$;
-- Columnas públicas (la insignia se ve en el perfil); nadie las puede escribir desde la app.
grant select (fundador_n, destacados_gratis) on public.profiles to anon, authenticated;

create or replace function public.lp_dar_fundador(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_user is null or exists (select 1 from public.profiles where id = p_user and fundador_n is not null) then
    return;
  end if;
  perform pg_advisory_xact_lock(hashtext('pavito_fundadores'));
  select count(*) into n from public.profiles where fundador_n is not null;
  if n >= 200 then return; end if;
  update public.profiles set fundador_n = n + 1, destacados_gratis = destacados_gratis + 3
    where id = p_user and fundador_n is null and not coalesce(blocked, false);
  if found then
    perform public.avisar(p_user,
      '¡Eres el vendedor fundador #' || (n + 1) || ' de Pavito! Tienes 3 destacados gratis.', 'perfil', null);
  end if;
end $$;
revoke all on function public.lp_dar_fundador(uuid) from public, anon, authenticated;

create or replace function public.listings_fundador() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.lp_dar_fundador(new.seller_id);
  return new;
end $$;
revoke all on function public.listings_fundador() from public, anon, authenticated;
drop trigger if exists listings_fundador on public.listings;
create trigger listings_fundador after insert on public.listings
  for each row execute function public.listings_fundador();

-- Quienes ya publicaron antes de esto entran por orden de su primer anuncio.
do $$ declare r record; begin
  for r in select seller_id, min(created_at) primero from public.listings group by seller_id order by 2 loop
    perform public.lp_dar_fundador(r.seller_id);
  end loop;
end $$;

-- Cuántos puestos quedan (para el cartel de la app).
create or replace function public.fundadores_restantes() returns int
language sql stable security definer set search_path = public as $$
  select greatest(0, 200 - count(*))::int from public.profiles where fundador_n is not null
$$;
revoke all on function public.fundadores_restantes() from public;
grant execute on function public.fundadores_restantes() to anon, authenticated;

-- Usar un destacado gratis: 7 días, solo en un anuncio propio y activo.
create or replace function public.usar_destacado_gratis(p_listing uuid) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare l public.listings; v timestamptz;
begin
  if auth.uid() is null or public.is_blocked() then raise exception 'No autorizado'; end if;
  select * into l from public.listings where id = p_listing for update;
  if l.id is null or l.seller_id <> auth.uid() then raise exception 'No autorizado'; end if;
  if l.status <> 'active' then raise exception 'Solo puedes destacar anuncios activos'; end if;
  update public.profiles set destacados_gratis = destacados_gratis - 1
    where id = auth.uid() and destacados_gratis > 0;
  if not found then raise exception 'Ya usaste tus destacados gratis'; end if;
  perform set_config('lapercha.sistema', '1', true);
  update public.listings
    set featured_until = greatest(coalesce(featured_until, now()), now()) + interval '7 days'
    where id = l.id returning featured_until into v;
  perform set_config('lapercha.sistema', '', true);
  return v;
end $$;
revoke all on function public.usar_destacado_gratis(uuid) from public, anon;
grant execute on function public.usar_destacado_gratis(uuid) to authenticated;

-- Limpieza: el precio del pedido lo pone siempre el servidor; la app ya no lo envía.
revoke insert (price) on public.orders from authenticated;
