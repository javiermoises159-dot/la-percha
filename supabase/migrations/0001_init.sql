-- La Percha: base de datos y seguridad (Supabase / PostgreSQL).
-- Regla de oro: cada tabla tiene "Row Level Security" activado, es decir,
-- el servidor decide fila por fila quién puede ver o cambiar qué.
-- Se pega completo en Supabase > SQL Editor > Run.

-- ============ Perfiles ============
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null check (char_length(username) between 3 and 20),
  city text not null check (char_length(city) between 2 and 40),
  rating_avg numeric(3,2) not null default 0,
  rating_count int not null default 0,
  is_admin boolean not null default false,
  blocked boolean not null default false,
  created_at timestamptz not null default now()
);

-- ============ Ayudas ============
create or replace function public.is_admin() returns boolean
language sql security definer stable set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
$$;

-- Datos privados: teléfono, cuenta de cobro, dirección de entrega.
create table public.private_profiles (
  id uuid primary key references public.profiles(id) on delete cascade,
  phone text,
  payout jsonb,
  address jsonb
);

-- ============ Anuncios ============
create table public.listings (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 3 and 60),
  description text not null default '' check (char_length(description) <= 500),
  price numeric(8,2) not null check (price > 0 and price <= 5000),
  category text not null,
  size text not null,
  condition text not null,
  city text not null,
  photos text[] not null default '{}' check (cardinality(photos) <= 8),
  status text not null default 'active' check (status in ('active','reserved','sold','hidden')),
  created_at timestamptz not null default now()
);
create index on public.listings (status, created_at desc);

-- ============ Conversaciones ============
create table public.threads (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  buyer_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  offer jsonb,
  last_message text,
  last_at timestamptz,
  unique (listing_id, buyer_id),
  check (buyer_id <> seller_id)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.threads(id) on delete cascade,
  sender_id uuid not null default auth.uid() references public.profiles(id),
  text text not null check (char_length(text) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index on public.messages (thread_id, created_at);

-- ============ Pedidos (compra protegida) ============
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id),
  buyer_id uuid not null default auth.uid() references public.profiles(id),
  seller_id uuid not null references public.profiles(id),
  price numeric(8,2) not null check (price > 0),
  fee numeric(8,2) not null,
  status text not null default 'esperando_pago' check (status in
    ('esperando_pago','revision','retenido','enviado','liberado','disputa','cancelado')),
  pay_ref text,
  tracking text,
  delivery jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.orders (buyer_id);
create index on public.orders (seller_id);

-- ============ Favoritos y denuncias ============
create table public.favorites (
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  listing_id uuid not null references public.listings(id) on delete cascade,
  primary key (user_id, listing_id)
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null default auth.uid() references public.profiles(id),
  listing_id uuid references public.listings(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  reason text not null check (char_length(reason) between 3 and 500),
  created_at timestamptz not null default now()
);

-- ============ Permisos: todo cerrado, se abre lo mínimo ============
revoke all on all tables in schema public from anon, authenticated;

grant select on public.profiles, public.listings to anon, authenticated;
grant insert (id, username, city) on public.profiles to authenticated;
grant update (username, city) on public.profiles to authenticated;

grant select, insert, update on public.private_profiles to authenticated;

grant insert (title, description, price, category, size, condition, city, photos)
  on public.listings to authenticated;
grant update (title, description, price, category, size, condition, city, photos, status)
  on public.listings to authenticated;
grant delete on public.listings to authenticated;

grant select on public.threads to authenticated;
grant insert (listing_id, seller_id) on public.threads to authenticated;
grant update (offer, last_message, last_at) on public.threads to authenticated;

grant select on public.messages to authenticated;
grant insert (thread_id, text) on public.messages to authenticated;

grant select on public.orders to authenticated;
grant insert (listing_id, price, delivery) on public.orders to authenticated;
grant update (status, pay_ref, tracking, delivery) on public.orders to authenticated;

grant select, insert, delete on public.favorites to authenticated;
grant insert (listing_id, user_id, reason) on public.reports to authenticated;
grant select on public.reports to authenticated;

-- ============ Reglas fila por fila ============
alter table public.profiles enable row level security;
alter table public.private_profiles enable row level security;
alter table public.listings enable row level security;
alter table public.threads enable row level security;
alter table public.messages enable row level security;
alter table public.orders enable row level security;
alter table public.favorites enable row level security;
alter table public.reports enable row level security;

create policy profiles_read on public.profiles for select using (true);
create policy profiles_insert on public.profiles for insert to authenticated
  with check (id = auth.uid());
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy private_all on public.private_profiles for all to authenticated
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

create policy listings_read on public.listings for select
  using (status in ('active','reserved','sold') or seller_id = auth.uid() or public.is_admin());
create policy listings_insert on public.listings for insert to authenticated
  with check (seller_id = auth.uid());
create policy listings_update on public.listings for update to authenticated
  using (seller_id = auth.uid() or public.is_admin())
  with check ((seller_id = auth.uid() and status in ('active','hidden')) or public.is_admin());
create policy listings_delete on public.listings for delete to authenticated
  using (seller_id = auth.uid() or public.is_admin());

create policy threads_read on public.threads for select to authenticated
  using (auth.uid() in (buyer_id, seller_id));
create policy threads_insert on public.threads for insert to authenticated
  with check (buyer_id = auth.uid()
    and seller_id = (select l.seller_id from public.listings l where l.id = listing_id));
create policy threads_update on public.threads for update to authenticated
  using (auth.uid() in (buyer_id, seller_id))
  with check (auth.uid() in (buyer_id, seller_id));

create policy messages_read on public.messages for select to authenticated
  using (exists (select 1 from public.threads t
    where t.id = thread_id and auth.uid() in (t.buyer_id, t.seller_id)));
create policy messages_insert on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and exists (select 1 from public.threads t
    where t.id = thread_id and auth.uid() in (t.buyer_id, t.seller_id)));

create policy orders_read on public.orders for select to authenticated
  using (auth.uid() in (buyer_id, seller_id) or public.is_admin());
create policy orders_insert on public.orders for insert to authenticated
  with check (buyer_id = auth.uid());
create policy orders_update on public.orders for update to authenticated
  using (auth.uid() in (buyer_id, seller_id) or public.is_admin());

create policy favorites_own on public.favorites for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy reports_insert on public.reports for insert to authenticated
  with check (reporter_id = auth.uid());
create policy reports_read on public.reports for select to authenticated
  using (public.is_admin());

-- ============ Pedidos: el servidor impone las reglas del dinero ============
-- Al crear: fija vendedor, comisión y estado. El comprador no puede inventarlos.
create or replace function public.orders_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare l public.listings;
begin
  select * into l from public.listings where id = new.listing_id;
  if l.id is null or l.status <> 'active' then
    raise exception 'La prenda no está disponible';
  end if;
  if l.seller_id = auth.uid() then
    raise exception 'No puedes comprar tu propia prenda';
  end if;
  if new.price > l.price or new.price < l.price * 0.5 then
    raise exception 'Precio no válido';
  end if;
  new.buyer_id := auth.uid();
  new.seller_id := l.seller_id;
  new.fee := round((0.5 + new.price * 0.05)::numeric, 2);
  new.status := 'esperando_pago';
  return new;
end $$;
create trigger orders_before_insert before insert on public.orders
  for each row execute function public.orders_before_insert();

-- Al actualizar: solo transiciones permitidas para cada persona.
create or replace function public.orders_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if public.is_admin() then
    return new;
  end if;
  if new.id <> old.id or new.listing_id <> old.listing_id or new.buyer_id <> old.buyer_id
     or new.seller_id <> old.seller_id or new.price <> old.price or new.fee <> old.fee
     or new.created_at <> old.created_at then
    raise exception 'Campos protegidos';
  end if;
  if auth.uid() = old.buyer_id then
    if new.tracking is distinct from old.tracking then
      raise exception 'Solo el vendedor puede poner el seguimiento';
    end if;
    if new.status <> old.status and not (
         (old.status = 'esperando_pago' and new.status in ('revision','cancelado'))
      or (old.status = 'enviado' and new.status in ('liberado','disputa'))) then
      raise exception 'Cambio de estado no permitido';
    end if;
  elsif auth.uid() = old.seller_id then
    if new.pay_ref is distinct from old.pay_ref or new.delivery is distinct from old.delivery then
      raise exception 'Campos del comprador';
    end if;
    if new.status <> old.status and not (
         (old.status = 'retenido' and new.status = 'enviado')
      or (old.status = 'esperando_pago' and new.status = 'cancelado')) then
      raise exception 'Cambio de estado no permitido';
    end if;
  else
    raise exception 'No autorizado';
  end if;
  return new;
end $$;
create trigger orders_guard before update on public.orders
  for each row execute function public.orders_guard();

-- El estado del anuncio sigue al del pedido.
create or replace function public.orders_after_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    update public.listings set status = case
      when new.status in ('retenido','enviado','disputa','revision') then 'reserved'
      when new.status = 'liberado' then 'sold'
      when new.status = 'cancelado' then 'active'
      else status end
    where id = new.listing_id;
  end if;
  return new;
end $$;
create trigger orders_after_change after update on public.orders
  for each row execute function public.orders_after_change();

-- ============ Fotos ============
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('listing-photos', 'listing-photos', true, 5242880,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy photos_read on storage.objects for select
  using (bucket_id = 'listing-photos');
create policy photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = auth.uid()::text);
create policy photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = auth.uid()::text);
