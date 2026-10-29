-- Envío calculado dentro del pago (como en Vinted).
-- El envío depende del tamaño de la prenda (según su categoría) y de la zona
-- (misma ciudad, misma región o resto del país). Se suma al precio del pedido
-- (el vendedor lo recibe junto con la prenda y paga la guía) y NO paga tarifa de
-- protección. La tarifa de protección (0,25 USD + 5 %) se sigue calculando solo
-- sobre el precio de la prenda.

alter table public.orders add column if not exists envio numeric(8,2) not null default 0
  check (envio >= 0 and envio <= 100);
grant select (envio) on public.orders to authenticated;

-- Tarifas (USD). El admin las puede cambiar desde el panel.
insert into public.ajustes (clave, valor) values
  ('envio_chico_ciudad', 2.00),   ('envio_chico_region', 3.00),   ('envio_chico_pais', 4.00),
  ('envio_mediano_ciudad', 3.00), ('envio_mediano_region', 4.00), ('envio_mediano_pais', 5.50),
  ('envio_grande_ciudad', 4.00),  ('envio_grande_region', 5.50),  ('envio_grande_pais', 7.50)
on conflict (clave) do nothing;

-- Tamaño del paquete según la categoría.
create or replace function public.lp_envio_tamano(cat text) returns text
language sql immutable as $$
  select case
    when cat in ('Accesorios', 'Bebés', 'Libros y juegos', 'Mascotas') then 'chico'
    when cat in ('Zapatos', 'Hogar', 'Deportes') then 'grande'
    else 'mediano' end $$;

-- Región de cada ciudad.
create or replace function public.lp_region(ciudad text) returns text
language sql immutable as $$
  select case
    when ciudad in ('Caracas', 'Valencia', 'Maracay') then 'centro'
    when ciudad in ('Maracaibo', 'Barquisimeto', 'Mérida', 'San Cristóbal') then 'occidente'
    when ciudad in ('Puerto La Cruz', 'Ciudad Guayana', 'Isla de Margarita') then 'oriente'
    else null end $$;

create or replace function public.lp_zona(origen text, destino text) returns text
language sql immutable as $$
  select case
    when origen is not null and origen = destino then 'ciudad'
    when public.lp_region(origen) is not null and public.lp_region(origen) = public.lp_region(destino) then 'region'
    else 'pais' end $$;

-- Tarifa para un tamaño y una zona (si falta el ajuste, usa el valor del país).
create or replace function public.lp_tarifa_envio(tamano text, zona text) returns numeric
language sql stable security definer set search_path = public as $$
  select round(coalesce(
    (select valor from public.ajustes where clave = 'envio_' || tamano || '_' || zona),
    (select valor from public.ajustes where clave = 'envio_' || tamano || '_pais'),
    5), 2) $$;

-- Envío en USD de una prenda: 0 si el vendedor ofrece envío gratis o si se entrega en persona / Yummy.
create or replace function public.lp_envio_prenda(l public.listings, destino text, metodo text) returns numeric
language sql stable security definer set search_path = public as $$
  select case
    when l.envio_gratis then 0
    when coalesce(metodo, '') like 'Entrega en persona%' or coalesce(metodo, '') like 'Envío Yummy%' then 0
    else public.lp_tarifa_envio(public.lp_envio_tamano(l.category), public.lp_zona(l.city, destino))
  end $$;

-- Lo que ve el comprador antes de pagar.
create or replace function public.envio_estimado(p_listing uuid, p_ciudad text, p_metodo text)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare l public.listings;
begin
  if auth.uid() is null then return 0; end if;
  select * into l from public.listings where id = p_listing;
  if l.id is null then return 0; end if;
  return public.lp_envio_prenda(l, p_ciudad, p_metodo);
end $$;
revoke all on function public.envio_estimado(uuid, text, text) from public, anon;
grant execute on function public.envio_estimado(uuid, text, text) to authenticated;

-- Envío de un lote: uno solo, según el tamaño más grande entre los artículos.
create or replace function public.lp_envio_lote(p_listings uuid[], destino text, metodo text) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare v_gratis boolean; v_tam text; v_ciudad text;
begin
  if coalesce(metodo, '') like 'Entrega en persona%' or coalesce(metodo, '') like 'Envío Yummy%' then return 0; end if;
  select bool_and(envio_gratis),
         case when bool_or(public.lp_envio_tamano(category) = 'grande') then 'grande'
              when bool_or(public.lp_envio_tamano(category) = 'mediano') then 'mediano' else 'chico' end,
         min(city)
    into v_gratis, v_tam, v_ciudad
    from public.listings where id = any(p_listings);
  if v_tam is null or coalesce(v_gratis, false) then return 0; end if;
  return public.lp_tarifa_envio(v_tam, public.lp_zona(v_ciudad, destino));
end $$;

create or replace function public.envio_estimado_lote(p_listings uuid[], p_ciudad text, p_metodo text)
returns numeric language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then return 0; end if;
  return public.lp_envio_lote(p_listings, p_ciudad, p_metodo);
end $$;
revoke all on function public.envio_estimado_lote(uuid[], text, text) from public, anon;
grant execute on function public.envio_estimado_lote(uuid[], text, text) to authenticated;
revoke all on function public.lp_envio_lote(uuid[], text, text) from public, anon, authenticated;
revoke all on function public.lp_envio_prenda(public.listings, text, text) from public, anon, authenticated;
revoke all on function public.lp_tarifa_envio(text, text) from public, anon, authenticated;

-- El admin cambia una tarifa.
create or replace function public.admin_set_envio(p_clave text, p_valor numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_clave !~ '^envio_(chico|mediano|grande)_(ciudad|region|pais)$' then raise exception 'Tarifa no válida'; end if;
  if p_valor is null or p_valor < 0 or p_valor > 50 then raise exception 'La tarifa debe estar entre 0 y 50 USD'; end if;
  update public.ajustes set valor = round(p_valor, 2), actualizado = now() where clave = p_clave;
end $$;
revoke all on function public.admin_set_envio(text, numeric) from public, anon;
grant execute on function public.admin_set_envio(text, numeric) to authenticated;

-- Pedido: el envío se suma al precio; la tarifa de protección sigue sobre la prenda.
create or replace function public.orders_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare l public.listings; pendientes int; v_offer public.offers; v_base numeric; v_envio numeric := 0;
        v_destino text := nullif(new.delivery->>'ciudad', '');
        v_metodo text := new.delivery->>'metodo';
        v_lote uuid := nullif(current_setting('lapercha.lote_id', true), '')::uuid;
        v_pct int := coalesce(nullif(current_setting('lapercha.lote_pct', true), '')::int, 0);
begin
  select * into l from public.listings where id = new.listing_id for update;
  if l.id is null or l.status <> 'active' then
    raise exception 'La prenda no está disponible';
  end if;
  if l.seller_id = auth.uid() then
    raise exception 'No puedes comprar tu propia prenda';
  end if;
  if exists (select 1 from public.profiles where id = l.seller_id and (vacation or blocked)) then
    raise exception 'El vendedor no está disponible ahora';
  end if;
  select count(distinct coalesce(bundle_id, id)) into pendientes from public.orders
    where buyer_id = auth.uid() and status = 'esperando_pago'
      and coalesce(bundle_id, id) is distinct from v_lote;
  if pendientes >= 3 then
    raise exception 'Tienes 3 pedidos sin pagar. Págalos o cancélalos antes de pedir otro.';
  end if;

  if v_lote is not null then
    if current_setting('lapercha.lote_primero', true) = '1' then
      new.id := v_lote;
    end if;
    new.bundle_id := v_lote;
    v_base := round(l.price * (100 - v_pct) / 100.0, 2);
    new.fee := round(case when new.id = v_lote then 0.25 else 0 end + v_base * 0.05, 2);
    -- Un solo envío por lote, en el pedido principal (lo calcula create_bundle).
    if new.id = v_lote then
      v_envio := coalesce(nullif(current_setting('lapercha.lote_envio', true), '')::numeric, 0);
    end if;
  else
    select * into v_offer from public.offers
      where listing_id = l.id and buyer_id = auth.uid() and status = 'aceptada'
        and responded_at > now() - interval '48 hours'
      order by responded_at desc limit 1;
    v_base := coalesce(v_offer.amount, l.price);
    if v_offer.id is not null then
      update public.offers set status = 'usada' where id = v_offer.id;
    end if;
    new.bundle_id := null;
    new.fee := round((0.25 + v_base * 0.05)::numeric, 2);
    v_envio := public.lp_envio_prenda(l, v_destino, v_metodo);
  end if;
  new.envio := v_envio;
  new.price := round(v_base + v_envio, 2);
  new.buyer_id := auth.uid();
  new.seller_id := l.seller_id;
  new.status := 'esperando_pago';
  new.pay_ref := null;
  new.tracking := null;
  new.paid_out_at := null;
  return new;
end $$;

-- Lote: calcula un solo envío (tamaño más grande entre los artículos).
create or replace function public.create_bundle(p_listings uuid[], p_delivery jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare n int := coalesce(array_length(p_listings, 1), 0); v_seller uuid; v_pct int;
        p public.profiles; v_lote uuid := gen_random_uuid(); i int;
        v_envio numeric := 0;
begin
  if auth.uid() is null or public.is_blocked() then raise exception 'No autorizado'; end if;
  if n < 2 or n > 10 then raise exception 'Un lote lleva de 2 a 10 artículos'; end if;
  if (select count(distinct x) from unnest(p_listings) x) <> n then raise exception 'Artículos repetidos'; end if;
  select min(seller_id::text)::uuid, count(distinct seller_id) into v_seller, i
    from public.listings where id = any(p_listings);
  if i <> 1 then raise exception 'Todos los artículos deben ser del mismo vendedor'; end if;
  select * into p from public.profiles where id = v_seller;
  v_pct := case when n >= 5 and p.lote_5 > 0 then p.lote_5
                when n >= 3 and p.lote_3 > 0 then p.lote_3
                else p.lote_2 end;
  v_envio := public.lp_envio_lote(p_listings, nullif(p_delivery->>'ciudad', ''), p_delivery->>'metodo');
  perform set_config('lapercha.lote_id', v_lote::text, true);
  perform set_config('lapercha.lote_pct', v_pct::text, true);
  perform set_config('lapercha.lote_envio', v_envio::text, true);
  for i in 1..n loop
    perform set_config('lapercha.lote_primero', case when i = 1 then '1' else '0' end, true);
    insert into public.orders (listing_id, price, delivery) values (p_listings[i], 1, p_delivery);
  end loop;
  perform set_config('lapercha.lote_id', '', true);
  perform set_config('lapercha.lote_pct', '', true);
  perform set_config('lapercha.lote_envio', '', true);
  perform set_config('lapercha.lote_primero', '', true);
  return v_lote;
end $$;
revoke all on function public.create_bundle(uuid[], jsonb) from public, anon;
grant execute on function public.create_bundle(uuid[], jsonb) to authenticated;
