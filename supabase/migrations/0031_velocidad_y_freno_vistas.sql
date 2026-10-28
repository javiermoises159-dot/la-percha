-- Velocidad: índices que faltaban en las búsquedas más comunes (lista de chats, tienda de un
-- vendedor, favoritos, seguidores, ofertas, historial de pedidos y cobros).
create index if not exists threads_comprador on public.threads (buyer_id);
create index if not exists threads_vendedor  on public.threads (seller_id);
create index if not exists listings_vendedor on public.listings (seller_id, created_at desc);
create index if not exists favorites_anuncio on public.favorites (listing_id);
create index if not exists follows_vendedor  on public.follows (seller_id);
create index if not exists offers_comprador  on public.offers (buyer_id);
create index if not exists offers_vendedor   on public.offers (seller_id);
create index if not exists order_events_pedido on public.order_events (order_id);
create index if not exists promotions_anuncio on public.promotions (listing_id);
create index if not exists promotions_vendedor on public.promotions (seller_id);
create index if not exists retiros_usuario   on public.retiros (user_id, creado desc);
create index if not exists messages_remitente on public.messages (sender_id);
create index if not exists reviews_autor     on public.reviews (author_id);
create index if not exists reports_anuncio   on public.reports (listing_id);
create index if not exists reports_usuario   on public.reports (user_id);
create index if not exists vistas_anuncio_dia on public.vistas (listing_id, dia);

-- Seguridad: un freno al contador de vistas (quien rote identificadores no puede inflarlo
-- ni llenar la tabla): como mucho 5.000 vistas nuevas por anuncio y por día.
create or replace function public.registrar_vista(p_listing uuid, p_dispositivo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare quien text := coalesce(auth.uid()::text, 'd:' || left(regexp_replace(coalesce(p_dispositivo, ''), '[^A-Za-z0-9-]', '', 'g'), 40));
begin
  if quien = 'd:' then return; end if;
  if exists (select 1 from public.listings where id = p_listing and seller_id = auth.uid()) then return; end if;
  if (select count(*) from public.vistas
      where listing_id = p_listing and dia = (now() at time zone 'America/Caracas')::date) >= 5000 then
    return;
  end if;
  insert into public.vistas (listing_id, quien) values (p_listing, quien) on conflict do nothing;
exception when foreign_key_violation then null;
end $$;
