\set VERBOSITY terse
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),('00000000-0000-0000-0000-00000000000d');
insert into public.profiles (id, username, city, is_admin) values
 ('00000000-0000-0000-0000-00000000000a','vende','Caracas',false),('00000000-0000-0000-0000-00000000000b','compra','Caracas',false),
 ('00000000-0000-0000-0000-00000000000d','jefe','Caracas',true);
create function pg_temp.yo(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false); $$;
set role authenticated;
\echo '--- alerta de la compradora y anuncio que coincide'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
insert into public.alertas_busqueda (q, talla) values ('zara', 'M');
insert into public.alertas_busqueda (q) values ('');
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
insert into public.listings (title, price, category, size, condition, city, photos, brand) values ('Blusa blanca',12,'Mujer','M','Como nuevo','Caracas','{}','Zara');
insert into public.listings (title, price, category, size, condition, city, photos, brand) values ('Blusa roja',12,'Mujer','L','Como nuevo','Caracas','{}','Zara');
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select texto, tipo from public.avisos;
\echo '--- editar: dueña sí (precio y marca), otra no; no puede tocar orden ni bumped_at'
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
update public.listings set price = 10, brand = 'Zara Basic' where title = 'Blusa blanca';
update public.listings set bumped_at = now() + interval '1 year' where title = 'Blusa blanca';
update public.listings set orden = now() + interval '1 year' where title = 'Blusa blanca';
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
update public.listings set price = 1 where title = 'Blusa blanca';
select title, price, brand from public.listings where title = 'Blusa blanca';
\echo '--- subir: recién publicado no se puede; con 8 días sí, y queda primero'
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select public.subir_anuncio((select id from public.listings where title='Blusa roja'));
select pg_temp.yo(''); reset role;
update public.listings set created_at = now() - interval '8 days', orden = now() - interval '8 days' where title='Blusa roja';
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select public.subir_anuncio((select id from public.listings where title='Blusa roja')) is not null as subido;
select title from public.buscar_anuncios('blusa') limit 1;
select public.subir_anuncio((select id from public.listings where title='Blusa roja'));
\echo '--- vistas: dueña no cuenta, compradora una por día, anónimo por dispositivo'
select public.registrar_vista((select id from public.listings where title='Blusa blanca'));
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select public.registrar_vista((select id from public.listings where title='Blusa blanca'));
select public.registrar_vista((select id from public.listings where title='Blusa blanca'));
insert into public.favorites (listing_id) values ((select id from public.listings where title='Blusa blanca'));
select pg_temp.yo(''); set role anon;
select public.registrar_vista((select id from public.listings where title='Blusa blanca'), 'abc-123');
select public.registrar_vista((select id from public.listings where title='Blusa blanca'), '');
set role authenticated; select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select l.title, e.vistas, e.favoritos from public.mis_estadisticas() e join public.listings l on l.id = e.listing_id order by 1;
\echo '--- verificado: solo admin'
update public.profiles set verificado = true where id = auth.uid();
select public.admin_set_verificado(auth.uid(), true);
select pg_temp.yo('00000000-0000-0000-0000-00000000000d');
select public.admin_set_verificado('00000000-0000-0000-0000-00000000000a', true);
select username, verificado from public.profiles where verificado;
\echo '--- invitación: compradora fue invitada por vende; al publicar su primera prenda, vende gana 1 destacado'
select pg_temp.yo('00000000-0000-0000-0000-00000000000b');
select public.usar_invitacion('compra');
select public.usar_invitacion('vende');
select public.usar_invitacion('jefe');
insert into public.listings (title, price, category, size, condition, city, photos) values ('Libro',5,'Libros y juegos','No aplica','Buen estado','Caracas','{}');
insert into public.listings (title, price, category, size, condition, city, photos) values ('Libro 2',5,'Libros y juegos','No aplica','Buen estado','Caracas','{}');
select pg_temp.yo('00000000-0000-0000-0000-00000000000a');
select destacados_gratis as vende_destacados_4 from public.profiles where id = auth.uid();
select public.mis_invitados() as invitados;
