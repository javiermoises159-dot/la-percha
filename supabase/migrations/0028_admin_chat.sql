-- 0028: el administrador puede leer el chat entre dos personas SOLO cuando hay
-- una disputa/devolución abierta entre ellas o una denuncia abierta, como dicen los términos.
-- Cada lectura queda registrada.

create table if not exists interno.accesos_chat (
  id bigint generated always as identity primary key,
  admin_id uuid not null,
  order_id uuid,
  report_id uuid,
  usuario_a uuid not null,
  usuario_b uuid not null,
  creado timestamptz not null default now()
);
revoke all on interno.accesos_chat from public, anon, authenticated;

create or replace function public.admin_chat(p_order uuid default null, p_report uuid default null)
returns table (enviado timestamptz, autor text, es_a boolean, prenda text, texto text)
language plpgsql security definer set search_path = public, interno as $$
declare a uuid; b uuid;
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  if (p_order is null) = (p_report is null) then raise exception 'Indica un pedido o una denuncia'; end if;

  if p_order is not null then
    select o.buyer_id, o.seller_id into a, b from public.orders o
     where o.id = p_order and o.status in ('disputa', 'devolucion');
    if a is null then raise exception 'Solo se puede ver el chat de pedidos con un problema abierto'; end if;
  else
    select r.reporter_id, coalesce(r.user_id, l.seller_id) into a, b
      from public.reports r left join public.listings l on l.id = r.listing_id
     where r.id = p_report and r.status = 'abierta';
    if a is null or b is null then raise exception 'Solo se puede ver el chat de denuncias abiertas'; end if;
  end if;

  insert into interno.accesos_chat (admin_id, order_id, report_id, usuario_a, usuario_b)
  values (auth.uid(), p_order, p_report, a, b);

  return query
    select m.created_at, p.username, m.sender_id = a, l.title, m.text
      from public.threads t
      join public.messages m on m.thread_id = t.id
      join public.profiles p on p.id = m.sender_id
      left join public.listings l on l.id = t.listing_id
     where (t.buyer_id = a and t.seller_id = b) or (t.buyer_id = b and t.seller_id = a)
     order by m.created_at
     limit 500;
end $$;
revoke all on function public.admin_chat(uuid, uuid) from public, anon;
grant execute on function public.admin_chat(uuid, uuid) to authenticated;

-- Registro de quién miró qué chat (para el panel).
create or replace function public.admin_accesos_chat()
returns table (creado timestamptz, admin text, motivo text, entre text)
language sql security definer stable set search_path = public, interno as $$
  select x.creado, pa.username,
         case when x.order_id is not null then 'Pedido con problema' else 'Denuncia' end,
         '@' || p1.username || ' y @' || p2.username
    from interno.accesos_chat x
    left join public.profiles pa on pa.id = x.admin_id
    left join public.profiles p1 on p1.id = x.usuario_a
    left join public.profiles p2 on p2.id = x.usuario_b
   where public.is_admin()
   order by x.creado desc limit 100
$$;
revoke all on function public.admin_accesos_chat() from public, anon;
grant execute on function public.admin_accesos_chat() to authenticated;
