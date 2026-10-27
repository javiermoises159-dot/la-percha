\set VERBOSITY terse
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),('00000000-0000-0000-0000-00000000000c');
insert into public.profiles (id, username, city) values
 ('00000000-0000-0000-0000-00000000000a','vende','Caracas'),('00000000-0000-0000-0000-00000000000b','otra','Caracas'),('00000000-0000-0000-0000-00000000000c','tercera','Caracas');
create function pg_temp.yo(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false); $$;
set role authenticated;
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
\echo '--- 1. primer anuncio da fundador #1 y 3 destacados; el segundo no suma'
insert into public.listings (title, price, category, size, condition, city) values ('Chaqueta',35,'Hombre','L','Buen estado','Caracas');
insert into public.listings (title, price, category, size, condition, city) values ('Falda',20,'Mujer','S','Buen estado','Caracas');
reset role; update public.listings set id = '11111111-1111-1111-1111-111111111111' where title='Chaqueta';
update public.listings set id = '22222222-2222-2222-2222-222222222222' where title='Falda'; set role authenticated;
select username, fundador_n, destacados_gratis from public.profiles where id = auth.uid();
select public.fundadores_restantes() as quedan;
\echo '--- 2. el usuario intenta darse más destacados o cambiar su número (falla)'
update public.profiles set destacados_gratis = 20 where id = auth.uid();
update public.profiles set fundador_n = 0 where id = auth.uid();
select public.lp_dar_fundador(auth.uid());
\echo '--- 3. usa 3 destacados gratis, el 4.º falla'
select public.usar_destacado_gratis('11111111-1111-1111-1111-111111111111') > now() + interval '6 days' as ok1;
select public.usar_destacado_gratis('11111111-1111-1111-1111-111111111111') > now() + interval '13 days' as ok2_acumula;
select public.usar_destacado_gratis('22222222-2222-2222-2222-222222222222') is not null as ok3;
select public.usar_destacado_gratis('22222222-2222-2222-2222-222222222222');
select destacados_gratis from public.profiles where id = auth.uid();
\echo '--- 4. otra persona destaca un anuncio ajeno (falla) y su número es el #2'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
insert into public.listings (title, price, category, size, condition, city) values
 ('Botas',30,'Zapatos','38','Buen estado','Caracas');
select public.usar_destacado_gratis('11111111-1111-1111-1111-111111111111');
select fundador_n, destacados_gratis from public.profiles where id = auth.uid();
\echo '--- 5. el usuario cambia featured_until directo (falla)'
update public.listings set featured_until = now() + interval '1 year' where seller_id = auth.uid();
\echo '--- 6. límite de 200: con 200 ya dados, la tercera no recibe nada'
select pg_temp.yo(''); reset role;
update public.profiles set fundador_n = 200 where id = '00000000-0000-0000-0000-00000000000b';
do $$ begin for i in 3..200 loop insert into auth.users values (('00000000-0000-0000-0001-'||lpad(i::text,12,'0'))::uuid);
  insert into public.profiles (id, username, city, fundador_n) values (('00000000-0000-0000-0001-'||lpad(i::text,12,'0'))::uuid, 'relleno'||i, 'Caracas', i-1); end loop; end $$;
select count(*) filter (where fundador_n is not null) as fundadores from public.profiles;
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
insert into public.listings (title, price, category, size, condition, city) values
 ('Libro',5,'Libros y juegos','No aplica','Buen estado','Caracas');
select fundador_n, destacados_gratis from public.profiles where id = auth.uid();
select public.fundadores_restantes() as quedan;
\echo '--- 7. pedido con precio inventado: ya ni se puede enviar el campo'
insert into public.orders (listing_id, price) values ('11111111-1111-1111-1111-111111111111', 0.01);
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select texto from public.avisos where user_id = '00000000-0000-0000-0000-00000000000a';
