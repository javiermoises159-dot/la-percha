-- 0025: modo directo (lanzamiento). El comprador le paga al vendedor por fuera de la app,
-- así que el vendedor necesita poder marcar su anuncio como vendido.
create or replace function public.marcar_vendido(p_listing uuid) returns void
language plpgsql security definer set search_path = public as $$
declare st text; dueno uuid;
begin
  if auth.uid() is null then raise exception 'Inicia sesión'; end if;
  select status, seller_id into st, dueno from public.listings where id = p_listing for update;
  if dueno is null or dueno <> auth.uid() then raise exception 'Este anuncio no es tuyo'; end if;
  if st not in ('active','hidden') then raise exception 'Este anuncio ya no se puede marcar'; end if;
  if exists (select 1 from public.orders where listing_id = p_listing
             and status not in ('liberado','cancelado')) then
    raise exception 'Este anuncio tiene un pedido abierto';
  end if;
  perform set_config('lapercha.sistema', '1', true);
  update public.listings set status = 'sold' where id = p_listing;
  perform set_config('lapercha.sistema', '', true);
end $$;
revoke all on function public.marcar_vendido(uuid) from public, anon;
grant execute on function public.marcar_vendido(uuid) to authenticated;
