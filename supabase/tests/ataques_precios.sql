\set VERBOSITY terse
-- Manipulación de precios, cantidades y totales. a=vendedor, b=comprador, c=otro vendedor, d=admin.
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),
 ('00000000-0000-0000-0000-00000000000c'),('00000000-0000-0000-0000-00000000000d');
insert into public.profiles (id, username, city) values
 ('00000000-0000-0000-0000-00000000000a','vende','Caracas'),('00000000-0000-0000-0000-00000000000b','compra','Caracas'),
 ('00000000-0000-0000-0000-00000000000c','otro','Valencia'),('00000000-0000-0000-0000-00000000000d','jefe','Caracas');
insert into public.listings (id, seller_id, title, price, category, size, condition, city) values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-00000000000a','Chaqueta',35,'Hombre','L','Buen estado','Caracas'),
 ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-00000000000a','Falda',20,'Mujer','S','Buen estado','Caracas'),
 ('33333333-3333-3333-3333-333333333333','00000000-0000-0000-0000-00000000000a','Botas',30,'Zapatos','38','Buen estado','Caracas'),
 ('44444444-4444-4444-4444-444444444444','00000000-0000-0000-0000-00000000000c','Libro',5,'Libros y juegos','No aplica','Buen estado','Valencia');
create function pg_temp.yo(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false); $$;
set role authenticated;
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');

\echo '--- 1. el comprador manda precio 0,01 / -1 / 0 / 99999 (el único campo de precio que puede enviar): el servidor usa el de la base'
insert into public.orders (listing_id, price, fee) values ('11111111-1111-1111-1111-111111111111', 0.01, 0);
insert into public.orders (listing_id, price) values ('11111111-1111-1111-1111-111111111111', 0.01);
select price, fee, price + fee as total from public.orders where listing_id = '11111111-1111-1111-1111-111111111111';
update public.orders set status = 'cancelado' where listing_id = '11111111-1111-1111-1111-111111111111';
select l.status as anuncio_tras_cancelar from public.listings l where id = '11111111-1111-1111-1111-111111111111';
insert into public.orders (listing_id, price) values ('11111111-1111-1111-1111-111111111111', -1);
insert into public.orders (listing_id, price) values ('22222222-2222-2222-2222-222222222222', 0);
insert into public.orders (listing_id, price) values ('33333333-3333-3333-3333-333333333333', 99999);
select l.title, o.price, o.fee from public.orders o join public.listings l on l.id = o.listing_id
  where o.status = 'esperando_pago' order by l.title;
\echo '--- 2. inventarse el estado, el comprador o el vendedor al crear (se ignoran o fallan)'
select pg_temp.yo(''); reset role; update public.orders set status = 'cancelado'; set role authenticated;
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
insert into public.orders (listing_id, status, seller_id, buyer_id) values ('11111111-1111-1111-1111-111111111111', 'retenido', '00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000c');
select status, seller_id = '00000000-0000-0000-0000-00000000000a' as vendedor_real, buyer_id = auth.uid() as comprador_real
  from public.orders where status <> 'cancelado';
\echo '--- 3. cambiar el precio o la tarifa después de crear el pedido (fallan)'
update public.orders set price = 1 where status = 'esperando_pago';
update public.orders set fee = 0 where status = 'esperando_pago';
select price, fee from public.orders where status = 'esperando_pago';
\echo '--- 4. comprar algo propio, inexistente o ya reservado (fallan)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
insert into public.orders (listing_id) values ('22222222-2222-2222-2222-222222222222');
select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
insert into public.orders (listing_id) values ('99999999-9999-9999-9999-999999999999');
insert into public.orders (listing_id) values ('11111111-1111-1111-1111-111111111111');
select pg_temp.yo(''); reset role; update public.orders set status = 'cancelado'; set role authenticated;

\echo '--- 5. "cantidades" en lotes: vacío, 1, repetidos, 11 artículos, de otro vendedor (fallan)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select public.create_bundle(array[]::uuid[], '{"name":"Ana","phone":"0414","address":"Calle 2"}');
select public.create_bundle(array['11111111-1111-1111-1111-111111111111']::uuid[], '{"name":"Ana","phone":"0414","address":"Calle 2"}');
select public.create_bundle(array['11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111']::uuid[], '{"name":"Ana","phone":"0414","address":"Calle 2"}');
select public.create_bundle(array_fill('22222222-2222-2222-2222-222222222222'::uuid, array[11]), '{"name":"Ana","phone":"0414","address":"Calle 2"}');
select public.create_bundle(array['11111111-1111-1111-1111-111111111111','44444444-4444-4444-4444-444444444444']::uuid[], '{"name":"Ana","phone":"0414","address":"Calle 2"}');
select count(*) as pedidos_creados from public.orders where status = 'esperando_pago';

\echo '--- 6. ofertas: -1, 0, 99999, menos del 50 %, a sí mismo (fallan); 20 sobre 35 (ok)'
select public.make_offer('11111111-1111-1111-1111-111111111111', -1);
select public.make_offer('11111111-1111-1111-1111-111111111111', 0);
select public.make_offer('11111111-1111-1111-1111-111111111111', 99999);
select public.make_offer('11111111-1111-1111-1111-111111111111', 10);
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select public.make_offer('11111111-1111-1111-1111-111111111111', 30);
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select public.make_offer('11111111-1111-1111-1111-111111111111', 20) is not null as oferta_ok;
\echo '--- 7. el comprador intenta aceptar su propia oferta o cambiar el monto (fallan)'
select public.respond_offer((select id from public.offers limit 1), true);
update public.offers set amount = 1;
\echo '--- 8. el vendedor acepta: el pedido sale a $20 aunque el comprador mande $1'
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select public.respond_offer((select id from public.offers limit 1), true);
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
insert into public.orders (listing_id, price) values ('11111111-1111-1111-1111-111111111111', 1);
select price, fee, price + fee as total from public.orders where status = 'esperando_pago';
\echo '--- 9. otra persona no puede usar esa oferta: paga el precio completo'
select pg_temp.yo(''); reset role; update public.orders set status = 'cancelado'; set role authenticated;
select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
insert into public.orders (listing_id, price) values ('11111111-1111-1111-1111-111111111111', 20);
select price from public.orders where status = 'esperando_pago';
select pg_temp.yo(''); reset role; update public.orders set status = 'cancelado'; set role authenticated;

\echo '--- 10. destacados: días inventados (fallan); 3 días cuestan 1 USD aunque nadie lo diga'
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select public.request_promotion('22222222-2222-2222-2222-222222222222', 30, 'REF900');
select public.request_promotion('22222222-2222-2222-2222-222222222222', -3, 'REF901');
select public.request_promotion('22222222-2222-2222-2222-222222222222', 3, 'REF902') is not null as ok;
select days, amount from public.promotions;
insert into public.promotions (listing_id, seller_id, days, amount, pay_ref) values ('22222222-2222-2222-2222-222222222222', auth.uid(), 7, 0.01, 'REF903');
update public.promotions set amount = 0.01, status = 'activa';
