\set VERBOSITY terse
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000d'),('00000000-0000-0000-0000-00000000000e');
insert into public.profiles (id, username, city, is_admin) values ('00000000-0000-0000-0000-00000000000d','jefe','Caracas',true);
\echo '--- registro nuevo: el admin recibe 1 aviso tipo registro'
insert into public.profiles (id, username, city) values ('00000000-0000-0000-0000-00000000000a','nueva.vendedora','Maracaibo');
select tipo, texto from public.avisos;
create function pg_temp.yo(u text, aal text default 'aal1') returns void language sql as $$
  select set_config('request.jwt.claim.sub', case when u = '' then '' else '00000000-0000-0000-0000-00000000000' || u end, false), set_config('request.jwt.claim.aal', aal, false); $$;
set role anon;
\echo '--- visitas anónimas'
select pg_temp.yo(''); select public.registrar_visita('abcdef1234', null, 'instagram', 'app', 'web');
select public.registrar_visita('abcdef1234', null, 'instagram', 'app', 'web');
select public.registrar_visita('zzzz99998888', 'a1b2c3d4e5f60718', 'whatsapp', 'anuncio', 'web');
select public.registrar_visita('bad id!!', null, 'x', 'app', 'web');
select public.registrar_visita('qqqqwwww1', null, '<script>', 'app', 'web');
\echo '--- anon no puede leer visitas (error)'
select count(*) from interno.visitas;
reset role; set role authenticated;
\echo '--- la vendedora entra con la misma sesión: se asocia'
select pg_temp.yo('a'); select public.registrar_visita('abcdef1234', null, 'instagram', 'app', 'web');
\echo '--- usuario normal no ve el resumen (error)'
select public.admin_visitas(7);
\echo '--- admin con 2FA: hoy 2 visitas, 2 registros, origenes instagram 1 / whatsapp 1, nueva con origen instagram'
select pg_temp.yo('d','aal2');
select r->'hoy' as hoy, r->'origenes' as origenes, r->'nuevos'->0->>'origen' as origen_nueva, jsonb_array_length(r->'dias') as dias from public.admin_visitas(7) r;
