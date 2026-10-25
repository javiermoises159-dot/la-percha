-- La Percha: ofertas, reseñas y modo vacaciones.
-- Todo lo importante pasa por funciones del servidor: la app no puede inventar
-- precios aceptados ni reseñas.

-- ============ Modo vacaciones ============
alter table public.profiles add column if not exists vacation boolean not null default false;
grant update (vacation) on public.profiles to authenticated;

-- Anuncios activos de vendedores de vacaciones o bloqueados: ocultos para los demás.
-- Los reservados y vendidos siguen visibles para que los pedidos muestren su título.
drop policy if exists listings_read on public.listings;
create policy listings_read on public.listings for select using (
  seller_id = auth.uid() or public.is_admin()
  or status in ('reserved','sold')
  or (status = 'active' and not exists (
        select 1 from public.profiles p where p.id = seller_id and (p.vacation or p.blocked))));

-- ============ Ofertas ============
create table if not exists public.offers (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  proposer_id uuid not null references public.profiles(id) on delete cascade,
  amount numeric(8,2) not null check (amount > 0),
  status text not null default 'pendiente'
    check (status in ('pendiente','aceptada','rechazada','usada','vencida')),
  created_at timestamptz not null default now(),
  responded_at timestamptz
);
create index if not exists offers_listing_buyer on public.offers (listing_id, buyer_id, created_at desc);
alter table public.offers enable row level security;
revoke all on public.offers from anon, authenticated;
grant select on public.offers to authenticated;
drop policy if exists offers_read on public.offers;
create policy offers_read on public.offers for select to authenticated
  using (auth.uid() in (buyer_id, seller_id) or public.is_admin());

-- Hacer una oferta (comprador) o una contraoferta (vendedor, indicando a qué comprador).
create or replace function public.make_offer(p_listing uuid, p_amount numeric, p_buyer uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare l public.listings; v_buyer uuid; v_thread uuid; v_id uuid; n int;
begin
  if auth.uid() is null or public.is_blocked() then raise exception 'No autorizado'; end if;
  select * into l from public.listings where id = p_listing;
  if l.id is null or l.status <> 'active' then raise exception 'La prenda no está disponible'; end if;
  if exists (select 1 from public.profiles where id = l.seller_id and (vacation or blocked)) then
    raise exception 'El vendedor no está disponible ahora';
  end if;
  if auth.uid() = l.seller_id then
    v_buyer := p_buyer;            -- contraoferta del vendedor
    if v_buyer is null then raise exception 'Falta el comprador'; end if;
  else
    v_buyer := auth.uid();         -- oferta del comprador
  end if;
  p_amount := round(p_amount, 2);
  if p_amount >= l.price then raise exception 'La oferta debe ser menor que el precio'; end if;
  if p_amount < round(l.price * 0.5, 2) then
    raise exception 'La oferta mínima es %', round(l.price * 0.5, 2);
  end if;
  select count(*) into n from public.offers
    where proposer_id = auth.uid() and created_at > now() - interval '1 hour';
  if n >= 20 then raise exception 'Demasiadas ofertas seguidas. Espera un momento.'; end if;

  -- Necesita una conversación entre ambos (el comprador la crea si no existe).
  select id into v_thread from public.threads where listing_id = p_listing and buyer_id = v_buyer;
  if v_thread is null then
    if auth.uid() = l.seller_id then raise exception 'Ese comprador no te ha escrito'; end if;
    insert into public.threads (listing_id, buyer_id, seller_id)
      values (p_listing, v_buyer, l.seller_id) returning id into v_thread;
  end if;

  -- Solo una oferta pendiente por conversación: la anterior vence.
  update public.offers set status = 'vencida', responded_at = now()
    where listing_id = p_listing and buyer_id = v_buyer and status = 'pendiente';
  insert into public.offers (listing_id, buyer_id, seller_id, proposer_id, amount)
    values (p_listing, v_buyer, l.seller_id, auth.uid(), p_amount) returning id into v_id;
  insert into public.messages (thread_id, text)
    values (v_thread, case when auth.uid() = l.seller_id then 'Contraoferta: $' else 'Oferta: $' end
                      || to_char(p_amount, 'FM999990.00'));
  return v_id;
end $$;

-- Aceptar o rechazar: solo la otra parte, y antes de 48 h.
create or replace function public.respond_offer(p_offer uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare o public.offers; v_thread uuid;
begin
  if auth.uid() is null or public.is_blocked() then raise exception 'No autorizado'; end if;
  select * into o from public.offers where id = p_offer for update;
  if o.id is null or auth.uid() not in (o.buyer_id, o.seller_id) then raise exception 'No autorizado'; end if;
  if o.proposer_id = auth.uid() then raise exception 'No puedes responder tu propia oferta'; end if;
  if o.status <> 'pendiente' then raise exception 'Esta oferta ya no está pendiente'; end if;
  if o.created_at < now() - interval '48 hours' then
    update public.offers set status = 'vencida', responded_at = now() where id = o.id;
    raise exception 'La oferta venció';
  end if;
  update public.offers set status = case when p_accept then 'aceptada' else 'rechazada' end,
                           responded_at = now() where id = o.id;
  select id into v_thread from public.threads where listing_id = o.listing_id and buyer_id = o.buyer_id;
  insert into public.messages (thread_id, text) values (v_thread,
    case when p_accept
      then 'Oferta aceptada: $' || to_char(o.amount, 'FM999990.00') || '. El comprador puede comprar a ese precio durante 48 h.'
      else 'Oferta rechazada.' end);
end $$;

-- Precio que pagaría quien pregunta (oferta aceptada vigente, o el del anuncio).
create or replace function public.my_price(p_listing uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select o.amount from public.offers o
      where o.listing_id = p_listing and o.buyer_id = auth.uid() and o.status = 'aceptada'
        and o.responded_at > now() - interval '48 hours'
      order by o.responded_at desc limit 1),
    (select price from public.listings where id = p_listing))
$$;

-- ============ Crear pedido: ahora respeta la oferta aceptada ============
create or replace function public.orders_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare l public.listings; pendientes int; v_offer public.offers;
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
  select count(*) into pendientes from public.orders
    where buyer_id = auth.uid() and status = 'esperando_pago';
  if pendientes >= 3 then
    raise exception 'Tienes 3 pedidos sin pagar. Págalos o cancélalos antes de pedir otro.';
  end if;
  select * into v_offer from public.offers
    where listing_id = l.id and buyer_id = auth.uid() and status = 'aceptada'
      and responded_at > now() - interval '48 hours'
    order by responded_at desc limit 1;
  new.price := coalesce(v_offer.amount, l.price);
  if v_offer.id is not null then
    update public.offers set status = 'usada' where id = v_offer.id;
  end if;
  new.buyer_id := auth.uid();
  new.seller_id := l.seller_id;
  new.fee := round((0.25 + new.price * 0.05)::numeric, 2);
  new.status := 'esperando_pago';
  new.pay_ref := null;
  new.tracking := null;
  return new;
end $$;

-- ============ Reseñas ============
create table if not exists public.reviews (
  order_id uuid not null references public.orders(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.profiles(id) on delete cascade,
  stars int not null check (stars between 1 and 5),
  text text not null default '' check (char_length(text) <= 300),
  created_at timestamptz not null default now(),
  primary key (order_id, author_id)
);
create index if not exists reviews_target on public.reviews (target_id, created_at desc);
alter table public.reviews enable row level security;
revoke all on public.reviews from anon, authenticated;
grant select on public.reviews to anon, authenticated;
drop policy if exists reviews_read on public.reviews;
create policy reviews_read on public.reviews for select using (true);

create or replace function public.leave_review(p_order uuid, p_stars int, p_text text default '')
returns void language plpgsql security definer set search_path = public as $$
declare o public.orders; v_target uuid;
begin
  if auth.uid() is null or public.is_blocked() then raise exception 'No autorizado'; end if;
  select * into o from public.orders where id = p_order;
  if o.id is null or auth.uid() not in (o.buyer_id, o.seller_id) then raise exception 'No autorizado'; end if;
  if o.status <> 'liberado' then raise exception 'Solo puedes opinar cuando el pedido está completado'; end if;
  if p_stars not between 1 and 5 then raise exception 'Elige de 1 a 5 estrellas'; end if;
  if exists (select 1 from public.reviews where order_id = o.id and author_id = auth.uid()) then
    raise exception 'Ya dejaste tu reseña de este pedido';
  end if;
  v_target := case when auth.uid() = o.buyer_id then o.seller_id else o.buyer_id end;
  insert into public.reviews (order_id, author_id, target_id, stars, text)
    values (o.id, auth.uid(), v_target, p_stars, left(btrim(coalesce(p_text, '')), 300));
  update public.profiles p set
    rating_count = s.n, rating_avg = s.avg
  from (select count(*)::int as n, round(avg(stars)::numeric, 2) as avg
        from public.reviews where target_id = v_target) s
  where p.id = v_target;
end $$;

-- ============ Mantenimiento: también vencen las ofertas ============
create or replace function public.orders_mantenimiento() returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.orders set status = 'cancelado'
    where status = 'esperando_pago' and created_at < now() - interval '24 hours';
  update public.orders set status = 'liberado'
    where status = 'enviado' and updated_at < now() - interval '7 days';
  update public.orders set delivery = null
    where delivery is not null and status in ('liberado','cancelado')
      and updated_at < now() - interval '30 days';
  update public.offers set status = 'vencida', responded_at = now()
    where (status = 'pendiente' and created_at < now() - interval '48 hours')
       or (status = 'aceptada' and responded_at < now() - interval '48 hours');
end $$;
revoke all on function public.orders_mantenimiento() from public, anon, authenticated;

-- ============ Permisos de las funciones ============
revoke all on function public.make_offer(uuid, numeric, uuid) from public, anon;
revoke all on function public.respond_offer(uuid, boolean) from public, anon;
revoke all on function public.my_price(uuid) from public, anon;
revoke all on function public.leave_review(uuid, int, text) from public, anon;
grant execute on function public.make_offer(uuid, numeric, uuid) to authenticated;
grant execute on function public.respond_offer(uuid, boolean) to authenticated;
grant execute on function public.my_price(uuid) to authenticated;
grant execute on function public.leave_review(uuid, int, text) to authenticated;
