-- 0019: buscador en toda la base de datos (no solo en los últimos 300 anuncios) y
-- el puesto de fundador #1 vuelve a quedar libre (lo tenía una cuenta de prueba).

-- Quita tildes y pasa a minúsculas, para que "camisa" encuentre "Camisá" y al revés.
create or replace function public.lp_sin_tildes(t text) returns text
language sql immutable set search_path = public as $$
  select translate(lower(coalesce(t, '')), 'áàäâéèëêíìïîóòöôúùüûñ', 'aaaaeeeeiiiioooouuuun')
$$;

-- Busca anuncios activos por título, descripción, categoría o vendedor.
-- Respeta las reglas de seguridad de siempre (solo devuelve lo que la persona puede ver).
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
      or public.lp_sin_tildes(l.description) like q.patron
      or public.lp_sin_tildes(l.category) like q.patron
      or exists (select 1 from public.profiles p
                 where p.id = l.seller_id and public.lp_sin_tildes(p.username) like q.patron)
    )
  order by (l.featured_until is not null and l.featured_until > now()) desc, l.created_at desc
  limit least(greatest(coalesce(p_lim, 60), 1), 200)
$$;
revoke all on function public.buscar_anuncios(text, text, int) from public;
grant execute on function public.buscar_anuncios(text, text, int) to anon, authenticated;

-- Fundador #1: lo tenía la cuenta de prueba "vintage_store1dkdkd"; se libera para un vendedor real.
update public.profiles set fundador_n = null, destacados_gratis = 0
  where username = 'vintage_store1dkdkd' and fundador_n is not null;

-- El número de fundador es el primer puesto libre (así un puesto liberado se reutiliza
-- sin chocar con los números ya dados).
create or replace function public.lp_dar_fundador(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_user is null or exists (select 1 from public.profiles where id = p_user and fundador_n is not null) then
    return;
  end if;
  perform pg_advisory_xact_lock(hashtext('pavito_fundadores'));
  select min(g) into n from generate_series(1, 200) g
    where not exists (select 1 from public.profiles where fundador_n = g);
  if n is null then return; end if;
  update public.profiles set fundador_n = n, destacados_gratis = destacados_gratis + 3
    where id = p_user and fundador_n is null and not coalesce(blocked, false);
  if found then
    perform public.avisar(p_user,
      '¡Eres el vendedor fundador #' || n || ' de Pavito! Tienes 3 destacados gratis.', 'perfil', null);
  end if;
end $$;
revoke all on function public.lp_dar_fundador(uuid) from public, anon, authenticated;
