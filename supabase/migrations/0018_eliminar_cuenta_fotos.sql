-- 0018: arreglos encontrados en las pruebas del emulador.
-- 1. "Eliminar mi cuenta" fallaba para cualquiera que hubiera escrito un mensaje o tenido un
--    pedido (los pedidos y mensajes se guardan por ley y para resolver reclamos). Ahora:
--    se borran sus datos personales y anuncios sin historial; si queda historial, la cuenta
--    se anonimiza y se cierra para siempre en lugar de borrarse.
-- 2. Nadie podía listar todas las fotos del almacén (solo las suyas); las fotos públicas de los
--    anuncios se siguen viendo igual por su enlace.

create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'No autorizado';
  end if;
  if exists (select 1 from public.orders
             where (buyer_id = uid or seller_id = uid)
               and status not in ('liberado', 'cancelado')) then
    raise exception 'Tienes pedidos en curso. Termínalos antes de eliminar tu cuenta.';
  end if;
  perform set_config('lapercha.sistema', '1', true);

  -- Datos personales y actividad que no hace falta guardar.
  delete from public.private_profiles where id = uid;
  delete from public.favorites where user_id = uid;
  delete from public.follows where follower_id = uid or seller_id = uid;
  delete from public.avisos where user_id = uid;
  delete from public.listings l where l.seller_id = uid
    and not exists (select 1 from public.orders o where o.listing_id = l.id);
  update public.listings set status = 'hidden'
    where seller_id = uid and status in ('active', 'reserved');

  -- Sin historial: se borra todo.
  begin
    delete from auth.users where id = uid;
    perform set_config('lapercha.sistema', '', true);
    return;
  exception when foreign_key_violation then
    null;
  end;

  -- Con historial (pedidos o mensajes): se anonimiza y se cierra la cuenta.
  update public.profiles
    set username = 'eliminado_' || substr(md5(uid::text), 1, 10), city = 'Venezuela',
        blocked = true, vacation = true
    where id = uid;
  if exists (select 1 from information_schema.columns
             where table_schema = 'auth' and table_name = 'users' and column_name = 'banned_until') then
    execute 'update auth.users set email = $2, phone = null, banned_until = ''infinity'',
               raw_user_meta_data = ''{}''::jsonb where id = $1'
      using uid, 'eliminado+' || uid::text || '@pavito.invalid';
    execute 'delete from auth.identities where user_id = $1' using uid;
    execute 'delete from auth.sessions where user_id = $1' using uid;
  end if;
  perform set_config('lapercha.sistema', '', true);
end $$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- Fotos: cada quien solo ve el listado de su propia carpeta.
drop policy if exists photos_read on storage.objects;
create policy photos_read on storage.objects for select to authenticated
  using (bucket_id = 'listing-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- 3. El aviso de reembolso decía "a tu Pago Móvil" aunque se hubiera pagado con Binance o Zinli.
create or replace function public.avisos_pedido() returns trigger
language plpgsql security definer set search_path = public as $$
declare titulo text;
begin
  select title into titulo from public.listings where id = new.listing_id;
  titulo := '"' || coalesce(titulo, 'tu artículo') || '"';
  if tg_op = 'INSERT' then
    perform public.avisar(new.seller_id, '¡Alguien quiere ' || titulo || '! Esperando su pago.', 'pedido', new.id);
    return new;
  end if;
  if new.status is not distinct from old.status then return new; end if;
  case new.status
    when 'revision' then
      perform public.avisar(new.seller_id, 'El comprador pagó ' || titulo || '. Lo estamos verificando.', 'pedido', new.id);
    when 'retenido' then
      perform public.avisar(new.seller_id, 'Pago confirmado de ' || titulo || '. Ya puedes enviarlo.', 'pedido', new.id);
      perform public.avisar(new.buyer_id, 'Confirmamos tu pago de ' || titulo || '.', 'pedido', new.id);
    when 'enviado' then
      perform public.avisar(new.buyer_id, titulo || ' va en camino. Confirma cuando lo recibas.', 'pedido', new.id);
    when 'liberado' then
      perform public.avisar(new.seller_id, 'Venta completada: ' || titulo || '. ¡Deja tu reseña!', 'pedido', new.id);
      perform public.avisar(new.buyer_id, 'Pedido completado: ' || titulo || '. ¡Deja tu reseña!', 'pedido', new.id);
    when 'disputa' then
      perform public.avisar(new.seller_id, 'El comprador reportó un problema con ' || titulo || '.', 'pedido', new.id);
    when 'cancelado' then
      if old.status = 'retenido' and auth.uid() is null then
        perform public.avisar(new.seller_id, 'Se canceló la venta de ' || titulo || ' porque no se envió en 3 días.', 'pedido', new.id);
      else
        perform public.avisar(new.seller_id, 'Se canceló el pedido de ' || titulo || '.', 'pedido', new.id);
      end if;
      if new.paid_at is not null then
        perform public.avisar(new.buyer_id, 'Se canceló el pedido de ' || titulo
          || '. Te devolvemos lo que pagaste, por el mismo medio que usaste, en un máximo de 5 días hábiles.', 'pedido', new.id);
      else
        perform public.avisar(new.buyer_id, 'Se canceló el pedido de ' || titulo || '.', 'pedido', new.id);
      end if;
    else null;
  end case;
  return new;
end $$;
