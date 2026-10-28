\set VERBOSITY terse
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),('00000000-0000-0000-0000-00000000000c'),('00000000-0000-0000-0000-00000000000d');
insert into public.profiles (id, username, city, is_admin) values ('00000000-0000-0000-0000-00000000000a','vende','Caracas',false),
 ('00000000-0000-0000-0000-00000000000b','compra','Caracas',false),('00000000-0000-0000-0000-00000000000c','intruso','Caracas',false),('00000000-0000-0000-0000-00000000000d','jefe','Caracas',true);
insert into public.listings (id, seller_id, title, price, category, size, condition, city) values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-00000000000a','Chaqueta',20,'Hombre','L','Buen estado','Caracas');
grant select, insert on storage.objects to authenticated;
create function pg_temp.yo(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000' || u, false); $$;
create function pg_temp.o() returns text language sql as $$ select id::text from public.orders limit 1 $$;
set role authenticated;
select pg_temp.yo('b'); insert into public.orders (listing_id) values ('11111111-1111-1111-1111-111111111111');
update public.orders set status='revision', pay_ref='abcd1234';
select pg_temp.yo('d'); update public.orders set status='retenido';
\echo '--- vendedor sube foto del paquete (sí); comprador no puede subir tipo envío (error)'
select pg_temp.yo('a'); insert into public.pruebas (order_id, tipo, path) values (pg_temp.o()::uuid, 'envio', pg_temp.o() || '/00000000-0000-0000-0000-00000000000a/paquete.jpg');
select pg_temp.yo('b'); insert into public.pruebas (order_id, tipo, path) values (pg_temp.o()::uuid, 'envio', pg_temp.o() || '/00000000-0000-0000-0000-00000000000b/x.jpg');
\echo '--- comprador no puede reclamar antes del envío (error)'
insert into public.pruebas (order_id, tipo, path) values (pg_temp.o()::uuid, 'reclamo', pg_temp.o() || '/00000000-0000-0000-0000-00000000000b/r0.jpg');
select pg_temp.yo('a'); update public.orders set status='enviado', tracking='MRW 1';
\echo '--- comprador sin foto no puede abrir reclamo (error)'
select pg_temp.yo('b'); update public.orders set status='disputa';
\echo '--- ruta de otra persona (error)'
insert into public.pruebas (order_id, tipo, path) values (pg_temp.o()::uuid, 'reclamo', pg_temp.o() || '/00000000-0000-0000-0000-00000000000a/r1.jpg');
\echo '--- con foto sí puede'
insert into public.pruebas (order_id, tipo, path) values (pg_temp.o()::uuid, 'reclamo', pg_temp.o() || '/00000000-0000-0000-0000-00000000000b/r1.jpg');
update public.orders set status='disputa';
select status from public.orders;
\echo '--- quién ve: comprador 2, vendedor 2, intruso 0, admin 2'
select count(*) from public.pruebas;
select pg_temp.yo('a'); select count(*) from public.pruebas;
select pg_temp.yo('c'); select count(*) from public.pruebas;
\echo '--- intruso no puede subir (error)'
insert into public.pruebas (order_id, tipo, path) values (pg_temp.o()::uuid, 'reclamo', pg_temp.o() || '/00000000-0000-0000-0000-00000000000c/r.jpg');
select pg_temp.yo('d'); select count(*) from public.pruebas;
\echo '--- archivos: parte del pedido sí, intruso no (debe dar error), carpeta ajena no (error)'
select pg_temp.yo('b'); insert into storage.objects (bucket_id, name) values ('pruebas', pg_temp.o() || '/00000000-0000-0000-0000-00000000000b/r1.jpg');
select pg_temp.yo('c'); insert into storage.objects (bucket_id, name) values ('pruebas', pg_temp.o() || '/00000000-0000-0000-0000-00000000000c/x.jpg');
select pg_temp.yo('b'); insert into storage.objects (bucket_id, name) values ('pruebas', pg_temp.o() || '/00000000-0000-0000-0000-00000000000a/x.jpg');
\echo '--- ver archivos: intruso 0, vendedor 1'
select pg_temp.yo('c'); select count(*) from storage.objects where bucket_id='pruebas';
select pg_temp.yo('a'); select count(*) from storage.objects where bucket_id='pruebas';
\echo '--- límite de 8'
reset role;
insert into public.pruebas (order_id, autor, tipo, path) select pg_temp.o()::uuid, '00000000-0000-0000-0000-00000000000b', 'reclamo', pg_temp.o() || '/00000000-0000-0000-0000-00000000000b/n' || g || '.jpg' from generate_series(1,7) g;
select count(*) from public.pruebas where autor='00000000-0000-0000-0000-00000000000b';
\echo '--- el 9.º no (error)'
insert into public.pruebas (order_id, autor, tipo, path) values (pg_temp.o()::uuid, '00000000-0000-0000-0000-00000000000b', 'reclamo', pg_temp.o() || '/00000000-0000-0000-0000-00000000000b/n9.jpg');
