-- La Percha: tarifa de protección del comprador = 0,25 USD + 5 %.
-- Se calcula en el servidor, así que nadie puede cambiarla desde la app.
create or replace function public.orders_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare l public.listings;
begin
  select * into l from public.listings where id = new.listing_id;
  if l.id is null or l.status <> 'active' then
    raise exception 'La prenda no está disponible';
  end if;
  if l.seller_id = auth.uid() then
    raise exception 'No puedes comprar tu propia prenda';
  end if;
  if new.price > l.price or new.price < l.price * 0.5 then
    raise exception 'Precio no válido';
  end if;
  new.buyer_id := auth.uid();
  new.seller_id := l.seller_id;
  new.fee := round((0.25 + new.price * 0.05)::numeric, 2);
  new.status := 'esperando_pago';
  return new;
end $$;
