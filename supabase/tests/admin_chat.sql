\set VERBOSITY terse
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),('00000000-0000-0000-0000-00000000000c'),('00000000-0000-0000-0000-00000000000d');
insert into public.profiles (id, username, city, is_admin) values ('00000000-0000-0000-0000-00000000000a','vende','Caracas',false),
 ('00000000-0000-0000-0000-00000000000b','compra','Caracas',false),('00000000-0000-0000-0000-00000000000c','intruso','Caracas',false),('00000000-0000-0000-0000-00000000000d','jefe','Caracas',true);
insert into public.listings (id, seller_id, title, price, category, size, condition, city) values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-00000000000a','Chaqueta',20,'Hombre','L','Buen estado','Caracas');
create function pg_temp.yo(u text, aal text default 'aal1') returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000' || u, false), set_config('request.jwt.claim.aal', aal, false); $$;
select pg_temp.yo('b');
insert into public.threads (id, listing_id, buyer_id, seller_id) values ('22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000000a');
insert into public.messages (thread_id, sender_id, text) values ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-00000000000b','¿Tiene manchas?');
select pg_temp.yo('a');
insert into public.messages (thread_id, sender_id, text) values ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-00000000000a','No, está perfecta');
select pg_temp.yo('b');
insert into public.orders (id, listing_id, buyer_id, seller_id, price, fee, status) values ('33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000000a',20,1.25,'enviado');
insert into public.reports (id, reporter_id, user_id, reason) values ('44444444-4444-4444-4444-444444444444','00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000000a','Me quiso cobrar por fuera');
set role authenticated;
\echo '--- usuario normal no puede (error)'
select pg_temp.yo('c'); select * from public.admin_chat('33333333-3333-3333-3333-333333333333');
\echo '--- admin sin 2FA no puede (error)'
select pg_temp.yo('d'); select * from public.admin_chat('33333333-3333-3333-3333-333333333333');
\echo '--- admin con 2FA: pedido sin problema no (error)'
select pg_temp.yo('d','aal2'); select * from public.admin_chat('33333333-3333-3333-3333-333333333333');
\echo '--- denuncia abierta: sí, 2 mensajes'
select autor, texto from public.admin_chat(null, '44444444-4444-4444-4444-444444444444');
reset role; update public.orders set status = 'disputa'; update public.reports set status = 'revisada'; set role authenticated;
\echo '--- pedido en disputa: sí, 2 mensajes'
select autor, es_a, texto from public.admin_chat('33333333-3333-3333-3333-333333333333');
\echo '--- denuncia ya revisada: no (error)'
select * from public.admin_chat(null, '44444444-4444-4444-4444-444444444444');
\echo '--- registro: 2 accesos'
select motivo, entre from public.admin_accesos_chat();
\echo '--- nadie puede leer el registro directo (error)'
select count(*) from interno.accesos_chat;
