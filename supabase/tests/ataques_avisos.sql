\set VERBOSITY terse
-- Ejecutar DESPUÉS de ataques_ofertas.sql (usa sus datos).
create function pg_temp.yo(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false); $$;
\echo '--- avisos generados'
select p.username, a.tipo, a.texto from public.avisos a join public.profiles p on p.id = a.user_id order by a.id;
set role authenticated;
\echo '--- el comprador solo ve los suyos; no puede crear ni editar el texto; marcar leído sí'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select count(*) as mis_avisos, count(*) filter (where user_id <> auth.uid()) as ajenos from public.avisos;
insert into public.avisos (user_id, texto, tipo) values (auth.uid(), 'falso', 'chat');
update public.avisos set texto = 'hackeado';
select public.avisar('00000000-0000-0000-0000-00000000000a', 'spam', 'chat', null);
update public.avisos set leido = true where user_id = auth.uid() returning id;
