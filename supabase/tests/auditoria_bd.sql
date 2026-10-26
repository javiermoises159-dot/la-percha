\set VERBOSITY terse
-- Revisión automática: debe salir todo vacío (0 filas) salvo lo que se explica.
\echo '--- tablas de public sin RLS (debe ser 0)'
select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity order by 1;
\echo '--- funciones SECURITY DEFINER sin search_path fijo (debe ser 0)'
select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname in ('public','interno') and p.prosecdef
   and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) x where x like 'search_path=%') order by 1;
\echo '--- funciones SECURITY DEFINER que puede ejecutar alguien sin cuenta (anon)'
select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prosecdef and has_function_privilege('anon', p.oid, 'execute') order by 1;
\echo '--- tablas donde anon puede escribir (debe ser 0)'
select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r'
   and (has_table_privilege('anon', c.oid, 'insert') or has_table_privilege('anon', c.oid, 'update')
        or has_table_privilege('anon', c.oid, 'delete')) order by 1;
\echo '--- columnas sensibles legibles por usuarios (debe ser 0)'
select table_name, column_name from information_schema.column_privileges
 where grantee in ('anon','authenticated') and privilege_type = 'SELECT'
   and column_name in ('payout_cifrado','is_admin_secret') order by 1;
\echo '--- esquema interno accesible para usuarios (debe ser f, f)'
select has_schema_privilege('anon','interno','usage') anon, has_schema_privilege('authenticated','interno','usage') auth;
