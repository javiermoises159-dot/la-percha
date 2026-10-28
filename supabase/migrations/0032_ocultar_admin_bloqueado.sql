-- Los campos is_admin y blocked de profiles ya no se pueden leer desde la app pública.
-- Las funciones internas (security definer) siguen leyéndolos.
-- IMPORTANTE: si en el futuro se agrega una columna a profiles que la app deba leer,
-- hay que darle permiso: grant select (columna) on public.profiles to anon, authenticated;
-- La regla de lectura de anuncios miraba profiles.blocked con los permisos de quien lee:
-- la pasamos por una función interna para que siga funcionando.
create or replace function public.vendedor_pausado(p_vendedor uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id = p_vendedor and (p.vacation or p.blocked))
$$;
revoke all on function public.vendedor_pausado(uuid) from public;
grant execute on function public.vendedor_pausado(uuid) to anon, authenticated;

drop policy if exists listings_read on public.listings;
create policy listings_read on public.listings for select using (
  seller_id = auth.uid() or public.is_admin()
  or status = any (array['reserved','sold'])
  or (status = 'active' and not public.vendedor_pausado(seller_id))
);

do $$
declare cols text;
begin
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position) into cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'profiles'
    and column_name not in ('is_admin', 'blocked');
  execute 'revoke select on public.profiles from anon, authenticated';
  execute 'grant select (' || cols || ') on public.profiles to anon, authenticated';
end $$;

-- Lista de perfiles para el panel de administración (solo la ven los admin).
create or replace view public.admin_profiles with (security_invoker = false) as
  select id, username, city, blocked, is_admin, verificado, fundador_n, created_at
  from public.profiles
  where public.is_admin();
revoke all on public.admin_profiles from public, anon;
grant select on public.admin_profiles to authenticated;
