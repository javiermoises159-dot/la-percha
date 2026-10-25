\set ON_ERROR_STOP 0
\set VERBOSITY terse
-- usuarios: a=vendedor, b=comprador, c=otro, d=admin
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),
 ('00000000-0000-0000-0000-00000000000c'),('00000000-0000-0000-0000-00000000000d');
insert into public.profiles (id, username, city) values
 ('00000000-0000-0000-0000-00000000000a','vende','Caracas'),('00000000-0000-0000-0000-00000000000b','compra','Caracas'),
 ('00000000-0000-0000-0000-00000000000c','otro','Valencia'),('00000000-0000-0000-0000-00000000000d','jefe','Caracas');
update public.profiles set is_admin = true where username = 'jefe';
insert into public.listings (id, seller_id, title, price, category, size, condition, city) values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-00000000000a','Chaqueta azul',20,'Mujer','M','Bueno','Caracas');

create function pg_temp.yo(u text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', u, false); $$;

\echo '--- 1. comprador intenta pagar la mitad (debe quedar precio 20)'
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
insert into public.orders (listing_id, price, delivery) values ('11111111-1111-1111-1111-111111111111', 10, '{"name":"Ana","phone":"04120000000","address":"Calle 1"}');
select price, fee, status from public.orders;
\echo '--- 2. otro comprador intenta comprar la misma prenda (debe fallar)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
insert into public.orders (listing_id, price) values ('11111111-1111-1111-1111-111111111111', 20);
\echo '--- anuncio reservado?'
select status from public.listings;
\echo '--- 3. vendedor intenta reactivar o cambiar precio (deben fallar)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.listings set status = 'active';
update public.listings set price = 99;
\echo '--- 4. vendedor lee dirección antes del pago (null) y con select directo (error)'
select public.order_delivery(id) from public.orders;
select delivery from public.orders;
\echo '--- vendedor intenta marcar enviado sin pago (falla)'
update public.orders set status = 'enviado', tracking = 'ABC123';
\echo '--- comprador: revision sin referencia (falla), con referencia (ok)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
update public.orders set status = 'revision';
update public.orders set status = 'revision', pay_ref = '123456';
\echo '--- comprador cambia la dirección después de pagar (falla)'
update public.orders set delivery = '{"name":"X"}';
\echo '--- comprador se autoconfirma el pago (falla)'
update public.orders set status = 'retenido';
reset role; select pg_temp.yo('');
\echo '--- admin (panel) confirma el pago'
update public.orders set status = 'retenido';
set role authenticated;
\echo '--- 4b. vendedor ya ve la dirección'
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select public.order_delivery(id)->>'address' from public.orders;
\echo '--- vendedor envía sin seguimiento (falla) y con seguimiento (ok)'
update public.orders set status = 'enviado';
update public.orders set status = 'enviado', tracking = 'MRW-998877';
\echo '--- vendedor se autolibera el pago (falla)'
update public.orders set status = 'liberado';
\echo '--- 5. otro usa la misma referencia de pago (falla)'
reset role; select pg_temp.yo('');
insert into public.listings (id, seller_id, title, price, category, size, condition, city) values
 ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-00000000000a','Falda roja',10,'Mujer','S','Nuevo','Caracas');
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
insert into public.orders (listing_id, price) values ('22222222-2222-2222-2222-222222222222', 10);
update public.orders set status = 'revision', pay_ref = ' 123456' where listing_id = '22222222-2222-2222-2222-222222222222';
\echo '--- 6. caducidad: pedido de c con 25 h se cancela, y el enviado con 8 días se libera'
reset role; select pg_temp.yo('');
update public.orders set created_at = now() - interval '25 hours' where listing_id = '22222222-2222-2222-2222-222222222222';
select public.orders_mantenimiento();
alter table public.orders disable trigger orders_guard;
update public.orders set updated_at = now() - interval '8 days' where listing_id = '11111111-1111-1111-1111-111111111111';
alter table public.orders enable trigger orders_guard;
select public.orders_mantenimiento();
select l.title, l.status as anuncio, o.status as pedido from public.orders o join public.listings l on l.id = o.listing_id order by 1;
\echo '--- 7. foto de web externa (falla) y foto propia (ok)'
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
insert into public.listings (title, price, category, size, condition, city, photos) values
 ('Camisa', 5, 'Hombre','L','Bueno','Caracas', array['https://evil.com/storage/v1/object/public/listing-photos/00000000-0000-0000-0000-00000000000a/x.jpg']);
insert into public.listings (title, price, category, size, condition, city, photos) values
 ('Camisa', 5, 'Hombre','L','Bueno','Caracas', array['https://udhyuyokrxggdnnepbmr.supabase.co/storage/v1/object/public/listing-photos/00000000-0000-0000-0000-00000000000a/x.jpg']);
\echo '--- 8. chat: aviso y resumen; buyer intenta falsificar resumen (falla)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
insert into public.threads (listing_id, seller_id) values ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-00000000000a');
insert into public.messages (thread_id, text) select id, 'Hola, sigue disponible?' from public.threads;
insert into public.messages (thread_id, text) select id, 'escríbeme al 0412 555 1234 y te pago por zelle' from public.threads;
insert into public.messages (thread_id, sender_id, text) select id, '00000000-0000-0000-0000-00000000000a', 'suplanto al vendedor' from public.threads;
select sender_id = '00000000-0000-0000-0000-00000000000b' as yo_mismo, aviso, text from public.messages order by created_at;
update public.threads set last_message = 'falso';
select last_message from public.threads;
\echo '--- 9. nombres: Vende (duplicado), LaPercha_oficial (reservado), hacerme admin (falla)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
update public.profiles set username = 'Vende' where id = auth.uid();
update public.profiles set username = 'LaPercha_oficial' where id = auth.uid();
update public.profiles set is_admin = true where id = auth.uid();
\echo '--- 10. límite 3 pedidos sin pagar'
reset role; select pg_temp.yo('');
insert into public.listings (seller_id, title, price, category, size, condition, city)
 select '00000000-0000-0000-0000-00000000000a', 'Prenda '||g, 5, 'Mujer','S','Nuevo','Caracas' from generate_series(1,4) g;
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
insert into public.orders (listing_id, price) select id, 5 from public.listings where title in ('Prenda 1','Prenda 2','Prenda 3');
insert into public.orders (listing_id, price) select id, 5 from public.listings where title = 'Prenda 4';
\echo '--- comprador cancela y la prenda vuelve a estar activa'
update public.orders set status = 'cancelado' where listing_id = (select id from public.listings where title='Prenda 1');
select status from public.listings where title = 'Prenda 1';
