\set VERBOSITY terse
-- Foto de perfil y distintivos. a=vendedor, b=comprador.
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b');
insert into public.profiles (id, username, city) values
 ('00000000-0000-0000-0000-00000000000a','vende','Caracas'),('00000000-0000-0000-0000-00000000000b','compra','Caracas');
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
select 'sin nada' paso, public.distintivos_de('00000000-0000-0000-0000-00000000000a')->>'foto' obtenido, 'false' esperado;
update public.profiles set avatar_url='https://udhyuyokrxggdnnepbmr.supabase.co/storage/v1/object/public/avatares/00000000-0000-0000-0000-00000000000a/avatar.jpg?v=1' where id='00000000-0000-0000-0000-00000000000a';
select 'foto propia aceptada' paso, public.distintivos_de('00000000-0000-0000-0000-00000000000a')->>'foto' obtenido, 'true' esperado;
\echo '--- deben fallar:'
update public.profiles set avatar_url='https://evil.example/x.png' where id='00000000-0000-0000-0000-00000000000a';
update public.profiles set avatar_url='https://udhyuyokrxggdnnepbmr.supabase.co/storage/v1/object/public/avatares/00000000-0000-0000-0000-00000000000b/avatar.jpg' where id='00000000-0000-0000-0000-00000000000a';
select 'no puede marcar fundador' paso;
update public.profiles set fundador_n = 1 where id='00000000-0000-0000-0000-00000000000a';
reset role;
insert into public.listings (seller_id, title, price, category, size, condition, city)
select '00000000-0000-0000-0000-00000000000a','Prenda de prueba '||g,10,'Mujer','M','Buen estado','Caracas' from generate_series(1,10) g;
select 'primera_prenda y closet_10' paso, public.distintivos_de('00000000-0000-0000-0000-00000000000a')->>'primera_prenda' a, public.distintivos_de('00000000-0000-0000-0000-00000000000a')->>'closet_10' b, 'true / true' esperado;
set session_replication_role = replica;
insert into public.orders (listing_id, buyer_id, seller_id, price, fee, status)
select id,'00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000000a',10,1,'liberado' from public.listings limit 5;
set session_replication_role = origin;
select 'vendedor_5 / primera_compra(b)' paso, public.distintivos_de('00000000-0000-0000-0000-00000000000a')->>'vendedor_5' a, public.distintivos_de('00000000-0000-0000-0000-00000000000b')->>'primera_compra' b, 'true / true' esperado;
