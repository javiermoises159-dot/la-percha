\set VERBOSITY terse
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b');
insert into public.profiles (id, username, city) values ('00000000-0000-0000-0000-00000000000a','ana','Caracas'),('00000000-0000-0000-0000-00000000000b','luis','Caracas');
create function pg_temp.yo(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false); $$;
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
\echo '--- guardar dispositivo; leerlo de otro no se puede; insert directo no se puede'
select public.guardar_push('https://fcm.googleapis.com/fcm/send/abc', 'p256', 'authx');
insert into public.push_subs (user_id, endpoint, p256dh, auth) values (auth.uid(), 'https://x', 'a', 'b');
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select count(*) as ajenos from public.push_subs;
\echo '--- mismo dispositivo con otra cuenta: pasa a la nueva'
select public.guardar_push('https://fcm.googleapis.com/fcm/send/abc', 'p256', 'authx');
select pg_temp.yo(''); reset role;
select p.username from public.push_subs s join public.profiles p on p.id = s.user_id;
\echo '--- push_tomar: solo una vez por texto; cambia el texto (chat) y se puede otra vez; nadie más puede llamarla'
select public.avisar('00000000-0000-0000-0000-00000000000b', 'Hola 1', 'chat', '11111111-1111-1111-1111-111111111111');
select texto from public.push_tomar((select id from public.avisos limit 1));
select count(*) as segunda_vez from public.push_tomar((select id from public.avisos limit 1));
select public.avisar('00000000-0000-0000-0000-00000000000b', 'Hola 2', 'chat', '11111111-1111-1111-1111-111111111111');
select texto from public.push_tomar((select id from public.avisos limit 1));
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select * from public.push_tomar(1);
