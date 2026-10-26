\set VERBOSITY terse
-- Datos de cobro cifrados, 2FA del admin y auditoría. a=vendedor, b=comprador, c=otro, d=admin.
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),
 ('00000000-0000-0000-0000-00000000000c'),('00000000-0000-0000-0000-00000000000d');
insert into public.profiles (id, username, city) values
 ('00000000-0000-0000-0000-00000000000a','vende','Caracas'),('00000000-0000-0000-0000-00000000000b','compra','Caracas'),
 ('00000000-0000-0000-0000-00000000000c','otro','Valencia'),('00000000-0000-0000-0000-00000000000d','jefe','Caracas');
update public.profiles set is_admin = true where username = 'jefe';
insert into public.listings (id, seller_id, title, price, category, size, condition, city) values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-00000000000a','Blusa',10,'Mujer','M','Buen estado','Caracas');
create function pg_temp.yo(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false); $$;
set role authenticated;

\echo '--- datos de cobro: banco inventado, cédula y teléfono malos (fallan); correctos (ok)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
insert into public.private_profiles (id, payout) values (auth.uid(), '{"banco":"Mi banco","cedula":"V-12345678","telefono":"04141234567"}');
insert into public.private_profiles (id, payout) values (auth.uid(), '{"banco":"0134 - Banesco","cedula":"12","telefono":"04141234567"}');
insert into public.private_profiles (id, payout) values (auth.uid(), '{"banco":"0134 - Banesco","cedula":"V-12345678","telefono":"0212123"}');
insert into public.private_profiles (id, payout) values (auth.uid(), '{"banco":"0134 - Banesco","cedula":"v 12.345.678","telefono":"+58 414-123-4567"}');
\echo '--- el dueño solo ve el resumen; el cifrado no se puede leer (falla)'
select payout, payout_resumen from public.private_profiles;
select payout_cifrado from public.private_profiles;
\echo '--- otro usuario no ve nada; intenta escribir el cifrado a mano (se ignora)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
select count(*) as ajenos from public.private_profiles;
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.private_profiles set payout_cifrado = 'basura', payout_cambiado = now() - interval '9 days' where id = auth.uid();
reset role; select payout_cifrado <> 'basura'::bytea as intacto, payout is null as sin_claro,
  extensions.pgp_sym_decrypt(payout_cifrado, interno.clave_cobros())::jsonb->>'telefono' as tel_normalizado,
  payout_cambiado > now() - interval '1 minute' as fecha_real from public.private_profiles;
set role authenticated;

\echo '--- venta liberada pendiente de pago'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
insert into public.orders (listing_id) values ('11111111-1111-1111-1111-111111111111');
reset role; select pg_temp.yo('');
update public.orders set status = 'revision', pay_ref = 'REF001';
update public.orders set status = 'retenido';
update public.orders set status = 'enviado', tracking = 'MRW123';
update public.orders set status = 'liberado';
set role authenticated;

\echo '--- admin SIN verificación en dos pasos: no es admin (fallan / 0 filas)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000d');
select set_config('request.jwt.claim.aal', 'aal1', false);
select public.is_admin() as es_admin, public.admin_necesita_2fa() as pide_codigo;
select public.admin_datos_cobro((select id from public.orders limit 1));
select count(*) as cobros_vistos from public.private_profiles;
select public.admin_auditoria();
select public.admin_mark_paid((select id from public.orders limit 1));

\echo '--- admin CON verificación: ve los datos (cambio reciente), pero no puede pagar antes de 24 h (falla)'
select set_config('request.jwt.claim.aal', 'aal2', false);
select public.is_admin() as es_admin, public.admin_necesita_2fa() as pide_codigo;
select d->>'banco' banco, d->>'cedula' cedula, d->>'telefono' tel, d->>'cambiado_reciente' reciente
  from public.admin_datos_cobro((select id from public.orders limit 1)) d;
select public.admin_mark_paid((select id from public.orders limit 1));
\echo '--- pasan 25 h: ya puede pagar; después no puede volver a ver los datos (falla)'
reset role; alter table public.private_profiles disable trigger private_cobros;
update public.private_profiles set payout_cambiado = now() - interval '25 hours';
alter table public.private_profiles enable trigger private_cobros;
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000d');
select public.admin_mark_paid((select id from public.orders limit 1));
select paid_out_at is not null as pagado from public.orders;
select public.admin_datos_cobro((select id from public.orders limit 1));

\echo '--- datos viejos sin validar se cifran igual al migrar (no rompen la migración)'
reset role; select (select count(*) from public.private_profiles where payout_cifrado is not null) as cifrados;
set role authenticated;
\echo '--- el vendedor cambia su cuenta: aviso y nueva espera de 24 h'
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.private_profiles set payout = '{"banco":"0102 - Banco de Venezuela","cedula":"V-12345678","telefono":"04241112233"}' where id = auth.uid();
select payout_resumen->>'banco' banco, payout_resumen->>'telefono' tel, payout_cambiado > now() - interval '1 minute' as recien from public.private_profiles;
select texto from public.avisos where texto like 'Cambiaste tus datos%';

\echo '--- auditoría: el admin la lee; nadie la toca (fallan)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000d');
select quien, accion from public.admin_auditoria(20) order by creado, accion;
select count(*) from interno.auditoria;
reset role;
delete from interno.auditoria;
update interno.auditoria set accion = 'nada';
select count(*) > 0 as auditoria_intacta from interno.auditoria;
