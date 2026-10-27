\set VERBOSITY terse
-- Saldo Pavito: v=vendedora, c=comprador, o=otro, d=admin
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),
 ('00000000-0000-0000-0000-00000000000c'),('00000000-0000-0000-0000-00000000000d');
insert into public.profiles (id, username, city, is_admin) values
 ('00000000-0000-0000-0000-00000000000a','vende','Caracas',false),('00000000-0000-0000-0000-00000000000b','compra','Caracas',false),
 ('00000000-0000-0000-0000-00000000000c','otro','Valencia',false),('00000000-0000-0000-0000-00000000000d','jefe','Caracas',true);
insert into public.listings (id, seller_id, title, price, category, size, condition, city) values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-00000000000a','Chaqueta',20,'Hombre','L','Buen estado','Caracas'),
 ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-00000000000a','Falda',10,'Mujer','S','Buen estado','Caracas'),
 ('33333333-3333-3333-3333-333333333333','00000000-0000-0000-0000-00000000000a','Botas',30,'Zapatos','38','Buen estado','Caracas');
create function pg_temp.yo(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false); $$;
create function pg_temp.saldo(u text) returns text language sql as $$
  select coalesce(sum(monto),0)::text from public.movimientos where user_id = u::uuid $$;
set role authenticated;
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
insert into public.orders (listing_id) values ('11111111-1111-1111-1111-111111111111');
update public.orders set status='revision', pay_ref='111111' where listing_id='11111111-1111-1111-1111-111111111111';
select pg_temp.yo('00000000-0000-0000-0000-00000000000d');
update public.orders set status='retenido' where listing_id='11111111-1111-1111-1111-111111111111';
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.orders set status='enviado', tracking='MRW 1' where listing_id='11111111-1111-1111-1111-111111111111';
\echo '--- 1. al liberar, el precio entra al saldo de la vendedora (una sola vez)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
update public.orders set status='liberado' where listing_id='11111111-1111-1111-1111-111111111111';
select pg_temp.yo(''); reset role;
select pg_temp.saldo('00000000-0000-0000-0000-00000000000a') as saldo_vendedora_20, (select paid_out_at is not null from public.orders where listing_id='11111111-1111-1111-1111-111111111111') as marcado;
set role authenticated;
\echo '--- 2. nadie puede escribir el libro ni leer el de otro'
select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
insert into public.movimientos (user_id, monto, tipo) values ('00000000-0000-0000-0000-00000000000c', 1000, 'ajuste');
select count(*) as movimientos_ajenos_visibles from public.movimientos;
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.movimientos set monto = 9999;
delete from public.movimientos;
select (public.mi_saldo())->>'disponible' as mi_saldo_20;
\echo '--- 3. cancelación de un pedido pagado: vuelve al saldo del comprador'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
insert into public.orders (listing_id) values ('33333333-3333-3333-3333-333333333333');
update public.orders set status='revision', pay_ref='222222' where listing_id='33333333-3333-3333-3333-333333333333';
select pg_temp.yo('00000000-0000-0000-0000-00000000000d');
update public.orders set status='retenido' where listing_id='33333333-3333-3333-3333-333333333333';
update public.orders set status='cancelado' where listing_id='33333333-3333-3333-3333-333333333333';
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select (public.mi_saldo())->>'disponible' as saldo_comprador_31_75;
\echo '--- 4. pagar con saldo: ajeno falla, suficiente funciona y queda retenido'
insert into public.orders (listing_id) values ('22222222-2222-2222-2222-222222222222');
select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
select public.pagar_con_saldo((select id from public.orders where listing_id='22222222-2222-2222-2222-222222222222'));
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select public.pagar_con_saldo((select id from public.orders where listing_id='22222222-2222-2222-2222-222222222222'));
select status, pay_ref from public.orders where listing_id='22222222-2222-2222-2222-222222222222';
select (public.mi_saldo())->>'disponible' as saldo_comprador_21_00;
select public.pagar_con_saldo((select id from public.orders where listing_id='22222222-2222-2222-2222-222222222222'));
\echo '--- 5. retiros: sin datos, menos de $5, más que el saldo, datos recién cambiados'
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select public.pedir_retiro(10);
select pg_temp.yo(''); reset role;
insert into public.private_profiles (id) values ('00000000-0000-0000-0000-00000000000a') on conflict do nothing;
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.private_profiles set payout = '{"banco":"0102 - Banco de Venezuela","cedula":"V-12345678","telefono":"04141234567"}' where id = auth.uid();
select public.pedir_retiro(4);
select public.pedir_retiro(10);
select pg_temp.yo(''); reset role;
alter table public.private_profiles disable trigger user;
update public.private_profiles set payout_cambiado = now() - interval '2 days' where id='00000000-0000-0000-0000-00000000000a';
alter table public.private_profiles enable trigger user;
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select public.pedir_retiro(25);
select public.pedir_retiro(12) is not null as retiro_ok;
select (public.mi_saldo())::text as saldo_tras_retiro;
\echo '--- 6. la vendedora no puede marcarse el retiro como pagado; el admin sí; rechazar devuelve'
select public.admin_pagar_retiro((select id from public.retiros limit 1), 'x');
select pg_temp.yo('00000000-0000-0000-0000-00000000000d');
select (public.admin_datos_retiro((select id from public.retiros limit 1)))->>'telefono' as tel_admin;
select public.admin_pagar_retiro((select id from public.retiros limit 1), '');
select public.admin_pagar_retiro((select id from public.retiros limit 1), '987654');
select public.admin_pagar_retiro((select id from public.retiros limit 1), '987654');
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select public.pedir_retiro(5) is not null as segundo_retiro;
select pg_temp.yo('00000000-0000-0000-0000-00000000000d');
select public.admin_rechazar_retiro((select id from public.retiros where estado='pendiente'), 'Datos incorrectos');
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select (public.mi_saldo())->>'disponible' as saldo_8_devuelto, (select string_agg(estado, ',' order by creado) from public.retiros) as estados;
\echo '--- 7. no puede borrar la cuenta con saldo'
select public.delete_my_account();
\echo '--- 8. el admin ve el cuadre con los saldos'
select pg_temp.yo('00000000-0000-0000-0000-00000000000d');
select (public.admin_cuadre())->>'saldos' as saldos, (public.admin_cuadre())->>'retiros_pendientes' as ret_pend, (public.admin_cuadre())->>'pagado' as pagado;
select texto from public.avisos where user_id='00000000-0000-0000-0000-00000000000a' order by creado desc limit 3;
