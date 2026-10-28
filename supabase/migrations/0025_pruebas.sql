-- 0025: pruebas de los pedidos (fotos y videos).
--  * El vendedor puede subir foto/video del paquete al enviarlo (opcional).
--  * El comprador DEBE subir al menos una foto para abrir un reclamo.
--  * El vendedor DEBE subir al menos una foto si la devolución "llegó con problemas".
-- Las pruebas son privadas: solo las ven comprador, vendedor y admin.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pruebas', 'pruebas', false, 31457280,
        array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime','video/webm'])
on conflict (id) do nothing;

create table if not exists public.pruebas (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  autor uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  tipo text not null check (tipo in ('envio','reclamo','devolucion')),
  path text not null unique check (char_length(path) between 10 and 200),
  es_video boolean not null default false,
  creado timestamptz not null default now()
);
create index if not exists pruebas_order on public.pruebas (order_id, creado);
alter table public.pruebas enable row level security;

create or replace function public.lp_parte_pedido(p_order uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.orders o where o.id = p_order
                 and (o.buyer_id = auth.uid() or o.seller_id = auth.uid()))
$$;
revoke all on function public.lp_parte_pedido(uuid) from public, anon;
grant execute on function public.lp_parte_pedido(uuid) to authenticated;

drop policy if exists pruebas_ver on public.pruebas;
create policy pruebas_ver on public.pruebas for select to authenticated
  using (public.lp_parte_pedido(order_id) or public.is_admin());

-- Subir: cada parte solo en su momento.
drop policy if exists pruebas_subir on public.pruebas;
create policy pruebas_subir on public.pruebas for insert to authenticated
  with check (
    autor = auth.uid()
    and path like order_id::text || '/' || auth.uid()::text || '/%'
    and exists (select 1 from public.orders o where o.id = order_id and (
         (tipo = 'envio'      and o.seller_id = auth.uid() and o.status in ('retenido','enviado'))
      or (tipo = 'reclamo'    and o.buyer_id  = auth.uid() and o.status in ('enviado','disputa'))
      or (tipo = 'devolucion' and o.seller_id = auth.uid() and o.status in ('devolucion','disputa'))
    ))
  );
grant select, insert on public.pruebas to authenticated;

-- Máximo 8 pruebas por persona y pedido.
create or replace function public.pruebas_limite() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.pruebas where order_id = new.order_id and autor = new.autor) >= 8 then
    raise exception 'Máximo 8 fotos o videos por pedido';
  end if;
  return new;
end $$;
drop trigger if exists pruebas_limite on public.pruebas;
create trigger pruebas_limite before insert on public.pruebas
  for each row execute function public.pruebas_limite();

-- Archivos: carpeta <pedido>/<persona>/..., solo las partes del pedido (y el admin para ver).
drop policy if exists pruebas_arch_subir on storage.objects;
create policy pruebas_arch_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'pruebas'
    and (storage.foldername(name))[2] = auth.uid()::text
    and public.lp_parte_pedido(((storage.foldername(name))[1])::uuid));
drop policy if exists pruebas_arch_ver on storage.objects;
create policy pruebas_arch_ver on storage.objects for select to authenticated
  using (bucket_id = 'pruebas'
    and (public.is_admin() or public.lp_parte_pedido(((storage.foldername(name))[1])::uuid)));

-- Sin fotos no hay reclamo (salvo admin o procesos automáticos).
create or replace function public.orders_zpruebas() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'disputa' and old.status is distinct from 'disputa'
     and auth.uid() is not null and not public.is_admin() and not public.lp_sistema()
     and not exists (select 1 from public.pruebas p where p.order_id = new.id
                     and p.autor = auth.uid() and p.tipo in ('reclamo','devolucion')) then
    raise exception 'Sube al menos una foto para abrir el reclamo';
  end if;
  return new;
end $$;
drop trigger if exists orders_zpruebas on public.orders;
create trigger orders_zpruebas before update on public.orders
  for each row execute function public.orders_zpruebas();
