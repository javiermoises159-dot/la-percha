\set VERBOSITY terse
-- Opiniones. a=vendedor, b=comprador con pedido liberado, c=sin pedidos. Tras supabase_stub.sql y todas las migraciones.
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),('00000000-0000-0000-0000-00000000000c');
insert into public.profiles (id, username, city) values
 ('00000000-0000-0000-0000-00000000000a','vende','Caracas'),('00000000-0000-0000-0000-00000000000b','compra','Caracas'),('00000000-0000-0000-0000-00000000000c','nuevo','Caracas');
insert into public.listings (id, seller_id, title, price, category, size, condition, city)
values ('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-00000000000a','Prenda de prueba',10,'Mujer','M','Buen estado','Caracas');
set session_replication_role = replica;
insert into public.orders (listing_id, buyer_id, seller_id, price, fee, status)
values ('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000000a',10,1,'liberado');
set session_replication_role = origin;
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000c',false);
select 'sin pedidos: quiere_opinar' paso, public.quiere_opinar() obtenido, 'false' esperado;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000b',false);
select 'comprador con pedido liberado' paso, public.quiere_opinar() obtenido, 'true' esperado;
insert into public.opiniones(estrellas,comentario) values (5,'Muy bueno');
select 'ya opinó: quiere_opinar' paso, public.quiere_opinar() obtenido, 'false' esperado;
select 've la suya' paso, count(*) obtenido, '1' esperado from public.opiniones;
\echo '--- deben fallar:'
insert into public.opiniones(estrellas) values (4);
insert into public.opiniones(estrellas) values (9);
insert into public.opiniones(estrellas, user_id) values (3,'00000000-0000-0000-0000-00000000000c');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
select 'vendedor también debe poder opinar' paso, public.quiere_opinar() obtenido, 'true' esperado;
select 'otro no ve la ajena' paso, count(*) obtenido, '0' esperado from public.opiniones;
