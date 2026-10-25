-- La Percha: endurecimiento de seguridad (ejecutar DESPUÉS de 0001_init.sql).
-- Añade: usuarios bloqueados, límite de abusos, fotos solo propias,
-- historial de pedidos y borrado de cuenta.

-- ============ Usuarios bloqueados ============
create or replace function public.is_blocked() returns boolean
language sql security definer stable set search_path = public as $$
  select coalesce((select blocked from public.profiles where id = auth.uid()), false)
$$;

-- Políticas "restrictivas": se suman a las demás y las anulan si el usuario está bloqueado.
create policy no_blocked_ins on public.listings as restrictive for insert to authenticated
  with check (not public.is_blocked());
create policy no_blocked_upd on public.listings as restrictive for update to authenticated
  using (not public.is_blocked()) with check (not public.is_blocked());
create policy no_blocked_ins on public.threads as restrictive for insert to authenticated
  with check (not public.is_blocked());
create policy no_blocked_ins on public.messages as restrictive for insert to authenticated
  with check (not public.is_blocked());
create policy no_blocked_ins on public.orders as restrictive for insert to authenticated
  with check (not public.is_blocked());
create policy no_blocked_upd on public.orders as restrictive for update to authenticated
  using (not public.is_blocked()) with check (not public.is_blocked());
create policy no_blocked_ins on public.reports as restrictive for insert to authenticated
  with check (not public.is_blocked());

-- ============ Límite de acciones (contra spam y abuso) ============
alter table public.threads add column if not exists created_at timestamptz not null default now();

create or replace function public.rate_limit() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  col text := tg_argv[0];
  max_n int := tg_argv[1]::int;
  secs int := tg_argv[2]::int;
  n int;
begin
  execute format(
    'select count(*) from %I.%I where %I = $1 and created_at > now() - make_interval(secs => $2)',
    tg_table_schema, tg_table_name, col)
  into n using auth.uid(), secs;
  if n >= max_n then
    raise exception 'Demasiadas acciones seguidas. Espera un momento e intenta de nuevo.';
  end if;
  return new;
end $$;

create trigger listings_rate before insert on public.listings
  for each row execute function public.rate_limit('seller_id', '30', '86400');   -- 30 anuncios al día
create trigger threads_rate before insert on public.threads
  for each row execute function public.rate_limit('buyer_id', '30', '3600');      -- 30 chats nuevos por hora
create trigger messages_rate before insert on public.messages
  for each row execute function public.rate_limit('sender_id', '20', '60');       -- 20 mensajes por minuto
create trigger orders_rate before insert on public.orders
  for each row execute function public.rate_limit('buyer_id', '10', '3600');      -- 10 pedidos por hora
create trigger reports_rate before insert on public.reports
  for each row execute function public.rate_limit('reporter_id', '10', '3600');   -- 10 denuncias por hora

-- ============ Datos válidos ============
-- Nombre de usuario: solo letras, números, punto y guion bajo (evita suplantaciones raras).
alter table public.profiles add constraint username_format
  check (username ~ '^[A-Za-z0-9_.]+$') not valid;

-- Las fotos de un anuncio solo pueden venir de la carpeta del propio vendedor
-- (evita enlaces externos maliciosos o rastreadores).
create or replace function public.listings_check_photos() returns trigger
language plpgsql set search_path = public as $$
declare p text;
begin
  foreach p in array new.photos loop
    if p not like ('https://%/storage/v1/object/public/listing-photos/' || new.seller_id::text || '/%') then
      raise exception 'Foto no válida';
    end if;
  end loop;
  return new;
end $$;
create trigger listings_photos before insert or update of photos on public.listings
  for each row execute function public.listings_check_photos();

-- ============ Historial de pedidos (para resolver disputas) ============
create table public.order_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  actor uuid,
  from_status text,
  to_status text not null,
  at timestamptz not null default now()
);
alter table public.order_events enable row level security;
revoke all on public.order_events from anon, authenticated;
grant select on public.order_events to authenticated;
create policy events_read on public.order_events for select to authenticated
  using (public.is_admin() or exists (select 1 from public.orders o
    where o.id = order_id and auth.uid() in (o.buyer_id, o.seller_id)));

create or replace function public.orders_log() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    insert into public.order_events (order_id, actor, from_status, to_status)
    values (new.id, auth.uid(), old.status, new.status);
  end if;
  return new;
end $$;
create trigger orders_log after update on public.orders
  for each row execute function public.orders_log();

-- ============ Borrar mi cuenta ============
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then
    raise exception 'No autorizado';
  end if;
  if exists (select 1 from public.orders
             where (buyer_id = auth.uid() or seller_id = auth.uid())
               and status not in ('liberado', 'cancelado')) then
    raise exception 'Tienes pedidos en curso';
  end if;
  delete from auth.users where id = auth.uid();
end $$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
