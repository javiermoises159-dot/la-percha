-- 0044: más avisos.
--  1. Al publicarse una prenda: aviso a los administradores y a quienes siguen al vendedor.
--  2. Los avisos de pedidos (pedido, pago, envío, entrega, cancelación...) también salen por correo.

-- 1) Prenda nueva: administradores y seguidores (máx. 500 seguidores por prenda).
create or replace function public.avisar_publicacion() returns trigger
language plpgsql security definer set search_path = public as $$
declare usuario text; f record; adm record;
begin
  if new.status <> 'active' then return new; end if;
  select username into usuario from public.profiles where id = new.seller_id;
  for adm in select id from public.profiles where is_admin and id <> new.seller_id loop
    perform public.avisar(adm.id, '🧥 Nueva prenda de @' || coalesce(usuario, '?') || ': ' || left(new.title, 50)
      || ' · $' || to_char(new.price, 'FM999990.00'), 'anuncio', new.id);
  end loop;
  for f in
    select fo.follower_id from public.follows fo
    where fo.seller_id = new.seller_id
      and not exists (select 1 from public.profiles p where p.id = fo.follower_id and p.is_admin)
    limit 500
  loop
    perform public.avisar(f.follower_id, '@' || coalesce(usuario, '?') || ' publicó: ' || left(new.title, 50)
      || ' · $' || to_char(new.price, 'FM999990.00'), 'anuncio', new.id);
  end loop;
  return new;
exception when others then
  return new; -- avisar nunca debe impedir publicar
end $$;
revoke all on function public.avisar_publicacion() from public, anon, authenticated;
drop trigger if exists listings_avisar_publicacion on public.listings;
create trigger listings_avisar_publicacion after insert on public.listings
  for each row execute function public.avisar_publicacion();

-- 2) Correo: cada aviso de pedido llama a la función "correo" (misma clave interna que "push").
create or replace function public.avisos_correo() returns trigger
language plpgsql security definer set search_path = public as $$
declare clave text;
begin
  if new.tipo <> 'pedido' then return new; end if;
  if to_regproc('net.http_post') is null then return new; end if;
  select valor into clave from public.secretos where secretos.clave = 'push';
  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
    using 'https://udhyuyokrxggdnnepbmr.supabase.co/functions/v1/correo',
          jsonb_build_object('aviso', new.id),
          jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', coalesce(clave, ''));
  return new;
exception when others then
  return new; -- un fallo al mandar el correo nunca debe frenar la app
end $$;
revoke all on function public.avisos_correo() from public, anon, authenticated;
drop trigger if exists avisos_correo on public.avisos;
create trigger avisos_correo after insert on public.avisos
  for each row execute function public.avisos_correo();
