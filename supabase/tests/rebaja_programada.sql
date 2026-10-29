\set VERBOSITY terse
-- Rebaja programada. a=vendedor, b=comprador que tiene la prenda en favoritos, c=otro.
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),('00000000-0000-0000-0000-00000000000c');
insert into public.profiles (id, username, city) values
 ('00000000-0000-0000-0000-00000000000a','vende','Caracas'),('00000000-0000-0000-0000-00000000000b','compra','Caracas'),('00000000-0000-0000-0000-00000000000c','otro','Caracas');
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
insert into public.listings (title, price, category, size, condition, city, rebaja_pct, rebaja_dias)
values ('Con rebaja',20,'Mujer','M','Buen estado','Caracas',10,14);
insert into public.listings (title, price, category, size, condition, city)
values ('Sin rebaja',20,'Mujer','M','Buen estado','Caracas');
select id as con from public.listings where title='Con rebaja' \gset
select id as sin from public.listings where title='Sin rebaja' \gset
select 'fecha puesta por el servidor (14 días)' paso, (rebaja_en::date - now()::date) obtenido, '14' esperado from public.listings where id=:'con';
select 'solo el dueño ve su rebaja' paso, (public.mi_rebaja(:'con')->>'pct') obtenido, '10' esperado;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000b',false);
insert into public.favorites (listing_id) values (:'con');
select 'otro usuario no la ve' paso, coalesce(public.mi_rebaja(:'con')::text,'null') obtenido, 'null' esperado;
\echo '--- deben fallar:'
update public.listings set rebaja_pct = 10, rebaja_dias = 7 where id=:'con';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
update public.listings set rebaja_pct = 50, rebaja_dias = 7 where id=:'con';
update public.listings set rebaja_en = now() - interval '1 day' where id=:'con';
select 'cambiar a 7 días reinicia fecha' paso;
update public.listings set rebaja_pct = 15, rebaja_dias = 7 where id=:'con';
select (rebaja_en::date - now()::date) obtenido, '7' esperado from public.listings where id=:'con';
reset role;
select 'aún no vence: no cambia' paso, public.aplicar_rebajas() obtenido, '0' esperado;
set session_replication_role = replica;
update public.listings set rebaja_en = now() - interval '1 hour' where id=:'con';
set session_replication_role = origin;
select 'vencida: se aplica' paso, public.aplicar_rebajas() obtenido, '1' esperado;
select 'precio nuevo 20 -15% = 17.00' paso, price obtenido, '17.00' esperado, rebaja_pct is null sin_rebaja from public.listings where id=:'con';
select 'aviso al favorito' paso, count(*) obtenido, '1' esperado from public.avisos where user_id='00000000-0000-0000-0000-00000000000b' and texto like 'Bajó de precio%';
select 'no se repite' paso, public.aplicar_rebajas() obtenido, '0' esperado;
select 'sin rebaja no se toca' paso, price obtenido, '20.00' esperado from public.listings where id=:'sin';
