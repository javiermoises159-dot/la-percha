-- 0020: Saldo Pavito (monedero, como Vinted).
--  * Al completarse una venta, el dinero pasa al Saldo Pavito del vendedor.
--  * Si se cancela un pedido ya pagado, el dinero vuelve al instante al Saldo Pavito del comprador.
--  * Con el saldo se puede pagar otra compra, o retirarlo (desde $5) a la cuenta de Pago Móvil.
--  * Los retiros los paga el equipo desde el panel; si se rechaza uno, el dinero vuelve al saldo.
-- Todo queda en un libro de movimientos que nadie puede modificar ni borrar.

-- ============ Libro de movimientos ============
create table if not exists public.movimientos (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id),
  monto numeric(12,2) not null check (monto <> 0),
  tipo text not null check (tipo in ('venta','reembolso','compra','retiro','retiro_devuelto','ajuste')),
  order_id uuid references public.orders(id),
  retiro_id uuid,
  nota text,
  creado timestamptz not null default now()
);
create unique index if not exists movimientos_unico_pedido on public.movimientos (order_id, tipo)
  where order_id is not null;
create index if not exists movimientos_usuario on public.movimientos (user_id, creado desc);
alter table public.movimientos enable row level security;
revoke all on public.movimientos from anon, authenticated;
grant select on public.movimientos to authenticated;
drop policy if exists movimientos_leer on public.movimientos;
create policy movimientos_leer on public.movimientos for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

create or replace function public.movimientos_inmutable() returns trigger
language plpgsql as $$
begin
  raise exception 'Los movimientos del saldo no se pueden modificar ni borrar';
end $$;
drop trigger if exists movimientos_inmutable on public.movimientos;
create trigger movimientos_inmutable before update or delete on public.movimientos
  for each row execute function public.movimientos_inmutable();
revoke all on function public.movimientos_inmutable() from public, anon, authenticated;

-- ============ Retiros ============
create table if not exists public.retiros (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  monto numeric(12,2) not null check (monto >= 5),
  estado text not null default 'pendiente' check (estado in ('pendiente','pagado','rechazado')),
  destino text,
  ref_pago text,
  motivo text,
  creado timestamptz not null default now(),
  resuelto_at timestamptz
);
create index if not exists retiros_estado on public.retiros (estado, creado);
alter table public.retiros enable row level security;
revoke all on public.retiros from anon, authenticated;
grant select on public.retiros to authenticated;
drop policy if exists retiros_leer on public.retiros;
create policy retiros_leer on public.retiros for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

create or replace function public.lp_saldo(p_user uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(monto), 0) from public.movimientos where user_id = p_user
$$;
revoke all on function public.lp_saldo(uuid) from public, anon, authenticated;

-- Resumen del saldo para la app.
create or replace function public.mi_saldo() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'disponible', public.lp_saldo(auth.uid()),
    'pendiente', coalesce((select sum(price) from public.orders
                           where seller_id = auth.uid() and status in ('retenido','enviado','disputa')), 0),
    'en_retiro', coalesce((select sum(monto) from public.retiros
                           where user_id = auth.uid() and estado = 'pendiente'), 0),
    'minimo_retiro', 5)
  where auth.uid() is not null
$$;
revoke all on function public.mi_saldo() from public, anon;
grant execute on function public.mi_saldo() to authenticated;

-- ============ El dinero se mueve solo con el estado del pedido ============
-- Se ejecuta después de las demás reglas del pedido (por eso el nombre empieza con "z").
create or replace function public.orders_zdinero() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is not distinct from old.status then return new; end if;
  -- Venta completada: el precio va al saldo del vendedor.
  if new.status = 'liberado' then
    new.paid_out_at := coalesce(new.paid_out_at, now());
    insert into public.movimientos (user_id, monto, tipo, order_id)
      values (new.seller_id, new.price, 'venta', new.id)
      on conflict do nothing;
  end if;
  -- Pedido pagado y cancelado: todo lo pagado vuelve al saldo del comprador.
  if new.status = 'cancelado' and new.paid_at is not null and new.refunded_at is null then
    new.refunded_at := now();
    insert into public.movimientos (user_id, monto, tipo, order_id)
      values (new.buyer_id, new.price + new.fee, 'reembolso', new.id)
      on conflict do nothing;
  end if;
  return new;
end $$;
revoke all on function public.orders_zdinero() from public, anon, authenticated;
drop trigger if exists orders_zdinero on public.orders;
create trigger orders_zdinero before update on public.orders
  for each row execute function public.orders_zdinero();

-- ============ Pagar con el saldo ============
create or replace function public.pagar_con_saldo(p_order uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g uuid; total numeric; o record;
begin
  if auth.uid() is null or public.is_blocked() then raise exception 'No autorizado'; end if;
  select coalesce(bundle_id, id) into g from public.orders
    where id = p_order and buyer_id = auth.uid() and status = 'esperando_pago';
  if g is null then raise exception 'Este pedido ya no está esperando pago'; end if;
  perform pg_advisory_xact_lock(hashtext('saldo:' || auth.uid()::text));
  select sum(price + fee) into total from public.orders
    where coalesce(bundle_id, id) = g and buyer_id = auth.uid() and status = 'esperando_pago';
  if public.lp_saldo(auth.uid()) < total then
    raise exception 'No te alcanza el saldo: tienes $% y el pedido es de $%',
      to_char(public.lp_saldo(auth.uid()), 'FM999990.00'), to_char(total, 'FM999990.00');
  end if;
  perform set_config('pavito.pago_saldo', 'si', true);
  for o in select * from public.orders
           where coalesce(bundle_id, id) = g and buyer_id = auth.uid() and status = 'esperando_pago' loop
    insert into public.movimientos (user_id, monto, tipo, order_id)
      values (auth.uid(), -(o.price + o.fee), 'compra', o.id);
    update public.orders set status = 'retenido', pay_ref = 'SALDO-' || left(o.id::text, 8)
      where id = o.id;
  end loop;
  perform set_config('pavito.pago_saldo', '', true);
  perform interno.registrar('pago_con_saldo', p_order, jsonb_build_object('usd', total));
end $$;
revoke all on function public.pagar_con_saldo(uuid) from public, anon;
grant execute on function public.pagar_con_saldo(uuid) to authenticated;

-- ============ Retiros: pedir, pagar, rechazar ============
create or replace function public.pedir_retiro(p_monto numeric) returns uuid
language plpgsql security definer set search_path = public as $$
declare pp public.private_profiles; v uuid; m numeric := round(p_monto, 2); n int;
begin
  if auth.uid() is null or public.is_blocked() then raise exception 'No autorizado'; end if;
  if m is null or m < 5 then raise exception 'El retiro mínimo es de $5'; end if;
  select * into pp from public.private_profiles where id = auth.uid();
  if pp.payout_cifrado is null then
    raise exception 'Primero pon tus datos de Pago Móvil para cobrar';
  end if;
  if pp.payout_cambiado is not null and pp.payout_cambiado > now() - interval '24 hours' then
    raise exception 'Cambiaste tus datos de cobro hace poco. Por seguridad podrás retirar 24 h después del cambio.';
  end if;
  perform pg_advisory_xact_lock(hashtext('saldo:' || auth.uid()::text));
  select count(*) into n from public.retiros where user_id = auth.uid() and creado > now() - interval '1 day';
  if n >= 3 then raise exception 'Puedes pedir hasta 3 retiros al día'; end if;
  if public.lp_saldo(auth.uid()) < m then raise exception 'No tienes ese saldo disponible'; end if;
  insert into public.retiros (user_id, monto, destino)
    values (auth.uid(), m, coalesce(pp.payout_resumen::text, ''))
    returning id into v;
  insert into public.movimientos (user_id, monto, tipo, retiro_id) values (auth.uid(), -m, 'retiro', v);
  perform interno.registrar('pedir_retiro', v, jsonb_build_object('usd', m));
  perform public.avisar(auth.uid(), 'Pediste retirar $' || to_char(m, 'FM999990.00')
    || '. Te lo enviamos a tu Pago Móvil en 1 a 2 días hábiles.', 'perfil', null);
  return v;
end $$;
revoke all on function public.pedir_retiro(numeric) from public, anon;
grant execute on function public.pedir_retiro(numeric) to authenticated;

-- El admin ve los datos completos solo para pagar un retiro pendiente (queda registrado).
create or replace function public.admin_datos_retiro(p_retiro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.retiros; d jsonb; ch timestamptz;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  select * into r from public.retiros where id = p_retiro and estado = 'pendiente';
  if r.id is null then raise exception 'Solo se pueden ver los datos de un retiro pendiente'; end if;
  select extensions.pgp_sym_decrypt(payout_cifrado, interno.clave_cobros())::jsonb, payout_cambiado
    into d, ch from public.private_profiles where id = r.user_id;
  if d is null then raise exception 'La persona no tiene datos de cobro'; end if;
  perform interno.registrar('ver_datos_retiro', p_retiro, jsonb_build_object('usuario', r.user_id));
  return d || jsonb_build_object('cambiado', ch, 'cambiado_despues', coalesce(ch > r.creado, false));
end $$;
revoke all on function public.admin_datos_retiro(uuid) from public, anon;
grant execute on function public.admin_datos_retiro(uuid) to authenticated;

create or replace function public.admin_pagar_retiro(p_retiro uuid, p_ref text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.retiros; ch timestamptz;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if coalesce(btrim(p_ref), '') = '' then raise exception 'Escribe la referencia de la transferencia'; end if;
  select * into r from public.retiros where id = p_retiro for update;
  if r.id is null or r.estado <> 'pendiente' then raise exception 'Este retiro ya fue resuelto'; end if;
  select payout_cambiado into ch from public.private_profiles where id = r.user_id;
  if ch is not null and ch > r.creado then
    raise exception 'La persona cambió sus datos de cobro después de pedir el retiro. Recházalo y que lo pida de nuevo.';
  end if;
  update public.retiros set estado = 'pagado', ref_pago = left(btrim(p_ref), 60), resuelto_at = now()
    where id = r.id;
  perform interno.registrar('pagar_retiro', r.id, jsonb_build_object('usuario', r.user_id, 'usd', r.monto, 'ref', p_ref));
  perform public.avisar(r.user_id, 'Te enviamos $' || to_char(r.monto, 'FM999990.00')
    || ' a tu Pago Móvil (ref. ' || left(btrim(p_ref), 30) || ').', 'perfil', null);
end $$;
revoke all on function public.admin_pagar_retiro(uuid, text) from public, anon;
grant execute on function public.admin_pagar_retiro(uuid, text) to authenticated;

create or replace function public.admin_rechazar_retiro(p_retiro uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.retiros;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  select * into r from public.retiros where id = p_retiro for update;
  if r.id is null or r.estado <> 'pendiente' then raise exception 'Este retiro ya fue resuelto'; end if;
  update public.retiros set estado = 'rechazado', motivo = left(btrim(coalesce(p_motivo, '')), 200), resuelto_at = now()
    where id = r.id;
  insert into public.movimientos (user_id, monto, tipo, retiro_id, nota)
    values (r.user_id, r.monto, 'retiro_devuelto', r.id, left(btrim(coalesce(p_motivo, '')), 200));
  perform interno.registrar('rechazar_retiro', r.id, jsonb_build_object('usuario', r.user_id, 'usd', r.monto, 'motivo', p_motivo));
  perform public.avisar(r.user_id, 'No pudimos enviar tu retiro de $' || to_char(r.monto, 'FM999990.00')
    || '. El dinero volvió a tu Saldo Pavito.' || coalesce(' Motivo: ' || nullif(btrim(p_motivo), ''), ''), 'perfil', null);
end $$;
revoke all on function public.admin_rechazar_retiro(uuid, text) from public, anon;
grant execute on function public.admin_rechazar_retiro(uuid, text) to authenticated;

-- ============ Cuadre: ahora cuenta lo que se debe en saldos y retiros ============
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
    'retenido', coalesce(sum(price + fee) filter (where status in ('retenido','enviado','disputa')), 0),
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


-- ============ Reglas del pedido: el pago con saldo puede confirmar el pedido ============
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

-- ============ Avisos: la venta y el reembolso van al Saldo Pavito ============
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
      perform public.avisar(new.seller_id, 'Venta completada: ' || titulo || '. Ya tienes $'
        || to_char(new.price, 'FM999990.00') || ' en tu Saldo Pavito.', 'pedido', new.id);
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
        perform public.avisar(new.buyer_id, 'Se canceló el pedido de ' || titulo || '. Te devolvimos $'
          || to_char(new.price + new.fee, 'FM999990.00') || ' a tu Saldo Pavito: úsalo en otra compra o retíralo.', 'pedido', new.id);
      else
        perform public.avisar(new.buyer_id, 'Se canceló el pedido de ' || titulo || '.', 'pedido', new.id);
      end if;
    else null;
  end case;
  return new;
end $$;

-- ============ No se puede eliminar la cuenta con dinero dentro ============
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'No autorizado';
  end if;
  if exists (select 1 from public.orders
             where (buyer_id = uid or seller_id = uid)
               and status not in ('liberado', 'cancelado')) then
    raise exception 'Tienes pedidos en curso. Termínalos antes de eliminar tu cuenta.';
  end if;
  if public.lp_saldo(uid) > 0 or exists (select 1 from public.retiros where user_id = uid and estado = 'pendiente') then
    raise exception 'Tienes dinero en tu Saldo Pavito. Retíralo antes de eliminar tu cuenta.';
  end if;
  perform set_config('lapercha.sistema', '1', true);

  -- Datos personales y actividad que no hace falta guardar.
  delete from public.private_profiles where id = uid;
  delete from public.favorites where user_id = uid;
  delete from public.follows where follower_id = uid or seller_id = uid;
  delete from public.avisos where user_id = uid;
  delete from public.listings l where l.seller_id = uid
    and not exists (select 1 from public.orders o where o.listing_id = l.id);
  update public.listings set status = 'hidden'
    where seller_id = uid and status in ('active', 'reserved');

  -- Sin historial: se borra todo.
  begin
    delete from auth.users where id = uid;
    perform set_config('lapercha.sistema', '', true);
    return;
  exception when foreign_key_violation then
    null;
  end;

  -- Con historial (pedidos o mensajes): se anonimiza y se cierra la cuenta.
  update public.profiles
    set username = 'eliminado_' || substr(md5(uid::text), 1, 10), city = 'Venezuela',
        blocked = true, vacation = true
    where id = uid;
  if exists (select 1 from information_schema.columns
             where table_schema = 'auth' and table_name = 'users' and column_name = 'banned_until') then
    execute 'update auth.users set email = $2, phone = null, banned_until = ''infinity'',
               raw_user_meta_data = ''{}''::jsonb where id = $1'
      using uid, 'eliminado+' || uid::text || '@pavito.invalid';
    execute 'delete from auth.identities where user_id = $1' using uid;
    execute 'delete from auth.sessions where user_id = $1' using uid;
  end if;
  perform set_config('lapercha.sistema', '', true);
end $$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- ============ Ventas y reembolsos que ya estaban pendientes pasan al saldo ============
alter table public.orders disable trigger orders_sellos;
insert into public.movimientos (user_id, monto, tipo, order_id)
  select seller_id, price, 'venta', id from public.orders
  where status = 'liberado' and paid_out_at is null
  on conflict do nothing;
update public.orders set paid_out_at = now() where status = 'liberado' and paid_out_at is null;
insert into public.movimientos (user_id, monto, tipo, order_id)
  select buyer_id, price + fee, 'reembolso', id from public.orders
  where status = 'cancelado' and paid_at is not null and refunded_at is null
  on conflict do nothing;
update public.orders set refunded_at = now()
  where status = 'cancelado' and paid_at is not null and refunded_at is null;
alter table public.orders enable trigger orders_sellos;
