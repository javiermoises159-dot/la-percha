-- 0023: devoluciones dentro de la app.
-- Si un reclamo termina en devolución, el equipo de Pavito la pide desde el panel:
--  1. El comprador tiene 3 días hábiles para enviar la prenda de vuelta y poner la guía.
--  2. El vendedor confirma que la recibió y el dinero vuelve al Saldo Pavito del comprador.
--     Si el vendedor no confirma en 7 días desde el envío, el reembolso se hace solo.
--  3. Si el comprador no la envía a tiempo, el pedido se cierra a favor del vendedor.

alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check check (status in
  ('esperando_pago','revision','retenido','enviado','liberado','disputa','cancelado','devolucion'));

alter table public.orders add column if not exists devolucion_at timestamptz;
alter table public.orders add column if not exists guia_devolucion text;
alter table public.orders add column if not exists devuelta_enviada_at timestamptz;
do $$ begin
  alter table public.orders add constraint orders_guia_devolucion_largo check (guia_devolucion is null or char_length(guia_devolucion) <= 80);
exception when duplicate_object then null; end $$;
grant select (devolucion_at, guia_devolucion, devuelta_enviada_at) on public.orders to authenticated;
grant update (guia_devolucion) on public.orders to authenticated;

-- Fechas de la devolución: las pone el servidor. Va antes que el movimiento de dinero.
create or replace function public.orders_zdevolucion() returns trigger
language plpgsql security definer set search_path = public as $$
declare titulo text;
begin
  new.devolucion_at := old.devolucion_at;
  new.devuelta_enviada_at := old.devuelta_enviada_at;
  if new.status = 'devolucion' and old.status is distinct from 'devolucion' then
    new.devolucion_at := now();
    new.guia_devolucion := null;
  end if;
  select '"' || coalesce(title, 'tu artículo') || '"' into titulo from public.listings where id = new.listing_id;
  if new.guia_devolucion is not null and old.guia_devolucion is null then
    new.devuelta_enviada_at := now();
    perform public.avisar(new.seller_id, 'El comprador te devolvió ' || titulo || ' (guía ' || left(new.guia_devolucion, 40)
      || '). Cuando la recibas, confírmalo en el pedido.', 'pedido', new.id);
  end if;
  if new.status = 'devolucion' and old.status is distinct from 'devolucion' then
    perform public.avisar(new.buyer_id, 'Resolvimos tu reclamo de ' || titulo || ': devuelve la prenda al vendedor en 3 días hábiles '
      || 'y escribe la guía en el pedido. Al recibirla, te devolvemos el dinero.', 'pedido', new.id);
    perform public.avisar(new.seller_id, 'El reclamo de ' || titulo || ' termina en devolución: el comprador te enviará la prenda. '
      || 'Coordinen el envío por el chat.', 'pedido', new.id);
  end if;
  return new;
end $$;
revoke all on function public.orders_zdevolucion() from public, anon, authenticated;
drop trigger if exists orders_zdevolucion on public.orders;
create trigger orders_zdevolucion before update on public.orders
  for each row execute function public.orders_zdevolucion();

-- ============ Reglas del pedido con la devolución ============
create or replace function public.orders_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if new.pay_ref is not null and new.pay_ref is distinct from old.pay_ref
     and public.lp_ref_usada(new.pay_ref, coalesce(new.bundle_id, new.id)) then
    raise exception 'Esa referencia de pago ya se usó';
  end if;
  if auth.uid() is null or public.is_admin()
     or coalesce(current_setting('pavito.pago_saldo', true), '') = 'si' then
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
    if new.guia_devolucion is distinct from old.guia_devolucion then
      if old.status <> 'devolucion' or old.guia_devolucion is not null then
        raise exception 'Solo puedes poner la guía de la devolución una vez, cuando Pavito la pide';
      end if;
      if char_length(btrim(coalesce(new.guia_devolucion, ''))) < 3 then
        raise exception 'Escribe la empresa y el número de guía de la devolución';
      end if;
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
    if new.guia_devolucion is distinct from old.guia_devolucion then
      raise exception 'La guía de la devolución la pone el comprador';
    end if;
    if new.status <> old.status and not (
         (old.status = 'retenido' and new.status = 'enviado')
      or (old.status = 'esperando_pago' and new.status = 'cancelado')
      or (old.status = 'devolucion' and old.guia_devolucion is not null and new.status in ('cancelado','disputa'))) then
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

-- ============ Plazos de la devolución (cada 15 minutos) ============
create or replace function public.devoluciones_mantenimiento() returns void
language plpgsql security definer set search_path = public as $$
begin
  -- El comprador no envió la devolución a tiempo: se cierra a favor del vendedor.
  update public.orders set status = 'liberado'
    where status = 'devolucion' and guia_devolucion is null
      and now() > public.lp_mas_habiles(devolucion_at, 3);
  -- El vendedor no confirmó en 7 días desde el envío: se reembolsa al comprador.
  update public.orders set status = 'cancelado'
    where status = 'devolucion' and guia_devolucion is not null
      and devuelta_enviada_at < now() - interval '7 days';
end $$;
revoke all on function public.devoluciones_mantenimiento() from public, anon, authenticated;
do $$ begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'pavito_devoluciones';
  perform cron.schedule('pavito_devoluciones', '*/15 * * * *', 'select public.devoluciones_mantenimiento()');
exception when others then
  raise notice 'Plazos de devolución no programados (%).', sqlerrm;
end $$;

-- ============ El dinero en devolución sigue retenido ============
create or replace function public.admin_cuadre() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare j jsonb; dest numeric; saldos numeric; retiros_p numeric;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  select coalesce(sum(amount), 0) into dest from public.promotions where status = 'activa';
  select coalesce(sum(monto), 0) into saldos from public.movimientos;
  select coalesce(sum(monto), 0) into retiros_p from public.retiros where estado = 'pendiente';
  select jsonb_build_object(
    'tasa', (select valor from public.ajustes where clave = 'tasa_bs'),
    'por_verificar', coalesce(sum(price + fee) filter (where status = 'revision'), 0),
    'retenido', coalesce(sum(price + fee) filter (where status in ('retenido','enviado','disputa','devolucion')), 0),
    'por_pagar', coalesce(sum(price) filter (where status = 'liberado' and paid_out_at is null), 0),
    'reembolsos', coalesce(sum(price + fee) filter (where status = 'cancelado' and paid_at is not null
                                                     and refunded_at is null), 0),
    'tarifas', coalesce(sum(fee) filter (where status = 'liberado'), 0),
    'destacados', dest,
    'saldos', saldos,
    'retiros_pendientes', retiros_p,
    'pagado', coalesce((select sum(monto) from public.retiros where estado = 'pagado'), 0),
    'reembolsado', coalesce(sum(price + fee) filter (where refunded_at is not null), 0),
    'pagos_atrasados', (select count(*) from public.retiros where estado = 'pendiente'
        and now() > public.lp_mas_habiles(creado, 2)),
    'reembolsos_atrasados', count(distinct coalesce(bundle_id, id)) filter (where status = 'cancelado'
        and paid_at is not null and refunded_at is null and now() > public.lp_mas_habiles(coalesce(cancelled_at, updated_at), 5)),
    'disputas_atrasadas', count(distinct coalesce(bundle_id, id)) filter (where status = 'disputa'
        and now() > public.lp_mas_habiles(coalesce(disputed_at, updated_at), 5)),
    'envios_por_vencer', count(distinct coalesce(bundle_id, id)) filter (where status = 'retenido'
        and paid_at < now() - interval '48 hours')
  ) into j from public.orders;
  j := j || jsonb_build_object(
    'terceros', (j->>'retenido')::numeric + (j->>'por_pagar')::numeric + (j->>'reembolsos')::numeric
                + saldos + retiros_p,
    'esperado', (j->>'retenido')::numeric + (j->>'por_pagar')::numeric + (j->>'reembolsos')::numeric
                + saldos + retiros_p + (j->>'tarifas')::numeric + dest);
  return j;
end $$;
revoke all on function public.admin_cuadre() from public, anon;
grant execute on function public.admin_cuadre() to authenticated;

create or replace function public.mi_saldo() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'disponible', public.lp_saldo(auth.uid()),
    'pendiente', coalesce((select sum(price) from public.orders
                           where seller_id = auth.uid() and status in ('retenido','enviado','disputa','devolucion')), 0),
    'en_retiro', coalesce((select sum(monto) from public.retiros
                           where user_id = auth.uid() and estado = 'pendiente'), 0),
    'minimo_retiro', 5)
  where auth.uid() is not null
$$;
revoke all on function public.mi_saldo() from public, anon;
grant execute on function public.mi_saldo() to authenticated;
