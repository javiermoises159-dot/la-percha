\set VERBOSITY terse
-- a=vendedor, b=comprador, d=admin. Tras supabase_stub.sql y todas las migraciones.
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),('00000000-0000-0000-0000-00000000000d');
insert into public.profiles (id, username, city) values
 ('00000000-0000-0000-0000-00000000000a','vende','Caracas'),('00000000-0000-0000-0000-00000000000b','compra','Caracas'),
 ('00000000-0000-0000-0000-00000000000d','jefe','Caracas');
update public.profiles set is_admin = true where username = 'jefe';
insert into public.listings (id, seller_id, title, price, category, size, condition, city) values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-00000000000a','Vestido rojo',20,'Mujer','M','Buen estado','Caracas');
create function pg_temp.yo(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false); $$;

\echo '--- tasa: 0 -> 300 ok; 9000 rechazada (filtro); usuario no puede cambiarla'
select public.guardar_tasa(300), public.guardar_tasa(9000), (select valor from public.ajustes);
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
update public.ajustes set valor = 1;
select public.admin_set_tasa(1);
select public.guardar_tasa(1);
\echo '--- seguir: ok; seguir en nombre de otro (falla); ver contador'
insert into public.follows (seller_id) values ('00000000-0000-0000-0000-00000000000a');
insert into public.follows (follower_id, seller_id) values ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000d');
select public.followers_count('00000000-0000-0000-0000-00000000000a') as seguidores;
\echo '--- favorito guarda precio 20 aunque mande otro'
insert into public.favorites (listing_id, price_at) values ('11111111-1111-1111-1111-111111111111', 999);
select price_at from public.favorites;
\echo '--- destacar: el comprador no puede destacar anuncio ajeno; el vendedor no puede ponerse destacado gratis'
select public.request_promotion('11111111-1111-1111-1111-111111111111', 7, 'REF1234');
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.listings set featured_until = now() + interval '30 days';
select public.request_promotion('11111111-1111-1111-1111-111111111111', 7, 'REF1234') is not null as solicitada;
select public.admin_review_promotion((select id from public.promotions), true);
select pg_temp.yo('00000000-0000-0000-0000-00000000000d');
select public.admin_review_promotion((select id from public.promotions), true);
select featured_until > now() + interval '6 days' as destacado_7_dias, (select amount from public.promotions) as pago from public.listings;
\echo '--- el vendedor sigue pudiendo editar título'
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.listings set title = 'Vestido rojo talla M' returning title;
