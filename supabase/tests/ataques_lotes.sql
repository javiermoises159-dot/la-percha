\set VERBOSITY terse
-- a=vendedor, b=comprador, c=otro vendedor, d=admin. Tras supabase_stub.sql y todas las migraciones.
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),
 ('00000000-0000-0000-0000-00000000000c'),('00000000-0000-0000-0000-00000000000d');
insert into public.profiles (id, username, city) values
 ('00000000-0000-0000-0000-00000000000a','vende','Caracas'),('00000000-0000-0000-0000-00000000000b','compra','Caracas'),
 ('00000000-0000-0000-0000-00000000000c','otro','Valencia'),('00000000-0000-0000-0000-00000000000d','jefe','Caracas');
update public.profiles set is_admin = true where username = 'jefe';
insert into public.listings (id, seller_id, title, price, category, size, condition, city) values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-00000000000a','Blusa',10,'Mujer','M','Buen estado','Caracas'),
 ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-00000000000a','Falda',20,'Mujer','S','Buen estado','Caracas'),
 ('33333333-3333-3333-3333-333333333333','00000000-0000-0000-0000-00000000000a','Zapatos',30,'Zapatos','38','Buen estado','Caracas'),
 ('44444444-4444-4444-4444-444444444444','00000000-0000-0000-0000-00000000000c','Libro',5,'Libros y juegos','No aplica','Buen estado','Valencia');
create function pg_temp.yo(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false); $$;
set role authenticated;

\echo '--- vendedor pone descuentos 10/20; otro no puede cambiar los suyos'
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.profiles set lote_2 = 10, lote_3 = 20 where id = auth.uid();
update public.profiles set lote_2 = 60 where id = auth.uid();
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
update public.profiles set lote_2 = 50 where username = 'vende';
\echo '--- lote mezclando vendedores (falla); 1 artículo (falla); lote de 3 (ok, 20 %)'
select public.create_bundle(array['11111111-1111-1111-1111-111111111111','44444444-4444-4444-4444-444444444444']::uuid[], '{"name":"Ana"}');
select public.create_bundle(array['11111111-1111-1111-1111-111111111111']::uuid[], '{}');
select public.create_bundle(array['11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222','33333333-3333-3333-3333-333333333333']::uuid[], '{"name":"Ana","phone":"0414","address":"Calle 2"}') is not null as lote;
select l.title, o.price, o.fee, o.id = o.bundle_id as principal from public.orders o join public.listings l on l.id = o.listing_id order by l.price;
select count(*) as avisos_vendedor from public.avisos where user_id = '00000000-0000-0000-0000-00000000000a';
\echo '--- el comprador intenta cambiar bundle_id o paid_out (falla); paga el lote con una referencia'
update public.orders set bundle_id = null;
update public.orders set status = 'revision', pay_ref = 'REF777' where bundle_id = (select bundle_id from public.orders limit 1);
select count(*) as en_revision from public.orders where status = 'revision';
\echo '--- otro pedido con la misma referencia (falla)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
insert into public.orders (listing_id) values ('44444444-4444-4444-4444-444444444444');
update public.orders set status = 'revision', pay_ref = 'ref777' where listing_id = '44444444-4444-4444-4444-444444444444';
\echo '--- el comprador no puede marcarse pagado; el admin sí; vendedor ve el saldo'
select public.admin_mark_paid((select bundle_id from public.orders where bundle_id is not null limit 1));
reset role; select pg_temp.yo('');
update public.orders set status = 'liberado' where bundle_id is not null;
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000d');
select public.admin_mark_paid((select bundle_id from public.orders where bundle_id is not null limit 1));
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select count(*) filter (where paid_out_at is not null) as cobrados, sum(price) as total from public.orders where seller_id = auth.uid();
\echo '--- denuncias: a sí mismo (falla); doble (falla); ok; el usuario no las ve'
select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
insert into public.reports (listing_id, reason) values ('44444444-4444-4444-4444-444444444444', 'Prueba');
insert into public.reports (listing_id, reason) values ('11111111-1111-1111-1111-111111111111', 'Parece falso');
insert into public.reports (listing_id, reason) values ('11111111-1111-1111-1111-111111111111', 'Parece falso');
select count(*) as ve_denuncias from public.reports;
select public.admin_close_report((select id from public.reports limit 1));
\echo '--- preferencias propias'
insert into public.private_profiles (id, prefs) values (auth.uid(), '{"city":"Valencia","cats":["Hogar"]}');
select prefs->>'city' from public.private_profiles;
