-- Pavito: plazos que prometen los términos y cuadre diario del dinero guardado.
--  * El vendedor tiene 3 días para enviar desde que se confirma el pago: aviso a las 48 h
--    y cancelación automática a los 3 días (el dinero vuelve al comprador).
--  * Pago al vendedor en 2 días hábiles y reembolsos en 5 días hábiles: el panel los
--    marca como atrasados. Las disputas abiertas más de 5 días hábiles también.
--  * Cuadre: lo que debe haber en la cuenta de Pavito y registro diario del saldo real.

-- ============ Fechas de cada paso del pedido ============
alter table public.orders
  add column if not exists paid_at timestamptz,
  add column if not exists shipped_at timestamptz,
  add column if not exists released_at timestamptz,
  add column if not exists refunded_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists disputed_at timestamptz,
  add column if not exists aviso_envio boolean not null default false;
grant select (paid_at, shipped_at, released_at, refunded_at, cancelled_at, disputed_at) on public.orders to authenticated;

update public.orders set paid_at = coalesce(paid_at, updated_at)
  where paid_at is null and status in ('retenido','enviado','liberado','disputa');
update public.orders set shipped_at = coalesce(shipped_at, updated_at)
  where shipped_at is null and status in ('enviado','liberado');
update public.orders set released_at = coalesce(released_at, updated_at)
  where released_at is null and status = 'liberado';
update public.orders set cancelled_at = coalesce(cancelled_at, updated_at)
  where cancelled_at is null and status = 'cancelado';
update public.orders set disputed_at = coalesce(disputed_at, updated_at)
  where disputed_at is null and status = 'disputa';

-- Las fechas las pone el servidor; nadie las puede escribir desde la app
-- (los permisos de update siguen siendo solo status, pay_ref, tracking y delivery).
create or replace function public.orders_sellos() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    new.paid_at := old.paid_at; new.shipped_at := old.shipped_at;
    new.released_at := old.released_at; new.aviso_envio := old.aviso_envio;
    new.cancelled_at := old.cancelled_at; new.disputed_at := old.disputed_at;
    if current_setting('pavito.reembolso', true) is distinct from 'si' or not public.is_admin() then
      new.refunded_at := old.refunded_at;
    end if;
    if current_setting('pavito.mantenimiento', true) = 'si' and auth.uid() is null then
      new.aviso_envio := true;
    end if;
    if new.status is distinct from old.status then
      if new.status = 'retenido' then new.paid_at := coalesce(new.paid_at, now()); end if;
      if new.status = 'enviado' then new.shipped_at := coalesce(new.shipped_at, now()); end if;
      if new.status = 'liberado' then new.released_at := coalesce(new.released_at, now()); end if;
      if new.status = 'cancelado' then new.cancelled_at := now(); end if;
      if new.status = 'disputa' then new.disputed_at := now(); end if;
    end if;
  else
    new.paid_at := null; new.shipped_at := null; new.released_at := null;
    new.refunded_at := null; new.aviso_envio := false;
    new.cancelled_at := null; new.disputed_at := null;
  end if;
  return new;
end $$;
drop trigger if exists orders_sellos on public.orders;
create trigger orders_sellos before insert or update on public.orders
  for each row execute function public.orders_sellos();

-- Suma días hábiles (lunes a viernes, hora de Venezuela).
create or replace function public.lp_mas_habiles(t timestamptz, n int) returns timestamptz
language plpgsql immutable as $$
declare d timestamptz := t; k int := 0;
begin
  while k < n loop
    d := d + interval '1 day';
    if extract(isodow from d at time zone 'America/Caracas') < 6 then k := k + 1; end if;
  end loop;
  return d;
end $$;

-- ============ Avisos de pedido (cancelación con reembolso) ============
create or replace function public.avisos_pedido() returns trigger
language plpgsql security definer set search_path = public as $$
declare titulo text;
begin
  select title into titulo from public.listings where id = new.listing_id;
  titulo := '"' || coalesce(titulo, 'tu artículo') || '"';
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
      perform public.avisar(new.buyer_id, titulo || ' va en camino. Confirma cuando lo recibas.', 'pedido', new.id);
    when 'liberado' then
      perform public.avisar(new.seller_id, 'Venta completada: ' || titulo || '. ¡Deja tu reseña!', 'pedido', new.id);
      perform public.avisar(new.buyer_id, 'Pedido completado: ' || titulo || '. ¡Deja tu reseña!', 'pedido', new.id);
    when 'disputa' then
      perform public.avisar(new.seller_id, 'El comprador reportó un problema con ' || titulo || '.', 'pedido', new.id);
    when 'cancelado' then
      if old.status = 'retenido' and auth.uid() is null then
        perform public.avisar(new.seller_id, 'Se canceló la venta de ' || titulo || ' porque no se envió en 3 días.', 'pedido', new.id);
      else
        perform public.avisar(new.seller_id, 'Se canceló el pedido de ' || titulo || '.', 'pedido', new.id);
      end if;
      if new.paid_at is not null then
        perform public.avisar(new.buyer_id, 'Se canceló el pedido de ' || titulo
          || '. Te devolvemos lo que pagaste a tu Pago Móvil en un máximo de 5 días hábiles.', 'pedido', new.id);
      else
        perform public.avisar(new.buyer_id, 'Se canceló el pedido de ' || titulo || '.', 'pedido', new.id);
      end if;
    else null;
  end case;
  return new;
end $$;

-- ============ Mantenimiento con el plazo de envío ============
create or replace function public.orders_mantenimiento() returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  update public.orders set status = 'cancelado'
    where status = 'esperando_pago' and created_at < now() - interval '24 hours';
  -- El vendedor tiene 3 días para enviar desde que se confirma el pago.
  for r in select distinct on (coalesce(bundle_id, id)) id, seller_id from public.orders
           where status = 'retenido' and not aviso_envio and paid_at < now() - interval '48 hours' loop
    perform public.avisar(r.seller_id, 'Te queda 1 día para enviar tu venta. Si no cargas la guía, '
      || 'el pedido se cancela y el dinero vuelve al comprador.', 'pedido', r.id);
  end loop;
  perform set_config('pavito.mantenimiento', 'si', true);
  update public.orders set updated_at = updated_at
    where status = 'retenido' and not aviso_envio and paid_at < now() - interval '48 hours';
  perform set_config('pavito.mantenimiento', 'no', true);
  update public.orders set status = 'cancelado'
    where status = 'retenido' and paid_at < now() - interval '3 days';
  update public.orders set status = 'liberado'
    where status = 'enviado' and coalesce(shipped_at, updated_at) < now() - interval '7 days';
  update public.orders set delivery = null
    where delivery is not null and status in ('liberado','cancelado')
      and updated_at < now() - interval '30 days';
  update public.offers set status = 'vencida', responded_at = now()
    where (status = 'pendiente' and created_at < now() - interval '48 hours')
       or (status = 'aceptada' and responded_at < now() - interval '48 hours');
  delete from public.avisos where leido and creado < now() - interval '60 days';
end $$;

-- ============ Reembolsos ============
create or replace function public.admin_mark_refunded(p_order uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g uuid; b uuid;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  select coalesce(bundle_id, id), buyer_id into g, b from public.orders where id = p_order;
  perform set_config('pavito.reembolso', 'si', true);
  update public.orders set refunded_at = now()
    where coalesce(bundle_id, id) = g and status = 'cancelado'
      and paid_at is not null and refunded_at is null;
  perform set_config('pavito.reembolso', 'no', true);
  perform public.avisar(b, 'Te devolvimos el dinero de tu pedido cancelado. Revisa tu Pago Móvil.', 'pedido', p_order);
end $$;
revoke all on function public.admin_mark_refunded(uuid) from public, anon;
grant execute on function public.admin_mark_refunded(uuid) to authenticated;

-- ============ Cuadre del dinero ============
create table if not exists public.cuadres (
  id bigserial primary key,
  dia date not null default (now() at time zone 'America/Caracas')::date,
  esperado_usd numeric(12,2) not null,
  terceros_usd numeric(12,2) not null,
  saldo_bs numeric(16,2) not null check (saldo_bs >= 0),
  tasa numeric(14,4) not null,
  saldo_usd numeric(12,2) not null,
  diferencia_usd numeric(12,2) not null,
  nota text check (char_length(nota) <= 300),
  creado timestamptz not null default now(),
  creado_por uuid default auth.uid()
);
alter table public.cuadres enable row level security;
revoke all on public.cuadres from anon, authenticated;
grant select on public.cuadres to authenticated;
drop policy if exists cuadres_admin on public.cuadres;
create policy cuadres_admin on public.cuadres for select to authenticated using (public.is_admin());

create or replace function public.admin_cuadre() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare j jsonb; dest numeric;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  select coalesce(sum(amount), 0) into dest from public.promotions where status = 'activa';
  select jsonb_build_object(
    'tasa', (select valor from public.ajustes where clave = 'tasa_bs'),
    'por_verificar', coalesce(sum(price + fee) filter (where status = 'revision'), 0),
    'retenido', coalesce(sum(price + fee) filter (where status in ('retenido','enviado','disputa')), 0),
    'por_pagar', coalesce(sum(price) filter (where status = 'liberado' and paid_out_at is null), 0),
    'reembolsos', coalesce(sum(price + fee) filter (where status = 'cancelado' and paid_at is not null
                                                     and refunded_at is null), 0),
    'tarifas', coalesce(sum(fee) filter (where status = 'liberado'), 0),
    'destacados', dest,
    'pagado', coalesce(sum(price) filter (where paid_out_at is not null), 0),
    'reembolsado', coalesce(sum(price + fee) filter (where refunded_at is not null), 0),
    'pagos_atrasados', count(distinct coalesce(bundle_id, id)) filter (where status = 'liberado'
        and paid_out_at is null and now() > public.lp_mas_habiles(coalesce(released_at, updated_at), 2)),
    'reembolsos_atrasados', count(distinct coalesce(bundle_id, id)) filter (where status = 'cancelado'
        and paid_at is not null and refunded_at is null and now() > public.lp_mas_habiles(coalesce(cancelled_at, updated_at), 5)),
    'disputas_atrasadas', count(distinct coalesce(bundle_id, id)) filter (where status = 'disputa'
        and now() > public.lp_mas_habiles(coalesce(disputed_at, updated_at), 5)),
    'envios_por_vencer', count(distinct coalesce(bundle_id, id)) filter (where status = 'retenido'
        and paid_at < now() - interval '48 hours')
  ) into j from public.orders;
  j := j || jsonb_build_object(
    'terceros', (j->>'retenido')::numeric + (j->>'por_pagar')::numeric + (j->>'reembolsos')::numeric,
    'esperado', (j->>'retenido')::numeric + (j->>'por_pagar')::numeric + (j->>'reembolsos')::numeric
                + (j->>'tarifas')::numeric + dest);
  return j;
end $$;
revoke all on function public.admin_cuadre() from public, anon;
grant execute on function public.admin_cuadre() to authenticated;

-- Guarda el saldo real de la cuenta (en Bs) y la diferencia con lo esperado.
create or replace function public.admin_guardar_cuadre(p_saldo_bs numeric, p_nota text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c jsonb; t numeric; usd numeric; fila public.cuadres;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_saldo_bs is null or p_saldo_bs < 0 then raise exception 'Saldo no válido'; end if;
  c := public.admin_cuadre();
  t := nullif((c->>'tasa')::numeric, 0);
  if t is null then raise exception 'Falta la tasa del BCV'; end if;
  usd := round(p_saldo_bs / t, 2);
  insert into public.cuadres (esperado_usd, terceros_usd, saldo_bs, tasa, saldo_usd, diferencia_usd, nota)
  values ((c->>'esperado')::numeric, (c->>'terceros')::numeric, p_saldo_bs, t, usd,
          usd - (c->>'esperado')::numeric, nullif(btrim(p_nota), ''))
  returning * into fila;
  return to_jsonb(fila);
end $$;
revoke all on function public.admin_guardar_cuadre(numeric, text) from public, anon;
grant execute on function public.admin_guardar_cuadre(numeric, text) to authenticated;
