-- La Percha: lotes con descuento, saldo y pagos a vendedores, preferencias y denuncias.

-- ============ Descuentos por lote del vendedor (porcentaje) ============
alter table public.profiles
  add column if not exists lote_2 int not null default 0 check (lote_2 between 0 and 50),
  add column if not exists lote_3 int not null default 0 check (lote_3 between 0 and 50),
  add column if not exists lote_5 int not null default 0 check (lote_5 between 0 and 50);
grant update (lote_2, lote_3, lote_5) on public.profiles to authenticated;

-- ============ Pedidos: lote y pago al vendedor ============
alter table public.orders
  add column if not exists bundle_id uuid,
  add column if not exists paid_out_at timestamptz;
create index if not exists orders_bundle on public.orders (bundle_id) where bundle_id is not null;
grant select (bundle_id, paid_out_at) on public.orders to authenticated;

-- Una referencia de pago vale para un solo pedido o un solo lote.
drop index if exists public.orders_pay_ref_unica;

create or replace function public.lp_ref_usada(p_ref text, p_grupo uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.orders o
                 where lower(btrim(o.pay_ref)) = lower(btrim(p_ref)) and o.status <> 'cancelado'
                   and coalesce(o.bundle_id, o.id) <> p_grupo)
      or exists (select 1 from public.promotions p
                 where lower(btrim(p.pay_ref)) = lower(btrim(p_ref)) and p.status <> 'rechazada')
$$;
revoke all on function public.lp_ref_usada(text, uuid) from public, anon, authenticated;

create or replace function public.orders_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if new.pay_ref is not null and new.pay_ref is distinct from old.pay_ref
     and public.lp_ref_usada(new.pay_ref, coalesce(new.bundle_id, new.id)) then
    raise exception 'Esa referencia de pago ya se usó';
  end if;
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if new.id <> old.id or new.listing_id <> old.listing_id or new.buyer_id <> old.buyer_id
     or new.seller_id <> old.seller_id or new.price <> old.price or new.fee <> old.fee
     or new.created_at <> old.created_at
     or new.bundle_id is distinct from old.bundle_id
     or new.paid_out_at is distinct from old.paid_out_at then
    raise exception 'Campos protegidos';
  end if;

  if auth.uid() = old.buyer_id then
    if new.tracking is distinct from old.tracking then
      raise exception 'Solo el vendedor puede poner el seguimiento';
    end if;
    if (new.pay_ref is distinct from old.pay_ref or new.delivery is distinct from old.delivery)
       and old.status <> 'esperando_pago' then
      raise exception 'Ya no puedes cambiar el pago ni la entrega de este pedido';
    end if;
    if new.status <> old.status and not (
         (old.status = 'esperando_pago' and new.status in ('revision','cancelado'))
      or (old.status = 'enviado' and new.status in ('liberado','disputa'))) then
      raise exception 'Cambio de estado no permitido';
    end if;
    if new.status = 'revision' and coalesce(btrim(new.pay_ref), '') = '' then
      raise exception 'Escribe la referencia del Pago Móvil';
    end if;
  elsif auth.uid() = old.seller_id then
    if new.pay_ref is distinct from old.pay_ref or new.delivery is distinct from old.delivery then
      raise exception 'Campos del comprador';
    end if;
    if new.tracking is distinct from old.tracking and old.status not in ('retenido','enviado') then
      raise exception 'Solo puedes poner el seguimiento cuando el pago está confirmado';
    end if;
    if new.status <> old.status and not (
         (old.status = 'retenido' and new.status = 'enviado')
      or (old.status = 'esperando_pago' and new.status = 'cancelado')) then
      raise exception 'Cambio de estado no permitido';
    end if;
    if new.status = 'enviado' and coalesce(btrim(new.tracking), '') = '' then
      raise exception 'Escribe el número de seguimiento del envío';
    end if;
  else
    raise exception 'No autorizado';
  end if;
  return new;
end $$;

-- Crear pedido: modo lote (solo desde create_bundle) o normal.
create or replace function public.orders_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare l public.listings; pendientes int; v_offer public.offers;
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
    -- Lote: precio con el descuento del vendedor; la parte fija de la tarifa, una sola vez.
    if current_setting('lapercha.lote_primero', true) = '1' then
      new.id := v_lote;
    end if;
    new.bundle_id := v_lote;
    new.price := round(l.price * (100 - v_pct) / 100.0, 2);
    new.fee := round(case when new.id = v_lote then 0.25 else 0 end + new.price * 0.05, 2);
  else
    select * into v_offer from public.offers
      where listing_id = l.id and buyer_id = auth.uid() and status = 'aceptada'
        and responded_at > now() - interval '48 hours'
      order by responded_at desc limit 1;
    new.price := coalesce(v_offer.amount, l.price);
    if v_offer.id is not null then
      update public.offers set status = 'usada' where id = v_offer.id;
    end if;
    new.bundle_id := null;
    new.fee := round((0.25 + new.price * 0.05)::numeric, 2);
  end if;
  new.buyer_id := auth.uid();
  new.seller_id := l.seller_id;
  new.status := 'esperando_pago';
  new.pay_ref := null;
  new.tracking := null;
  new.paid_out_at := null;
  return new;
end $$;

-- Comprar varias cosas del mismo vendedor en un solo pedido.
create or replace function public.create_bundle(p_listings uuid[], p_delivery jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare n int := coalesce(array_length(p_listings, 1), 0); v_seller uuid; v_pct int;
        p public.profiles; v_lote uuid := gen_random_uuid(); i int;
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
  perform set_config('lapercha.lote_id', v_lote::text, true);
  perform set_config('lapercha.lote_pct', v_pct::text, true);
  for i in 1..n loop
    perform set_config('lapercha.lote_primero', case when i = 1 then '1' else '0' end, true);
    insert into public.orders (listing_id, price, delivery) values (p_listings[i], 1, p_delivery);
  end loop;
  perform set_config('lapercha.lote_id', '', true);
  perform set_config('lapercha.lote_pct', '', true);
  perform set_config('lapercha.lote_primero', '', true);
  return v_lote;
end $$;
revoke all on function public.create_bundle(uuid[], jsonb) from public, anon;
grant execute on function public.create_bundle(uuid[], jsonb) to authenticated;

-- Avisos: en un lote, un solo aviso (el del primer pedido) con el número de artículos.
create or replace function public.avisos_pedido() returns trigger
language plpgsql security definer set search_path = public as $$
declare titulo text; n int;
begin
  if new.bundle_id is not null and new.id <> new.bundle_id then return new; end if;
  if new.bundle_id is not null then
    select count(*) into n from public.orders where bundle_id = new.bundle_id;
    titulo := 'tu lote';
    if tg_op = 'INSERT' then titulo := 'un lote'; end if;
  else
    select '"' || coalesce(title, 'tu artículo') || '"' into titulo from public.listings where id = new.listing_id;
  end if;
  if tg_op = 'INSERT' then
    perform public.avisar(new.seller_id, '¡Alguien quiere ' || titulo || '! Esperando su pago.', 'pedido', new.id);
    return new;
  end if;
  if new.status is not distinct from old.status then return new; end if;
  case new.status
    when 'revision' then
      perform public.avisar(new.seller_id, 'El comprador pagó ' || titulo || '. Lo estamos verificando.', 'pedido', new.id);
    when 'retenido' then
      perform public.avisar(new.seller_id, 'Pago confirmado de ' || titulo || '. Ya puedes enviarlo.', 'pedido', new.id);
      perform public.avisar(new.buyer_id, 'Confirmamos tu pago de ' || titulo || '.', 'pedido', new.id);
    when 'enviado' then
      perform public.avisar(new.buyer_id, initcap(left(titulo, 1)) || substr(titulo, 2) || ' va en camino. Confirma cuando lo recibas.', 'pedido', new.id);
    when 'liberado' then
      perform public.avisar(new.seller_id, 'Venta completada: ' || titulo || '. ¡Deja tu reseña!', 'pedido', new.id);
      perform public.avisar(new.buyer_id, 'Pedido completado: ' || titulo || '. ¡Deja tu reseña!', 'pedido', new.id);
    when 'disputa' then
      perform public.avisar(new.seller_id, 'El comprador reportó un problema con ' || titulo || '.', 'pedido', new.id);
    when 'cancelado' then
      perform public.avisar(new.seller_id, 'Se canceló el pedido de ' || titulo || '.', 'pedido', new.id);
      perform public.avisar(new.buyer_id, 'Se canceló el pedido de ' || titulo || '.', 'pedido', new.id);
    else null;
  end case;
  return new;
end $$;

-- ============ Pago al vendedor (lo marca el admin) ============
create or replace function public.admin_mark_paid(p_order uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g uuid;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  select coalesce(bundle_id, id) into g from public.orders where id = p_order;
  update public.orders set paid_out_at = now()
    where coalesce(bundle_id, id) = g and status = 'liberado' and paid_out_at is null;
  perform public.avisar((select seller_id from public.orders where id = p_order),
    'Te enviamos el pago de tu venta. Revisa tu Pago Móvil.', 'pedido', p_order);
end $$;
revoke all on function public.admin_mark_paid(uuid) from public, anon;
grant execute on function public.admin_mark_paid(uuid) to authenticated;

-- ============ Preferencias (ciudad y categorías favoritas) ============
alter table public.private_profiles add column if not exists prefs jsonb;
alter table public.private_profiles drop constraint if exists private_tamano;
alter table public.private_profiles add constraint private_tamano check (
  pg_column_size(coalesce(payout, '{}'::jsonb)) < 2000
  and pg_column_size(coalesce(address, '{}'::jsonb)) < 2000
  and pg_column_size(coalesce(prefs, '{}'::jsonb)) < 2000) not valid;

-- ============ Denuncias: motivo de una lista, una por persona y anuncio ============
alter table public.reports add column if not exists status text not null default 'abierta'
  check (status in ('abierta','revisada'));
do $$ begin
  create unique index if not exists reports_una_por_anuncio on public.reports (reporter_id, listing_id)
    where listing_id is not null;
  create unique index if not exists reports_una_por_usuario on public.reports (reporter_id, user_id)
    where user_id is not null and listing_id is null;
exception when others then raise notice '%', sqlerrm; end $$;
create or replace function public.reports_check() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.reporter_id := auth.uid();
  new.status := 'abierta';
  if new.listing_id is null and new.user_id is null then raise exception 'Falta qué denuncias'; end if;
  if new.listing_id is not null then
    new.user_id := (select seller_id from public.listings where id = new.listing_id);
  end if;
  if new.user_id = auth.uid() then raise exception 'No puedes denunciarte a ti mismo'; end if;
  return new;
end $$;
drop trigger if exists reports_check on public.reports;
create trigger reports_check before insert on public.reports
  for each row execute function public.reports_check();

create or replace function public.admin_close_report(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  update public.reports set status = 'revisada' where id = p_id;
end $$;
revoke all on function public.admin_close_report(uuid) from public, anon;
grant execute on function public.admin_close_report(uuid) to authenticated;
