-- La Percha: avisos dentro de la app (campanita). Los crea solo el servidor.
create table if not exists public.avisos (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  texto text not null,
  tipo text not null check (tipo in ('pedido','chat','perfil')),
  ref_id uuid,
  leido boolean not null default false,
  creado timestamptz not null default now()
);
create index if not exists avisos_user on public.avisos (user_id, creado desc);
alter table public.avisos enable row level security;
revoke all on public.avisos from anon, authenticated;
grant select on public.avisos to authenticated;
grant update (leido) on public.avisos to authenticated;
drop policy if exists avisos_own on public.avisos;
create policy avisos_own on public.avisos for select to authenticated using (user_id = auth.uid());
drop policy if exists avisos_marcar on public.avisos;
create policy avisos_marcar on public.avisos for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Crea un aviso; si ya hay uno sin leer del mismo chat, lo actualiza (no llena la lista).
create or replace function public.avisar(p_user uuid, p_texto text, p_tipo text, p_ref uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_user is null then return; end if;
  if p_tipo = 'chat' then
    update public.avisos set texto = p_texto, creado = now()
      where user_id = p_user and tipo = 'chat' and ref_id = p_ref and not leido;
    if found then return; end if;
  end if;
  insert into public.avisos (user_id, texto, tipo, ref_id) values (p_user, left(p_texto, 160), p_tipo, p_ref);
end $$;
revoke all on function public.avisar(uuid, text, text, uuid) from public, anon, authenticated;

-- Mensajes (incluye ofertas, que llegan como mensajes).
create or replace function public.avisos_mensaje() returns trigger
language plpgsql security definer set search_path = public as $$
declare t public.threads; quien text;
begin
  select * into t from public.threads where id = new.thread_id;
  select username into quien from public.profiles where id = new.sender_id;
  perform public.avisar(case when new.sender_id = t.buyer_id then t.seller_id else t.buyer_id end,
                        '@' || coalesce(quien, 'alguien') || ': ' || left(new.text, 100), 'chat', t.id);
  return new;
end $$;
drop trigger if exists avisos_mensaje on public.messages;
create trigger avisos_mensaje after insert on public.messages
  for each row execute function public.avisos_mensaje();

-- Pedidos: nuevo pedido y cada cambio de estado, a quien le toca actuar o saber.
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
      perform public.avisar(new.seller_id, 'Se canceló el pedido de ' || titulo || '.', 'pedido', new.id);
      perform public.avisar(new.buyer_id, 'Se canceló el pedido de ' || titulo || '.', 'pedido', new.id);
    else null;
  end case;
  return new;
end $$;
drop trigger if exists avisos_pedido on public.orders;
create trigger avisos_pedido after insert or update on public.orders
  for each row execute function public.avisos_pedido();

-- Reseñas recibidas.
create or replace function public.avisos_resena() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.avisar(new.target_id,
    'Recibiste una reseña de ' || new.stars || ' estrella' || case when new.stars = 1 then '' else 's' end || '.',
    'perfil', new.target_id);
  return new;
end $$;
drop trigger if exists avisos_resena on public.reviews;
create trigger avisos_resena after insert on public.reviews
  for each row execute function public.avisos_resena();

-- Limpieza: se borran los avisos leídos de más de 60 días (en el mantenimiento).
create or replace function public.orders_mantenimiento() returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.orders set status = 'cancelado'
    where status = 'esperando_pago' and created_at < now() - interval '24 hours';
  update public.orders set status = 'liberado'
    where status = 'enviado' and updated_at < now() - interval '7 days';
  update public.orders set delivery = null
    where delivery is not null and status in ('liberado','cancelado')
      and updated_at < now() - interval '30 days';
  update public.offers set status = 'vencida', responded_at = now()
    where (status = 'pendiente' and created_at < now() - interval '48 hours')
       or (status = 'aceptada' and responded_at < now() - interval '48 hours');
  delete from public.avisos where leido and creado < now() - interval '60 days';
end $$;
revoke all on function public.orders_mantenimiento() from public, anon, authenticated;
