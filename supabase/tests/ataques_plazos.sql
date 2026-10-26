\set VERBOSITY terse
-- Plazos y cuadre. a=vendedor, b=comprador, c=otro, d=admin. Tras supabase_stub.sql y todas las migraciones.
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),
 ('00000000-0000-0000-0000-00000000000c'),('00000000-0000-0000-0000-00000000000d');
insert into public.profiles (id, username, city) values
 ('00000000-0000-0000-0000-00000000000a','vende','Caracas'),('00000000-0000-0000-0000-00000000000b','compra','Caracas'),
 ('00000000-0000-0000-0000-00000000000c','otro','Valencia'),('00000000-0000-0000-0000-00000000000d','jefe','Caracas');
update public.profiles set is_admin = true where username = 'jefe';
update public.ajustes set valor = 400 where clave = 'tasa_bs';
insert into public.listings (id, seller_id, title, price, category, size, condition, city) values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-00000000000a','Blusa',10,'Mujer','M','Buen estado','Caracas'),
 ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-00000000000a','Falda',20,'Mujer','S','Buen estado','Caracas');
create function pg_temp.yo(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false); $$;
set role authenticated;

\echo '--- compra y pago de dos pedidos; el admin confirma: se pone paid_at solo'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
insert into public.orders (listing_id, paid_at, refunded_at) values ('11111111-1111-1111-1111-111111111111', now() - interval '9 days', now());
insert into public.orders (listing_id) values ('11111111-1111-1111-1111-111111111111');
insert into public.orders (listing_id) values ('22222222-2222-2222-2222-222222222222');
select count(*) as sin_fechas_falsas from public.orders where paid_at is null and refunded_at is null;
update public.orders set status = 'revision', pay_ref = 'REF' || substr(listing_id::text, 1, 4);
select pg_temp.yo('00000000-0000-0000-0000-00000000000d');
update public.orders set status = 'retenido';
select count(*) as con_paid_at from public.orders where paid_at is not null;

\echo '--- comprador y vendedor no pueden tocar las fechas ni el reembolso (fallan)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
update public.orders set paid_at = now() - interval '10 days';
update public.orders set refunded_at = now();
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.orders set aviso_envio = true;
select public.admin_mark_refunded((select id from public.orders limit 1));
select public.admin_cuadre();
select set_config('pavito.mantenimiento', 'si', false);
update public.orders set tracking = 'MRW999' where listing_id = '11111111-1111-1111-1111-111111111111';
reset role; select count(*) as aviso_falso from public.orders where aviso_envio; set role authenticated;
select set_config('pavito.mantenimiento', '', false);

\echo '--- pasan 2 días sin envío: aviso al vendedor; pasan 3 días: se cancela la Blusa'
reset role;
alter table public.orders disable trigger orders_sellos;
update public.orders set paid_at = now() - interval '50 hours' where listing_id = '11111111-1111-1111-1111-111111111111';
alter table public.orders enable trigger orders_sellos;
select pg_temp.yo('');
select public.orders_mantenimiento();
select status, aviso_envio from public.orders where listing_id = '11111111-1111-1111-1111-111111111111';
select count(*) as avisos_ultimo_dia from public.avisos where texto like 'Te queda 1 día%';
select public.orders_mantenimiento();
select count(*) as sin_aviso_doble from public.avisos where texto like 'Te queda 1 día%';
alter table public.orders disable trigger orders_sellos;
update public.orders set paid_at = now() - interval '73 hours' where listing_id = '11111111-1111-1111-1111-111111111111';
alter table public.orders enable trigger orders_sellos;
select public.orders_mantenimiento();
select o.status, l.status as anuncio from public.orders o join public.listings l on l.id = o.listing_id
  where o.listing_id = '11111111-1111-1111-1111-111111111111';
select texto from public.avisos where texto like '%5 días hábiles%' or texto like '%no se envió en 3 días%' order by texto;

\echo '--- la Falda se envía y se libera; cuadre: 10,75 por reembolsar, 20 por pagar, 1,25 de tarifa'
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.orders set status = 'enviado', tracking = 'MRW123' where listing_id = '22222222-2222-2222-2222-222222222222';
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
update public.orders set status = 'liberado' where listing_id = '22222222-2222-2222-2222-222222222222';
select shipped_at is not null as enviado_fecha, released_at is not null as liberado_fecha from public.orders
  where listing_id = '22222222-2222-2222-2222-222222222222';
select pg_temp.yo('00000000-0000-0000-0000-00000000000d');
select c->>'reembolsos' as reembolsos, c->>'por_pagar' as por_pagar, c->>'tarifas' as tarifas,
       c->>'terceros' as terceros, c->>'esperado' as esperado from public.admin_cuadre() c;

\echo '--- pago y reembolso atrasados aparecen en el cuadre'
reset role;
alter table public.orders disable trigger orders_sellos;
update public.orders set released_at = now() - interval '6 days' where status = 'liberado';
update public.orders set cancelled_at = now() - interval '9 days' where status = 'cancelado';
alter table public.orders enable trigger orders_sellos;
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000d');
select c->>'pagos_atrasados' as pagos_atrasados, c->>'reembolsos_atrasados' as reembolsos_atrasados from public.admin_cuadre() c;

\echo '--- el admin marca el reembolso y guarda el cuadre (saldo 13.000 Bs a 400 = 32,50 USD)'
select public.admin_mark_refunded((select id from public.orders where status = 'cancelado'));
select refunded_at is not null as reembolsado from public.orders where status = 'cancelado';
reset role; select texto from public.avisos where texto like 'Te devolvimos%';
set role authenticated;
select c->>'reembolsos' as reembolsos_pend, c->>'reembolsado' as reembolsado from public.admin_cuadre() c;
select (r->>'esperado_usd') esperado, (r->>'saldo_usd') saldo, (r->>'diferencia_usd') dif from public.admin_guardar_cuadre(13000, 'Cierre lunes') r;
select public.admin_guardar_cuadre(-5);
select count(*) as cuadres_admin from public.cuadres;

\echo '--- usuarios normales: no ven ni guardan cuadres (fallan / 0 filas)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
select count(*) as cuadres_vistos from public.cuadres;
select public.admin_guardar_cuadre(1);
insert into public.cuadres (esperado_usd, terceros_usd, saldo_bs, tasa, saldo_usd, diferencia_usd) values (0,0,0,1,0,0);
select public.admin_mark_refunded((select id from public.orders limit 1));
