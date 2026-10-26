-- Pavito: blindaje de datos bancarios y del panel de administración.
--  1. Los datos de cobro (banco, cédula, teléfono de Pago Móvil) se guardan cifrados con una
--     clave que vive en Supabase Vault. La app solo ve un resumen enmascarado (0134 · V-•••678).
--  2. Si alguien cambia sus datos de cobro, se le avisa y no se le puede pagar durante 24 h
--     (protege contra quien roba una cuenta y pone su propio Pago Móvil).
--  3. El administrador solo cuenta como administrador si entró con verificación en dos pasos
--     (aal2). Sin eso, es un usuario normal en toda la base de datos.
--  4. El admin solo puede ver los datos completos de cobro de una venta que debe pagar, y cada
--     consulta queda registrada.
--  5. Registro de auditoría de solo agregar: confirmaciones de pago, pagos, reembolsos,
--     bloqueos, cambios de tasa, cuadres y consultas de datos bancarios.

create schema if not exists interno;
revoke all on schema interno from public, anon, authenticated;
create extension if not exists pgcrypto with schema extensions;

-- ============ Clave de cifrado en Vault ============
do $$ begin
  if not exists (select 1 from vault.secrets where name = 'pavito_clave_cobros') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'base64'),
                                'pavito_clave_cobros', 'Clave para cifrar los datos de cobro de Pavito');
  end if;
end $$;

create or replace function interno.clave_cobros() returns text
language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'pavito_clave_cobros' limit 1
$$;
revoke all on function interno.clave_cobros() from public, anon, authenticated;

-- ============ Registro de auditoría (solo agregar) ============
create table if not exists interno.auditoria (
  id bigserial primary key,
  creado timestamptz not null default now(),
  actor uuid,
  accion text not null,
  ref uuid,
  detalle jsonb
);
revoke all on interno.auditoria from public, anon, authenticated;

create or replace function interno.auditoria_inmutable() returns trigger
language plpgsql as $$
begin
  raise exception 'El registro de auditoría no se puede modificar ni borrar';
end $$;
drop trigger if exists auditoria_inmutable on interno.auditoria;
create trigger auditoria_inmutable before update or delete on interno.auditoria
  for each row execute function interno.auditoria_inmutable();

create or replace function interno.registrar(p_accion text, p_ref uuid, p_detalle jsonb default null)
returns void language sql security definer set search_path = '' as $$
  insert into interno.auditoria (actor, accion, ref, detalle) values (auth.uid(), p_accion, p_ref, p_detalle)
$$;
revoke all on function interno.registrar(text, uuid, jsonb) from public, anon, authenticated;

-- ============ Administrador con verificación en dos pasos ============
create or replace function public.lp_aal() returns text
language sql stable set search_path = '' as $$
  select coalesce(nullif(current_setting('request.jwt.claim.aal', true), ''),
                  nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'aal', 'aal1')
$$;

create or replace function public.is_admin() returns boolean
language sql security definer stable set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
     and public.lp_aal() = 'aal2'
$$;

-- La app pregunta esto para saber si debe pedir el código de verificación.
create or replace function public.admin_necesita_2fa() returns boolean
language sql security definer stable set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
     and public.lp_aal() <> 'aal2'
$$;
revoke all on function public.admin_necesita_2fa() from public, anon;
grant execute on function public.admin_necesita_2fa() to authenticated;

-- ============ Datos de cobro cifrados ============
alter table public.private_profiles
  add column if not exists payout_cifrado bytea,
  add column if not exists payout_resumen jsonb,
  add column if not exists payout_cambiado timestamptz;

create or replace function public.private_cobros() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  b text; c text; t text; cod text;
  migrando boolean := coalesce(current_setting('pavito.migrando', true), '') = 'si';
begin
  -- Nadie escribe a mano el cifrado, el resumen ni la fecha de cambio.
  if tg_op = 'UPDATE' then
    new.payout_cifrado := old.payout_cifrado;
    new.payout_resumen := old.payout_resumen;
    new.payout_cambiado := old.payout_cambiado;
  else
    new.payout_cifrado := null; new.payout_resumen := null; new.payout_cambiado := null;
  end if;

  if new.payout is not null and new.payout <> 'null'::jsonb then
    b := btrim(coalesce(new.payout->>'banco', ''));
    c := upper(regexp_replace(coalesce(new.payout->>'cedula', ''), '[\s.]', '', 'g'));
    t := regexp_replace(coalesce(new.payout->>'telefono', ''), '\D', '', 'g');
    if t ~ '^58' then t := '0' || substr(t, 3); end if;
    if t ~ '^4' then t := '0' || t; end if;
    if not migrando then
      cod := substring(b from '^\d{4}');
      if cod is null or cod not in ('0102','0104','0105','0108','0114','0115','0128','0134','0137',
          '0138','0146','0151','0156','0157','0163','0166','0168','0169','0171','0172','0173',
          '0174','0175','0177','0178','0191') then
        raise exception 'Elige tu banco de la lista';
      end if;
      if c !~ '^[VEJPG]-?\d{5,10}$' then
        raise exception 'Cédula o RIF no válido (ejemplo: V-12345678)';
      end if;
      if t !~ '^04(12|14|16|22|24|26)\d{7}$' then
        raise exception 'Teléfono de Pago Móvil no válido (ejemplo: 0414 1234567)';
      end if;
      if c !~ '-' then c := left(c, 1) || '-' || substr(c, 2); end if;
    end if;
    new.payout_cifrado := extensions.pgp_sym_encrypt(
      jsonb_build_object('banco', b, 'cedula', c, 'telefono', t)::text, interno.clave_cobros());
    new.payout_resumen := jsonb_build_object(
      'banco', b,
      'cedula', left(c, 2) || '•••' || right(c, 3),
      'telefono', left(t, 4) || '•••' || right(t, 4));
    if not migrando then
      new.payout_cambiado := now();
      if tg_op = 'UPDATE' and old.payout_cifrado is not null then
        perform public.avisar(new.id, 'Cambiaste tus datos de cobro. Por seguridad, los pagos a la '
          || 'cuenta nueva esperan 24 h. Si no fuiste tú, escríbenos ya.', 'perfil', new.id);
      end if;
      perform interno.registrar('cambio_datos_cobro', new.id, jsonb_build_object('banco', b));
    end if;
  end if;
  new.payout := null;   -- nunca se guarda en claro
  return new;
end $$;
drop trigger if exists private_cobros on public.private_profiles;
create trigger private_cobros before insert or update on public.private_profiles
  for each row execute function public.private_cobros();

-- Cifrar lo que ya existía (sin validar ni avisar).
do $$ begin
  perform set_config('pavito.migrando', 'si', true);
  update public.private_profiles set payout = payout where payout is not null;
  perform set_config('pavito.migrando', 'no', true);
end $$;

-- La app ya no puede leer el cifrado: solo el resumen.
revoke select on public.private_profiles from authenticated;
grant select (id, phone, address, prefs, payout, payout_resumen, payout_cambiado)
  on public.private_profiles to authenticated;

-- ============ El admin ve los datos completos solo para pagar una venta ============
create or replace function public.admin_datos_cobro(p_order uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s uuid; d jsonb; ch timestamptz;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  select seller_id into s from public.orders
    where id = p_order and status = 'liberado' and paid_out_at is null;
  if s is null then raise exception 'Solo se pueden ver los datos de una venta pendiente de pago'; end if;
  select extensions.pgp_sym_decrypt(payout_cifrado, interno.clave_cobros())::jsonb, payout_cambiado
    into d, ch from public.private_profiles where id = s;
  if d is null then raise exception 'El vendedor no ha puesto sus datos de cobro'; end if;
  perform interno.registrar('ver_datos_cobro', p_order, jsonb_build_object('vendedor', s));
  return d || jsonb_build_object('cambiado', ch,
    'cambiado_reciente', coalesce(ch > now() - interval '24 hours', false));
end $$;
revoke all on function public.admin_datos_cobro(uuid) from public, anon;
grant execute on function public.admin_datos_cobro(uuid) to authenticated;

-- ============ Pagos y reembolsos con registro (y espera tras cambio de cuenta) ============
create or replace function public.admin_mark_paid(p_order uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g uuid; s uuid; ch timestamptz; total numeric;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  select coalesce(bundle_id, id), seller_id into g, s from public.orders where id = p_order;
  select payout_cambiado into ch from public.private_profiles where id = s;
  if ch is not null and ch > now() - interval '24 hours' then
    raise exception 'El vendedor cambió sus datos de cobro hace menos de 24 h. Espera y confirma con él antes de pagar.';
  end if;
  select sum(price) into total from public.orders
    where coalesce(bundle_id, id) = g and status = 'liberado' and paid_out_at is null;
  update public.orders set paid_out_at = now()
    where coalesce(bundle_id, id) = g and status = 'liberado' and paid_out_at is null;
  perform interno.registrar('pago_a_vendedor', p_order, jsonb_build_object('vendedor', s, 'usd', total));
  perform public.avisar(s, 'Te enviamos el pago de tu venta. Revisa tu Pago Móvil.', 'pedido', p_order);
end $$;
revoke all on function public.admin_mark_paid(uuid) from public, anon;
grant execute on function public.admin_mark_paid(uuid) to authenticated;

create or replace function public.admin_mark_refunded(p_order uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g uuid; b uuid; total numeric;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  select coalesce(bundle_id, id), buyer_id into g, b from public.orders where id = p_order;
  select sum(price + fee) into total from public.orders
    where coalesce(bundle_id, id) = g and status = 'cancelado' and paid_at is not null and refunded_at is null;
  perform set_config('pavito.reembolso', 'si', true);
  update public.orders set refunded_at = now()
    where coalesce(bundle_id, id) = g and status = 'cancelado'
      and paid_at is not null and refunded_at is null;
  perform set_config('pavito.reembolso', 'no', true);
  perform interno.registrar('reembolso', p_order, jsonb_build_object('comprador', b, 'usd', total));
  perform public.avisar(b, 'Te devolvimos el dinero de tu pedido cancelado. Revisa tu Pago Móvil.', 'pedido', p_order);
end $$;
revoke all on function public.admin_mark_refunded(uuid) from public, anon;
grant execute on function public.admin_mark_refunded(uuid) to authenticated;

-- Cambios de estado hechos por un admin (confirmar pagos, resolver problemas).
create or replace function public.orders_auditar() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and auth.uid() is not null and public.is_admin() then
    perform interno.registrar('estado_pedido', new.id,
      jsonb_build_object('de', old.status, 'a', new.status, 'usd', new.price + new.fee));
  end if;
  return null;
end $$;
drop trigger if exists orders_auditar on public.orders;
create trigger orders_auditar after update on public.orders
  for each row execute function public.orders_auditar();

-- Bloqueos de usuarios.
create or replace function public.profiles_auditar() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.blocked is distinct from old.blocked and auth.uid() is not null then
    perform interno.registrar(case when new.blocked then 'bloqueo' else 'desbloqueo' end, new.id, null);
  end if;
  return null;
end $$;
drop trigger if exists profiles_auditar on public.profiles;
create trigger profiles_auditar after update on public.profiles
  for each row execute function public.profiles_auditar();

-- Tasa y cuadres.
create or replace function public.ajustes_auditar() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    perform interno.registrar('tasa', null, jsonb_build_object('de', old.valor, 'a', new.valor));
  end if;
  return null;
end $$;
drop trigger if exists ajustes_auditar on public.ajustes;
create trigger ajustes_auditar after update on public.ajustes
  for each row when (new.valor is distinct from old.valor) execute function public.ajustes_auditar();

create or replace function public.cuadres_auditar() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform interno.registrar('cuadre', null,
    jsonb_build_object('saldo_bs', new.saldo_bs, 'diferencia_usd', new.diferencia_usd));
  return null;
end $$;
drop trigger if exists cuadres_auditar on public.cuadres;
create trigger cuadres_auditar after insert on public.cuadres
  for each row execute function public.cuadres_auditar();

-- El admin puede leer (nunca cambiar) las últimas acciones.
create or replace function public.admin_auditoria(p_limite int default 50)
returns table (creado timestamptz, quien text, accion text, ref uuid, detalle jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return query
    select a.creado, coalesce(p.username, 'sistema'), a.accion, a.ref, a.detalle
    from interno.auditoria a left join public.profiles p on p.id = a.actor
    order by a.id desc limit least(greatest(p_limite, 1), 200);
end $$;
revoke all on function public.admin_auditoria(int) from public, anon;
grant execute on function public.admin_auditoria(int) to authenticated;

-- ============ Nadie puede llamar a mano las funciones de disparador ============
-- (se ejecutan solas dentro de la base; desde la app no tienen sentido).
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           where p.pronamespace = 'public'::regnamespace and p.prorettype = 'trigger'::regtype loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
