\set VERBOSITY terse
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b');
insert into public.profiles (id, username, city) values
 ('00000000-0000-0000-0000-00000000000a','vende','Caracas'),('00000000-0000-0000-0000-00000000000b','otra','Caracas');
create function pg_temp.yo(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false); $$;
set role authenticated;
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
insert into public.listings (title, price, category, size, condition, city, photos) values ('Camisa',10,'Hombre','M','Como nuevo','Caracas','{}');
\echo '--- otra persona no puede marcarlo (debe dar error)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select public.marcar_vendido((select id from public.listings where title='Camisa'));
\echo '--- la dueña sí'
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select public.marcar_vendido((select id from public.listings where title='Camisa'));
select title, status from public.listings where title='Camisa';
\echo '--- dos veces no (debe dar error); y ya no puede volver a ponerlo activo (debe dar error)'
select public.marcar_vendido((select id from public.listings where title='Camisa'));
update public.listings set status='active' where title='Camisa';
select title, status from public.listings where title='Camisa';
\echo '--- anónimo no puede (debe dar error)'
reset role; set role anon;
select public.marcar_vendido((select id from public.listings where title='Camisa'));
