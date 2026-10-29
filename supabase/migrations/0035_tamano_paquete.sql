-- El vendedor elige el tamaño del paquete (pequeño, mediano, grande) al publicar, como en Vinted.
-- Si no lo elige, se usa el que corresponde a la categoría.
alter table public.listings add column if not exists envio_tamano text;
do $$ begin
  alter table public.listings add constraint listings_envio_tamano_check
    check (envio_tamano is null or envio_tamano in ('chico', 'mediano', 'grande'));
exception when duplicate_object then null; end $$;
grant select (envio_tamano) on public.listings to anon, authenticated;
grant insert (envio_tamano) on public.listings to authenticated;
grant update (envio_tamano) on public.listings to authenticated;

create or replace function public.lp_envio_prenda(l public.listings, destino text, metodo text) returns numeric
language sql stable security definer set search_path = public as $$
  select case
    when l.envio_gratis then 0
    when coalesce(metodo, '') like 'Entrega en persona%' or coalesce(metodo, '') like 'Envío Yummy%' then 0
    else public.lp_tarifa_envio(coalesce(l.envio_tamano, public.lp_envio_tamano(l.category)), public.lp_zona(l.city, destino))
  end $$;
revoke all on function public.lp_envio_prenda(public.listings, text, text) from public, anon, authenticated;

create or replace function public.lp_envio_lote(p_listings uuid[], destino text, metodo text) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare v_gratis boolean; v_tam text; v_ciudad text;
begin
  if coalesce(metodo, '') like 'Entrega en persona%' or coalesce(metodo, '') like 'Envío Yummy%' then return 0; end if;
  select bool_and(envio_gratis),
         case when bool_or(coalesce(envio_tamano, public.lp_envio_tamano(category)) = 'grande') then 'grande'
              when bool_or(coalesce(envio_tamano, public.lp_envio_tamano(category)) = 'mediano') then 'mediano' else 'chico' end,
         min(city)
    into v_gratis, v_tam, v_ciudad
    from public.listings where id = any(p_listings);
  if v_tam is null or coalesce(v_gratis, false) then return 0; end if;
  return public.lp_tarifa_envio(v_tam, public.lp_zona(v_ciudad, destino));
end $$;
revoke all on function public.lp_envio_lote(uuid[], text, text) from public, anon, authenticated;
