-- Opiniones de usuarios (estrellas + comentario). Una por persona; solo el admin las lee todas.
create table if not exists public.opiniones (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique default auth.uid() references public.profiles(id) on delete cascade,
  estrellas int not null check (estrellas between 1 and 5),
  comentario text check (comentario is null or char_length(comentario) <= 600),
  created_at timestamptz not null default now()
);
alter table public.opiniones enable row level security;
revoke all on public.opiniones from anon, authenticated;
grant select, insert (estrellas, comentario) on public.opiniones to authenticated;

drop policy if exists opiniones_insert on public.opiniones;
create policy opiniones_insert on public.opiniones for insert to authenticated
  with check (user_id = auth.uid());
drop policy if exists opiniones_select on public.opiniones;
create policy opiniones_select on public.opiniones for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- ¿Toca pedirle su opinión? Sí si ya completó una compra o una venta y aún no opinó.
create or replace function public.quiere_opinar() returns boolean
language sql security definer stable set search_path = public as $$
  select auth.uid() is not null
    and not exists (select 1 from public.opiniones where user_id = auth.uid())
    and exists (select 1 from public.orders
                where status = 'liberado' and (buyer_id = auth.uid() or seller_id = auth.uid()))
$$;
revoke all on function public.quiere_opinar() from public, anon;
grant execute on function public.quiere_opinar() to authenticated;
notify pgrst, 'reload schema';
