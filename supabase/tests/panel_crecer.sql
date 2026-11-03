\set VERBOSITY terse
insert into auth.users (id) values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),('00000000-0000-0000-0000-00000000000d');
insert into public.profiles (id, username, city, is_admin) values ('00000000-0000-0000-0000-00000000000a','vende','Caracas',false),
 ('00000000-0000-0000-0000-00000000000b','compra','Maracaibo',false),('00000000-0000-0000-0000-00000000000d','jefe','Caracas',true);
insert into public.listings (id, seller_id, title, price, category, size, condition, city) values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-00000000000a','Chaqueta',20,'Hombre','L','Buen estado','Caracas');
create function pg_temp.yo(u text, aal text default 'aal1') returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000' || u, false), set_config('request.jwt.claim.aal', aal, false); $$;
set role authenticated;
\echo '--- pagos cerrados: comprar falla'
select pg_temp.yo('b'); insert into public.orders (listing_id) values ('11111111-1111-1111-1111-111111111111');
\echo '--- usuario normal no puede abrir pagos ni ver la lista (error, error)'
select public.admin_set_config('pagos_abiertos','true');
select * from public.admin_usuarios_activacion();
\echo '--- admin: abrir pagos sin datos de cobro (error); con Binance sí'
select pg_temp.yo('d','aal2');
select public.admin_set_config('pagos_abiertos','true');
select public.admin_set_config('binance_id','123456789');
select public.admin_set_config('pagos_abiertos','true');
select public.admin_set_config('clave_rara','x');
select clave, valor from public.config_app where clave in ('pagos_abiertos','binance_id') order by 1;
\echo '--- ahora sí se puede comprar'
select pg_temp.yo('b'); insert into public.orders (listing_id) values ('11111111-1111-1111-1111-111111111111');
select count(*) as pedidos from public.orders;
\echo '--- lista de activación: compra 0 prendas, vende 1; solo sin prendas = compra'
select pg_temp.yo('d','aal2');
select username, prendas from public.admin_usuarios_activacion() order by 1;
select username from public.admin_usuarios_activacion(true);
\echo '--- simular: todos 2, sin_prendas 1, ciudad maracaibo 1'
select public.admin_enviar_aviso('', 'todos', null, null, true) t, public.admin_enviar_aviso('', 'sin_prendas', null, null, true) s, public.admin_enviar_aviso('', 'ciudad', 'maracaibo', null, true) c;
\echo '--- enviar a sin prendas: 1 aviso tipo pavito para compra'
select public.admin_enviar_aviso('¡Sube 3 prendas y llévate un destacado!', 'sin_prendas');
reset role; select p.username, a.tipo, a.texto from public.avisos a join public.profiles p on p.id = a.user_id where a.tipo = 'pavito'; set role authenticated;
\echo '--- mensaje muy corto (error); usuario normal no puede enviar (error)'
select public.admin_enviar_aviso('hi', 'todos');
select pg_temp.yo('b'); select public.admin_enviar_aviso('Hola a todos', 'todos');
\echo '--- historial: 1'
select pg_temp.yo('d','aal2'); select grupo, enviados from public.admin_comunicados();
\echo '--- anónimo puede leer si los pagos están abiertos pero no cambiarlo (error)'
reset role; set role anon; select public.pagos_abiertos(); select public.admin_set_config('pagos_abiertos','false');
