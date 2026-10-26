\set VERBOSITY terse
insert into auth.users values ('00000000-0000-0000-0000-00000000000a');
insert into public.profiles (id, username, city) values ('00000000-0000-0000-0000-00000000000a','vende','Caracas');
create function pg_temp.yo(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false); $$;
set role anon;
\echo '--- anónimo no puede escanear'
select public.ai_scan_permitido();
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
\echo '--- 20 escaneos permitidos, el 21 no (-1); no puede borrar su registro'
select min(q), max(q) from (select public.ai_scan_permitido() q from generate_series(1,20)) s;
select public.ai_scan_permitido() as el_21;
delete from public.ai_scans;
\echo '--- portada IA con una sola foto (falla); con 2 (ok)'
insert into public.listings (title, price, category, size, condition, city, photos, foto_ia) values ('Camisa',5,'Hombre','M','Buen estado','Caracas',
 array['https://udhyuyokrxggdnnepbmr.supabase.co/storage/v1/object/public/listing-photos/00000000-0000-0000-0000-00000000000a/1.png'], true);
insert into public.listings (title, price, category, size, condition, city, photos, foto_ia) values ('Camisa',5,'Hombre','M','Buen estado','Caracas',
 array['https://udhyuyokrxggdnnepbmr.supabase.co/storage/v1/object/public/listing-photos/00000000-0000-0000-0000-00000000000a/1.png',
       'https://udhyuyokrxggdnnepbmr.supabase.co/storage/v1/object/public/listing-photos/00000000-0000-0000-0000-00000000000a/2.jpg'], true) returning 'ok';
