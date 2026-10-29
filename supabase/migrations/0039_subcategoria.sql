-- Tipo de artículo dentro de cada categoría (Franela, Pantalón…). Opcional.
alter table public.listings add column if not exists subcategoria text check (char_length(subcategoria) <= 40);
grant select (subcategoria) on public.listings to anon, authenticated;
grant insert (subcategoria) on public.listings to authenticated;
grant update (subcategoria) on public.listings to authenticated;
