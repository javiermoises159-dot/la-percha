\set VERBOSITY terse
-- Estado del anuncio (active/reserved/sold) a lo largo de TODA la vida de un pedido.
-- a=vendedor, b=comprador, c=otro comprador, d=admin. Tras supabase_stub.sql y todas las migraciones.
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),
 ('00000000-0000-0000-0000-00000000000c'),('00000000-0000-0000-0000-00000000000d');
insert into public.profiles (id, username, city) values
 ('00000000-0000-0000-0000-00000000000a','vende','Caracas'),('00000000-0000-0000-0000-00000000000b','compra','Caracas'),
 ('00000000-0000-0000-0000-00000000000c','otro','Caracas'),('00000000-0000-0000-0000-00000000000d','jefe','Caracas');
update public.profiles set is_admin = true where username = 'jefe';
insert into public.listings (id, seller_id, title, price, category, size, condition, city)
select ('00000000-0000-0000-0000-0000000001' || lpad(g::text,2,'0'))::uuid, '00000000-0000-0000-0000-00000000000a', 'Prenda '||g, 10, 'Mujer','M','Buen estado','Caracas' from generate_series(1,16) g;
create function pg_temp.yo(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false); $$;
create function pg_temp.p(n int) returns uuid language sql as $$ select ('00000000-0000-0000-0000-0000000001' || lpad(n::text,2,'0'))::uuid $$;
create function pg_temp.est(n int) returns text language sql as $$ select status from public.listings where id = pg_temp.p(n) $$;
-- comprador compra la prenda n
create function pg_temp.compra(n int) returns void language sql as $$ insert into public.orders (listing_id, delivery) values (pg_temp.p(n), '{"name":"Ana","phone":"0414","address":"Calle 2","ciudad":"Caracas","metodo":"MRW"}') $$;
create function pg_temp.ped(n int) returns uuid language sql as $$ select id from public.orders where listing_id = pg_temp.p(n) order by created_at desc limit 1 $$;
\set liberar 'reset role; set session_replication_role = replica; update public.orders set created_at = created_at - interval ''2 hours''; set session_replication_role = origin; set role authenticated;'
set role authenticated;

\echo '=== A. CAMINO FELIZ: compra → paga → admin confirma → vendedor envía → comprador confirma'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); :liberar select pg_temp.compra(1);
select 'A1 pedido creado' paso, pg_temp.est(1) anuncio, 'reserved' esperado;
update public.orders set status='revision', pay_ref='REF0001' where id = pg_temp.ped(1);
select 'A2 comprador dice que pagó' paso, pg_temp.est(1) anuncio, 'reserved' esperado;
select pg_temp.yo(''); reset role; update public.orders set status='retenido' where id = pg_temp.ped(1); set role authenticated;
select 'A3 admin confirma el pago' paso, pg_temp.est(1) anuncio, 'reserved' esperado;
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.orders set status='enviado', tracking='MRW123456' where id = pg_temp.ped(1);
select 'A4 vendedor envía' paso, pg_temp.est(1) anuncio, 'reserved' esperado;
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
update public.orders set status='liberado' where id = pg_temp.ped(1);
select 'A5 comprador confirma' paso, pg_temp.est(1) anuncio, 'sold' esperado;
select 'A6 el inicio (status=active) ya no la muestra' paso, count(*) filas, 0 esperado from public.listings where status='active' and id = pg_temp.p(1);
\echo '--- A7 nadie puede volver a comprarla, ni el vendedor ocultarla/editarla/borrarla (todo debe fallar)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000c'); :liberar select pg_temp.compra(1);
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.listings set status='active' where id = pg_temp.p(1);
update public.listings set status='hidden' where id = pg_temp.p(1);
update public.listings set price = 1 where id = pg_temp.p(1);
delete from public.listings where id = pg_temp.p(1);
select 'A8 sigue vendida' paso, pg_temp.est(1) anuncio, 'sold' esperado;

\echo '=== B. EL COMPRADOR CANCELA ANTES DE PAGAR → vuelve a la venta y otro puede comprarla'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); :liberar select pg_temp.compra(2);
select 'B1 reservada' paso, pg_temp.est(2) anuncio, 'reserved' esperado;
update public.orders set status='cancelado' where id = pg_temp.ped(2);
select 'B2 comprador cancela' paso, pg_temp.est(2) anuncio, 'active' esperado;
select pg_temp.yo('00000000-0000-0000-0000-00000000000c'); :liberar select pg_temp.compra(2);
select 'B3 otro la compra' paso, pg_temp.est(2) anuncio, 'reserved' esperado;

\echo '=== C. EL VENDEDOR CANCELA ANTES DE PAGAR'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); :liberar select pg_temp.compra(3);
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.orders set status='cancelado' where id = pg_temp.ped(3);
select 'C1 vendedor cancela' paso, pg_temp.est(3) anuncio, 'active' esperado;

\echo '=== D. NO PAGÓ EN 24 HORAS → se cancela solo y vuelve a la venta'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); :liberar select pg_temp.compra(4);
select pg_temp.yo(''); reset role;
update public.orders set created_at = now() - interval '25 hours' where id = pg_temp.ped(4);
select public.orders_mantenimiento();
set role authenticated;
select 'D1 expira' paso, pg_temp.est(4) anuncio, 'active' esperado;

\echo '=== E. PAGO RECHAZADO POR EL ADMIN en revisión'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); :liberar select pg_temp.compra(5);
update public.orders set status='revision', pay_ref='REF0005' where id = pg_temp.ped(5);
select pg_temp.yo(''); reset role; update public.orders set status='cancelado' where id = pg_temp.ped(5); set role authenticated;
select 'E1 admin rechaza' paso, pg_temp.est(5) anuncio, 'active' esperado;

\echo '=== F. DESPUÉS DE PAGAR: ni comprador ni vendedor pueden cancelar solos (deben fallar); admin reembolsa'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); :liberar select pg_temp.compra(6);
update public.orders set status='revision', pay_ref='REF0006' where id = pg_temp.ped(6);
update public.orders set status='cancelado' where id = pg_temp.ped(6);
select pg_temp.yo(''); reset role; update public.orders set status='retenido' where id = pg_temp.ped(6); set role authenticated;
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); update public.orders set status='cancelado' where id = pg_temp.ped(6);
select pg_temp.yo('00000000-0000-0000-0000-00000000000a'); update public.orders set status='cancelado' where id = pg_temp.ped(6);
select 'F1 sigue reservada' paso, pg_temp.est(6) anuncio, 'reserved' esperado;
select pg_temp.yo(''); reset role; update public.orders set status='cancelado' where id = pg_temp.ped(6); set role authenticated;
select 'F2 admin reembolsa antes del envío' paso, pg_temp.est(6) anuncio, 'active' esperado;

\echo '=== G. ENVIADO Y NO RESPONDE EN 7 DÍAS → se libera solo → vendida'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); :liberar select pg_temp.compra(7);
update public.orders set status='revision', pay_ref='REF0007' where id = pg_temp.ped(7);
select pg_temp.yo(''); reset role; update public.orders set status='retenido' where id = pg_temp.ped(7); set role authenticated;
select pg_temp.yo('00000000-0000-0000-0000-00000000000a'); update public.orders set status='enviado', tracking='ZOOM777' where id = pg_temp.ped(7);
select pg_temp.yo(''); reset role; set session_replication_role = replica; update public.orders set updated_at = now() - interval '8 days', shipped_at = now() - interval '8 days' where id = pg_temp.ped(7); set session_replication_role = origin;
select public.orders_mantenimiento(); set role authenticated;
select 'G1 libera solo' paso, pg_temp.est(7) anuncio, 'sold' esperado;

\echo '=== H. DISPUTA → devolución → vendedor confirma el regreso → reembolso → vuelve a la venta'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); :liberar select pg_temp.compra(8);
update public.orders set status='revision', pay_ref='REF0008' where id = pg_temp.ped(8);
select pg_temp.yo(''); reset role; update public.orders set status='retenido' where id = pg_temp.ped(8); set role authenticated;
select pg_temp.yo('00000000-0000-0000-0000-00000000000a'); update public.orders set status='enviado', tracking='TEALCA8' where id = pg_temp.ped(8);
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); insert into public.pruebas (order_id, tipo, path, es_video, autor) values (pg_temp.ped(8), 'reclamo', pg_temp.ped(8)::text || '/' || auth.uid()::text || '/f.jpg', false, auth.uid()); update public.orders set status='disputa' where id = pg_temp.ped(8);
select 'H1 en disputa' paso, pg_temp.est(8) anuncio, 'reserved' esperado;
select pg_temp.yo(''); reset role; update public.orders set status='devolucion', devolucion_at=now() where id = pg_temp.ped(8); set role authenticated;
select 'H2 pide devolución' paso, pg_temp.est(8) anuncio, 'reserved' esperado;
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); update public.orders set guia_devolucion='MRW 99999' where id = pg_temp.ped(8);
select 'H3 comprador manda la guía' paso, pg_temp.est(8) anuncio, 'reserved' esperado;
select pg_temp.yo('00000000-0000-0000-0000-00000000000a'); update public.orders set status='cancelado' where id = pg_temp.ped(8);
select 'H4 vendedor recibió la devolución' paso, pg_temp.est(8) anuncio, 'active' esperado;

\echo '=== I. DISPUTA que el admin resuelve a favor del vendedor → vendida'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); :liberar select pg_temp.compra(9);
update public.orders set status='revision', pay_ref='REF0009' where id = pg_temp.ped(9);
select pg_temp.yo(''); reset role; update public.orders set status='retenido' where id = pg_temp.ped(9); set role authenticated;
select pg_temp.yo('00000000-0000-0000-0000-00000000000a'); update public.orders set status='enviado', tracking='MRW9' where id = pg_temp.ped(9);
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); insert into public.pruebas (order_id, tipo, path, es_video, autor) values (pg_temp.ped(9), 'reclamo', pg_temp.ped(9)::text || '/' || auth.uid()::text || '/f.jpg', false, auth.uid()); update public.orders set status='disputa' where id = pg_temp.ped(9);
select pg_temp.yo(''); reset role; update public.orders set status='liberado' where id = pg_temp.ped(9); set role authenticated;
select 'I1 admin paga al vendedor' paso, pg_temp.est(9) anuncio, 'sold' esperado;

\echo '=== J. DEVOLUCIÓN: el comprador no envía a tiempo → se cierra a favor del vendedor → vendida'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); :liberar select pg_temp.compra(10);
update public.orders set status='revision', pay_ref='REF0010' where id = pg_temp.ped(10);
select pg_temp.yo(''); reset role; update public.orders set status='retenido' where id = pg_temp.ped(10); set role authenticated;
select pg_temp.yo('00000000-0000-0000-0000-00000000000a'); update public.orders set status='enviado', tracking='Z10' where id = pg_temp.ped(10);
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); insert into public.pruebas (order_id, tipo, path, es_video, autor) values (pg_temp.ped(10), 'reclamo', pg_temp.ped(10)::text || '/' || auth.uid()::text || '/f.jpg', false, auth.uid()); update public.orders set status='disputa' where id = pg_temp.ped(10);
select pg_temp.yo(''); reset role; update public.orders set status='devolucion' where id = pg_temp.ped(10); set session_replication_role = replica; update public.orders set devolucion_at = now() - interval '10 days' where id = pg_temp.ped(10); set session_replication_role = origin;
select public.devoluciones_mantenimiento(); set role authenticated;
select 'J1 plazo vencido' paso, pg_temp.est(10) anuncio, 'sold' esperado;

\echo '=== K. EL VENDEDOR NO PUEDE OCULTAR NI BORRAR UNA PRENDA RESERVADA (deben fallar)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); :liberar select pg_temp.compra(11);
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.listings set status='hidden' where id = pg_temp.p(11);
delete from public.listings where id = pg_temp.p(11);
select 'K1 sigue reservada' paso, pg_temp.est(11) anuncio, 'reserved' esperado;

\echo '=== L. PRENDA OCULTA o de vendedor pausado: nadie puede comprarla (debe fallar)'
update public.listings set status='hidden' where id = pg_temp.p(12);
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); :liberar select pg_temp.compra(12);
select 'L1 oculta sigue oculta' paso, pg_temp.est(12) anuncio, 'hidden' esperado;


\echo '=== P. EL VENDEDOR NO ENVÍA EN 3 DÍAS tras confirmarse el pago → se cancela solo → vuelve a la venta'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); :liberar select pg_temp.compra(16);
update public.orders set status='revision', pay_ref='REF0016' where id = pg_temp.ped(16);
select pg_temp.yo(''); reset role; update public.orders set status='retenido' where id = pg_temp.ped(16);
set session_replication_role = replica; update public.orders set paid_at = now() - interval '4 days' where id = pg_temp.ped(16); set session_replication_role = origin;
select public.orders_mantenimiento(); set role authenticated;
select 'P1 vendedor no envió' paso, pg_temp.est(16) anuncio, 'active' esperado;

\echo '=== M. OFERTAS dentro del ciclo'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select 'M1 oferta de 8 sobre 10 (ok)' paso, public.make_offer(pg_temp.p(13), 8) is not null ok;
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select public.respond_offer((select id from public.offers where listing_id = pg_temp.p(13) and status='pendiente'), true);
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select 'M2 su precio con la oferta aceptada' paso, public.my_price(pg_temp.p(13)) precio, 8 esperado;
:liberar select pg_temp.compra(13);
select 'M3 compra al precio ofertado' paso, price, fee, 8 esperado from public.orders where listing_id = pg_temp.p(13);
select 'M4 oferta queda usada' paso, status, 'usada' esperado from public.offers where listing_id = pg_temp.p(13);
select 'M5 prenda reservada' paso, pg_temp.est(13) anuncio, 'reserved' esperado;
\echo '--- M6 nadie puede ofertar sobre una prenda reservada o vendida (deben fallar)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
select public.make_offer(pg_temp.p(13), 8);
select public.make_offer(pg_temp.p(1), 8);
\echo '--- M7 oferta pendiente y otro compra primero: el vendedor intenta aceptarla'
select public.make_offer(pg_temp.p(14), 8) is not null as oferta_c_pendiente;
select pg_temp.yo('00000000-0000-0000-0000-00000000000b'); :liberar select pg_temp.compra(14);
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select public.respond_offer((select id from public.offers where listing_id = pg_temp.p(14) and status='pendiente'), true);
select 'M8 c no puede comprarla (ya reservada por b)' paso, pg_temp.est(14) anuncio, 'reserved' esperado;
select pg_temp.yo('00000000-0000-0000-0000-00000000000c'); :liberar select pg_temp.compra(14);
\echo '--- M9 el comprador cancela el pedido: ¿puede volver a comprar al precio ofertado? (precio que cobra)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
update public.orders set status='cancelado' where id = pg_temp.ped(13);
select 'M10 vuelve a la venta' paso, pg_temp.est(13) anuncio, 'active' esperado;
select 'M11 estado de la oferta tras cancelar' paso, status from public.offers where listing_id = pg_temp.p(13);
:liberar select pg_temp.compra(13);
select 'M12 precio al recomprar' paso, price from public.orders where listing_id = pg_temp.p(13) order by created_at desc limit 1;

\echo '=== N. CHAT dentro del ciclo'
select pg_temp.yo('00000000-0000-0000-0000-00000000000c');
insert into public.threads (listing_id, seller_id) values (pg_temp.p(15), '00000000-0000-0000-0000-00000000000a');
insert into public.messages (thread_id, text) select id, 'Hola, ¿sigue disponible?' from public.threads where listing_id = pg_temp.p(15) and buyer_id = auth.uid();
select 'N1 comprador escribe' paso, count(*) mensajes, 1 esperado from public.messages m join public.threads t on t.id = m.thread_id where t.listing_id = pg_temp.p(15);
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
insert into public.messages (thread_id, text) select id, 'Sí, está disponible' from public.threads where listing_id = pg_temp.p(15);
select 'N2 vendedor responde' paso, count(*) mensajes, 2 esperado from public.messages m join public.threads t on t.id = m.thread_id where t.listing_id = pg_temp.p(15);
\echo '--- N3 un tercero (admin sin permisos / otro usuario) no lee ni escribe (deben dar 0 / fallar)'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select 'N3 tercero ve' paso, count(*) mensajes, 0 esperado from public.messages m join public.threads t on t.id = m.thread_id where t.listing_id = pg_temp.p(15);
insert into public.messages (thread_id, text) select id, 'intruso' from public.threads where listing_id = pg_temp.p(15);
\echo '--- N4 el chat sigue funcionando cuando la prenda se reserva y se vende'
select pg_temp.yo('00000000-0000-0000-0000-00000000000c'); :liberar select pg_temp.compra(15);
insert into public.messages (thread_id, text) select id, '¿Cuándo la envías?' from public.threads where listing_id = pg_temp.p(15) and buyer_id = auth.uid();
select 'N5 mensajes tras reservar' paso, count(*) mensajes, 3 esperado from public.messages m join public.threads t on t.id = m.thread_id where t.listing_id = pg_temp.p(15);
\echo '--- N6 enviar mensaje vacío o enorme (deben fallar)'
insert into public.messages (thread_id, text) select id, '' from public.threads where listing_id = pg_temp.p(15) and buyer_id = auth.uid();
insert into public.messages (thread_id, text) select id, repeat('x',1001) from public.threads where listing_id = pg_temp.p(15) and buyer_id = auth.uid();

\echo '=== RESUMEN: ¿coincide lo real con lo esperado en todos los casos?'
select count(*) filter (where true) as revisados from public.listings;
