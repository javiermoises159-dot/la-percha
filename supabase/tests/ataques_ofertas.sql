\set VERBOSITY terse
-- a=vendedor, b=comprador, c=otro. Ejecutar tras supabase_stub.sql y todas las migraciones.
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),('00000000-0000-0000-0000-00000000000c');
insert into public.profiles (id, username, city) values
 ('00000000-0000-0000-0000-00000000000a','vende','Caracas'),('00000000-0000-0000-0000-00000000000b','compra','Caracas'),
 ('00000000-0000-0000-0000-00000000000c','otro','Valencia');
insert into public.listings (id, seller_id, title, price, category, size, condition, city) values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-00000000000a','Licuadora Oster',40,'Hogar','No aplica','Buen estado','Caracas');
create function pg_temp.yo(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false); $$;
set role authenticated;

\echo '--- oferta demasiado baja (falla) y oferta válida de 30'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select public.make_offer('11111111-1111-1111-1111-111111111111', 10);
select public.make_offer('11111111-1111-1111-1111-111111111111', 30) is not null as ok;
\echo '--- el comprador intenta aceptar su propia oferta (falla) o escribir en offers (falla)'
select public.respond_offer((select id from public.offers limit 1), true);
insert into public.offers (listing_id, buyer_id, seller_id, proposer_id, amount, status)
 values ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000a',1,'aceptada');
\echo '--- un tercero no ve la oferta ni puede responderla'
select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
select count(*) as ve_ofertas from public.offers;
select public.respond_offer((select id from public.offers limit 1), true);
\echo '--- vendedor contraoferta 35 al comprador, el comprador acepta'
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select public.make_offer('11111111-1111-1111-1111-111111111111', 35, '00000000-0000-0000-0000-00000000000b') is not null as ok;
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select public.respond_offer((select id from public.offers where status = 'pendiente'), true);
select public.my_price('11111111-1111-1111-1111-111111111111') as mi_precio;
\echo '--- otro comprador sigue pagando 40'
select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
select public.my_price('11111111-1111-1111-1111-111111111111') as su_precio;
\echo '--- el comprador compra: precio 35, oferta usada; mensajes del chat'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
insert into public.orders (listing_id, price) values ('11111111-1111-1111-1111-111111111111', 1);
select price, fee from public.orders;
select status, amount from public.offers order by created_at;
select text from public.messages order by created_at;
\echo '--- reseña antes de completar (falla)'
select public.leave_review((select id from public.orders limit 1), 5, 'Genial');
reset role; select pg_temp.yo('');
update public.orders set status = 'liberado';
set role authenticated;
\echo '--- reseñas: comprador 5, vendedor 4; repetir (falla); tercero (falla); escribir directo (falla)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select public.leave_review((select id from public.orders limit 1), 5, 'Todo perfecto');
select public.leave_review((select id from public.orders limit 1), 1, 'otra vez');
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select public.leave_review((select id from public.orders limit 1), 4, 'Pagó rápido');
select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
select public.leave_review((select id from public.orders limit 1), 1, 'falsa');
insert into public.reviews (order_id, author_id, target_id, stars) select id, '00000000-0000-0000-0000-00000000000c', seller_id, 1 from public.orders;
update public.profiles set rating_avg = 5 where id = auth.uid();
select username, rating_avg, rating_count from public.profiles order by 1;
\echo '--- vacaciones: el vendedor activa; otro no ve su anuncio activo ni puede ofertar'
reset role; select pg_temp.yo('');
insert into public.listings (id, seller_id, title, price, category, size, condition, city) values
 ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-00000000000a','Libro Cien años',8,'Libros y juegos','No aplica','Muy buen estado','Caracas');
set role authenticated;
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.profiles set vacation = true where id = auth.uid();
select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
select count(*) as ve_libro from public.listings where id = '22222222-2222-2222-2222-222222222222';
select public.make_offer('22222222-2222-2222-2222-222222222222', 6);
insert into public.orders (listing_id) values ('22222222-2222-2222-2222-222222222222');
\echo '--- anónimo ve reseñas (perfil público)'
reset role; set role anon;
select count(*) as resenas_publicas from public.reviews;
