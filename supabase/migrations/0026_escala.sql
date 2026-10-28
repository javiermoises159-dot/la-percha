-- 0026: preparar Pavito para crecer.
--  1. Buscador con índice de texto (pg_trgm): sigue rápido con decenas de miles de anuncios.
--  2. Chat en tiempo real: los mensajes nuevos se avisan al instante (Supabase Realtime).

create extension if not exists pg_trgm with schema extensions;

-- Texto donde se busca (título, marca, descripción y categoría, sin tildes y en minúsculas).
create or replace function public.lp_texto_anuncio(t text, b text, d text, c text) returns text
language sql immutable set search_path = public as $$
  select public.lp_sin_tildes(coalesce(t, '') || ' ' || coalesce(b, '') || ' ' || coalesce(d, '') || ' ' || coalesce(c, ''))
$$;

create index if not exists listings_busqueda_trgm on public.listings
  using gin (public.lp_texto_anuncio(title, brand, description, category) extensions.gin_trgm_ops);
create index if not exists profiles_usuario_trgm on public.profiles
  using gin (public.lp_sin_tildes(username) extensions.gin_trgm_ops);

create or replace function public.buscar_anuncios(p_q text, p_cat text default null, p_lim int default 60)
returns setof public.listings
language sql stable security invoker set search_path = public, extensions as $$
  with q as (
    -- % y _ se escapan (antes se borraban y "tienda_zara" no encontraba nada)
    select '%' || replace(replace(replace(public.lp_sin_tildes(left(btrim(coalesce(p_q, '')), 60)), '\', '\\'), '%', '\%'), '_', '\_') || '%' as patron
  ),
  coinciden as (
    select l.id from public.listings l, q
     where q.patron <> '%%'
       and public.lp_texto_anuncio(l.title, l.brand, l.description, l.category) like q.patron
    union
    select l.id from public.listings l join public.profiles p on p.id = l.seller_id, q
     where q.patron <> '%%' and public.lp_sin_tildes(p.username) like q.patron
  )
  select l.* from public.listings l, q
  where l.status = 'active'
    and (p_cat is null or p_cat = '' or l.category = p_cat)
    and (q.patron = '%%' or l.id in (select id from coinciden))
  order by (l.featured_until is not null and l.featured_until > now()) desc, l.orden desc
  limit least(greatest(coalesce(p_lim, 60), 1), 200)
$$;
revoke all on function public.buscar_anuncios(text, text, int) from public;
grant execute on function public.buscar_anuncios(text, text, int) to anon, authenticated;

-- Chat en tiempo real: Realtime solo envía filas que la persona puede leer (respeta RLS).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages') then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;
