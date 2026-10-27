\set VERBOSITY terse
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),('00000000-0000-0000-0000-00000000000d');
insert into public.profiles (id, username, city, is_admin) values ('00000000-0000-0000-0000-00000000000a','vende','Caracas',false),
 ('00000000-0000-0000-0000-00000000000b','compra','Caracas',false),('00000000-0000-0000-0000-00000000000d','jefe','Caracas',true);
insert into public.listings (id, seller_id, title, price, category, size, condition, city) values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-00000000000a','Chaqueta',20,'Hombre','L','Buen estado','Caracas'),
 ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-00000000000a','Falda',10,'Mujer','S','Buen estado','Caracas');
create function pg_temp.yo(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false); $$;
create function pg_temp.hasta_disputa(l text) returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000b',false); set role authenticated;
  insert into public.orders (listing_id) values (l::uuid);
  update public.orders set status='revision', pay_ref=left(md5(l),8) where listing_id=l::uuid;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000d',false);
  update public.orders set status='retenido' where listing_id=l::uuid;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
  update public.orders set status='enviado', tracking='MRW 1' where listing_id=l::uuid;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000b',false);
  update public.orders set status='disputa' where listing_id=l::uuid;
  reset role; end $$;
select pg_temp.hasta_disputa('11111111-1111-1111-1111-111111111111');
set role authenticated;
\echo '--- comprador no puede pedirse la devolución ni poner guía antes; admin la pide'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
update public.orders set status='devolucion' where listing_id='11111111-1111-1111-1111-111111111111';
update public.orders set guia_devolucion='MRW 999' where listing_id='11111111-1111-1111-1111-111111111111';
select pg_temp.yo('00000000-0000-0000-0000-00000000000d');
update public.orders set status='devolucion' where listing_id='11111111-1111-1111-1111-111111111111';
select status, devolucion_at is not null as fecha from public.orders where listing_id='11111111-1111-1111-1111-111111111111';
\echo '--- el vendedor no puede confirmar antes de la guía ni poner guía; comprador pone guía (una vez)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.orders set status='cancelado' where listing_id='11111111-1111-1111-1111-111111111111';
update public.orders set guia_devolucion='x' where listing_id='11111111-1111-1111-1111-111111111111';
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
update public.orders set guia_devolucion='ok' where listing_id='11111111-1111-1111-1111-111111111111';
update public.orders set guia_devolucion='Tealca 12345' where listing_id='11111111-1111-1111-1111-111111111111';
update public.orders set guia_devolucion='otra' where listing_id='11111111-1111-1111-1111-111111111111';
update public.orders set status='cancelado' where listing_id='11111111-1111-1111-1111-111111111111';
\echo '--- vendedor confirma que recibió: reembolso al saldo del comprador; anuncio vuelve a la venta'
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.orders set status='cancelado' where listing_id='11111111-1111-1111-1111-111111111111';
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select (public.mi_saldo())->>'disponible' as saldo_21_25;
select status from public.listings where id='11111111-1111-1111-1111-111111111111';
\echo '--- plazos: sin guía en 3 días hábiles → vendedor cobra'
select pg_temp.hasta_disputa('22222222-2222-2222-2222-222222222222');
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000d');
update public.orders set status='devolucion' where listing_id='22222222-2222-2222-2222-222222222222';
select pg_temp.yo(''); reset role;
alter table public.orders disable trigger orders_zdevolucion;
update public.orders set devolucion_at = now() - interval '6 days' where listing_id='22222222-2222-2222-2222-222222222222';
alter table public.orders enable trigger orders_zdevolucion;
select public.devoluciones_mantenimiento();
select status from public.orders where listing_id='22222222-2222-2222-2222-222222222222';
select sum(monto) as saldo_vendedora_10 from public.movimientos where user_id='00000000-0000-0000-0000-00000000000a';
select texto from public.avisos where user_id='00000000-0000-0000-0000-00000000000b' and texto like 'Resolvimos%' limit 1;
