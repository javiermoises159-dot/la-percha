-- La Percha: blindaje de compras, privacidad y antiestafas.
-- Se aplica sola con Codemagic (supabase db push) o pegándola en SQL Editor.
--
-- Corrige:
--  1. El comprador ya no puede fijar su propio precio (antes aceptaba hasta un 50 % menos).
--  2. Una prenda no se puede vender dos veces: el anuncio se reserva al crear el pedido.
--  3. El vendedor no puede tocar un anuncio con pedido en curso.
--  4. El vendedor solo ve teléfono y dirección del comprador cuando el pago está confirmado.
--  5. Una referencia de Pago Móvil no sirve para dos pedidos.
--  6. Pedidos sin pagar caducan (24 h) y los enviados se liberan solos a los 7 días sin queja.
--  7. Las fotos solo pueden venir del almacenamiento de La Percha (no de webs externas).
--  8. Los chats marcan mensajes que piden pagar o hablar fuera de la app.
--  9. Nombres de usuario sin suplantaciones (mayúsculas, "admin", "lapercha"...).

-- ============ Ayuda: cambios hechos por el propio sistema ============
-- Los disparadores del sistema encienden esta marca para poder mover el estado
-- de un anuncio reservado sin que el guardián de anuncios lo impida.
create or replace function public.lp_sistema() returns boolean
language sql stable set search_path = public as $$
  select coalesce(current_setting('lapercha.sistema', true), '') = '1'
$$;

-- ============ 1 y 2. Crear pedido ============
create or replace function public.orders_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare l public.listings; pendientes int;
begin
  -- "for update" bloquea la fila: si dos personas compran a la vez, la segunda espera
  -- y luego ve el anuncio ya reservado.
  select * into l from public.listings where id = new.listing_id for update;
  if l.id is null or l.status <> 'active' then
    raise exception 'La prenda no está disponible';
  end if;
  if l.seller_id = auth.uid() then
    raise exception 'No puedes comprar tu propia prenda';
  end if;
  select count(*) into pendientes from public.orders
    where buyer_id = auth.uid() and status = 'esperando_pago';
  if pendientes >= 3 then
    raise exception 'Tienes 3 pedidos sin pagar. Págalos o cancélalos antes de pedir otro.';
  end if;
  -- El precio lo pone el servidor, nunca la app.
  new.price := l.price;
  new.buyer_id := auth.uid();
  new.seller_id := l.seller_id;
  new.fee := round((0.25 + new.price * 0.05)::numeric, 2);
  new.status := 'esperando_pago';
  new.pay_ref := null;
  new.tracking := null;
  return new;
end $$;

create or replace function public.orders_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('lapercha.sistema', '1', true);
  update public.listings set status = 'reserved' where id = new.listing_id;
  perform set_config('lapercha.sistema', '', true);
  return new;
end $$;
drop trigger if exists orders_after_insert on public.orders;
create trigger orders_after_insert after insert on public.orders
  for each row execute function public.orders_after_insert();

-- Solo un pedido vivo por prenda (segunda barrera además del bloqueo).
do $$ begin
  create unique index if not exists orders_un_pedido_por_prenda
    on public.orders (listing_id) where status <> 'cancelado';
exception when others then
  raise notice 'No se creó orders_un_pedido_por_prenda: %', sqlerrm;
end $$;

-- ============ 5. Referencia de pago única ============
do $$ begin
  create unique index if not exists orders_pay_ref_unica
    on public.orders (lower(btrim(pay_ref))) where pay_ref is not null and status <> 'cancelado';
exception when others then
  raise notice 'No se creó orders_pay_ref_unica: %', sqlerrm;
end $$;

alter table public.orders drop constraint if exists orders_campos_largo;
alter table public.orders add constraint orders_campos_largo check (
  (pay_ref is null or char_length(pay_ref) between 4 and 40)
  and (tracking is null or char_length(tracking) between 3 and 100)
  and (delivery is null or pg_column_size(delivery) < 2000)
) not valid;

-- ============ Cambios de estado del pedido ============
create or replace function public.orders_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  -- auth.uid() nulo = el dueño desde el panel de Supabase o una tarea programada.
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if new.id <> old.id or new.listing_id <> old.listing_id or new.buyer_id <> old.buyer_id
     or new.seller_id <> old.seller_id or new.price <> old.price or new.fee <> old.fee
     or new.created_at <> old.created_at then
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

-- El anuncio sigue al pedido (con la marca de sistema encendida).
create or replace function public.orders_after_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    perform set_config('lapercha.sistema', '1', true);
    update public.listings set status = case
      when new.status in ('esperando_pago','revision','retenido','enviado','disputa') then 'reserved'
      when new.status = 'liberado' then 'sold'
      when new.status = 'cancelado' and status = 'reserved' then 'active'
      else status end
    where id = new.listing_id;
    perform set_config('lapercha.sistema', '', true);
  end if;
  return new;
end $$;

-- ============ 3. Anuncios con pedido: congelados ============
create or replace function public.listings_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_admin() or public.lp_sistema() then
    return new;
  end if;
  if new.seller_id <> old.seller_id or new.created_at <> old.created_at then
    raise exception 'Campos protegidos';
  end if;
  if old.status in ('reserved','sold') then
    raise exception 'Este anuncio tiene un pedido y no se puede cambiar';
  end if;
  if new.status not in ('active','hidden') then
    raise exception 'Estado no permitido';
  end if;
  return new;
end $$;
drop trigger if exists listings_guard on public.listings;
create trigger listings_guard before update on public.listings
  for each row execute function public.listings_guard();

-- ============ 4. Dirección y teléfono del comprador ============
-- Nadie lee "delivery" directamente; se pide con esta función, que solo la da
-- al comprador, al admin, o al vendedor cuando el pago ya está confirmado.
revoke select on public.orders from authenticated;
grant select (id, listing_id, buyer_id, seller_id, price, fee, status, pay_ref,
              tracking, created_at, updated_at) on public.orders to authenticated;

create or replace function public.order_delivery(oid uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select o.delivery from public.orders o
  where o.id = oid and (
    o.buyer_id = auth.uid() or public.is_admin()
    or (o.seller_id = auth.uid() and o.status in ('retenido','enviado','liberado','disputa')))
$$;
revoke all on function public.order_delivery(uuid) from public, anon;
grant execute on function public.order_delivery(uuid) to authenticated;

-- ============ 6. Caducidad y liberación automática ============
create or replace function public.orders_mantenimiento() returns void
language plpgsql security definer set search_path = public as $$
begin
  -- Sin pagar en 24 h: se cancela y la prenda vuelve a estar a la venta.
  update public.orders set status = 'cancelado'
    where status = 'esperando_pago' and created_at < now() - interval '24 hours';
  -- Enviado hace 7 días sin queja: se libera el pago al vendedor.
  update public.orders set status = 'liberado'
    where status = 'enviado' and updated_at < now() - interval '7 days';
  -- Privacidad: se borra la dirección 30 días después de terminar.
  update public.orders set delivery = null
    where delivery is not null and status in ('liberado','cancelado')
      and updated_at < now() - interval '30 days';
end $$;
revoke all on function public.orders_mantenimiento() from public, anon, authenticated;

-- Se ejecuta cada 15 minutos si el proyecto tiene pg_cron (Supabase lo incluye).
do $$ begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'lapercha_mantenimiento';
  perform cron.schedule('lapercha_mantenimiento', '*/15 * * * *',
                        'select public.orders_mantenimiento()');
exception when others then
  raise notice 'pg_cron no disponible (%). Activa la extensión pg_cron en Supabase.', sqlerrm;
end $$;

-- ============ 7. Fotos solo de nuestro almacenamiento ============
create or replace function public.listings_check_photos() returns trigger
language plpgsql set search_path = public as $$
declare p text;
begin
  foreach p in array new.photos loop
    if p not like ('https://udhyuyokrxggdnnepbmr.supabase.co/storage/v1/object/public/listing-photos/'
                   || new.seller_id::text || '/%')
       or p ~ '[?#]|\.\.' then
      raise exception 'Foto no válida';
    end if;
  end loop;
  return new;
end $$;

-- ============ 8. Chats: resumen fiable y aviso antiestafa ============
alter table public.messages add column if not exists aviso boolean not null default false;

create or replace function public.messages_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare t text := lower(new.text);
begin
  new.sender_id := auth.uid();
  new.created_at := now();
  -- Teléfonos, correos, enlaces o pagos fuera de la app: se marca para avisar.
  new.aviso := t ~ '(\d[\s.-]?){7,}'
    or t ~ '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}'
    or t ~ '(https?://|www\.|wa\.me|t\.me|bit\.ly)'
    or t ~ '(whats ?app|wasap|telegram|instagram|zelle|paypal|binance|pago ?m[oó]vil|transferencia|efectivo|fuera de la app)';
  return new;
end $$;
drop trigger if exists messages_before_insert on public.messages;
create trigger messages_before_insert before insert on public.messages
  for each row execute function public.messages_before_insert();

-- El resumen del chat lo escribe el servidor, no la app (evita mensajes falsos en la lista).
create or replace function public.messages_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.threads
    set last_message = left(new.text, 80), last_at = new.created_at
    where id = new.thread_id;
  return new;
end $$;
drop trigger if exists messages_after_insert on public.messages;
create trigger messages_after_insert after insert on public.messages
  for each row execute function public.messages_after_insert();

revoke update on public.threads from authenticated;

-- ============ 9. Nombres de usuario ============
do $$ begin
  create unique index if not exists profiles_username_ci on public.profiles (lower(username));
exception when others then
  raise notice 'No se creó profiles_username_ci: %', sqlerrm;
end $$;

create or replace function public.profiles_check_username() returns trigger
language plpgsql set search_path = public as $$
declare u text := lower(regexp_replace(new.username, '[._0-9]', '', 'g'));
begin
  if new.username !~ '^[A-Za-z0-9_.]{3,20}$' then
    raise exception 'Usa de 3 a 20 letras, números, punto o guion bajo';
  end if;
  if (tg_op = 'INSERT' or new.username is distinct from old.username)
     and not coalesce(public.is_admin(), false)
     and u ~ '(admin|lapercha|percha|soporte|support|moderador|oficial|staff)' then
    raise exception 'Ese nombre de usuario está reservado';
  end if;
  return new;
end $$;
drop trigger if exists profiles_check_username on public.profiles;
create trigger profiles_check_username before insert or update of username on public.profiles
  for each row execute function public.profiles_check_username();

-- ============ Funciones internas: no se pueden llamar desde la app ============
revoke all on function public.lp_sistema() from public, anon, authenticated;
