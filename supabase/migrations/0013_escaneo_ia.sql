-- La Percha: "Vende con una foto" (escaneo con IA).
-- La clave de la IA vive solo en el servidor (función escanear). Aquí: límite de uso
-- y marca de portada generada por IA.

create table if not exists public.ai_scans (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists ai_scans_user on public.ai_scans (user_id, created_at desc);
alter table public.ai_scans enable row level security;
revoke all on public.ai_scans from anon, authenticated;

-- Cuenta un escaneo si la persona no pasó su límite diario. Devuelve los que le quedan, o -1.
create or replace function public.ai_scan_permitido() returns int
language plpgsql security definer set search_path = public as $$
declare n int; limite int := 20;
begin
  if auth.uid() is null or public.is_blocked() then return -1; end if;
  if not exists (select 1 from public.profiles where id = auth.uid()) then return -1; end if;
  select count(*) into n from public.ai_scans
    where user_id = auth.uid() and created_at > now() - interval '24 hours';
  if n >= limite then return -1; end if;
  insert into public.ai_scans (user_id) values (auth.uid());
  delete from public.ai_scans where created_at < now() - interval '7 days';
  return limite - n - 1;
end $$;
revoke all on function public.ai_scan_permitido() from public, anon;
grant execute on function public.ai_scan_permitido() to authenticated;

-- Portada generada por IA: se avisa al comprador y exige al menos una foto real más.
alter table public.listings add column if not exists foto_ia boolean not null default false;
grant insert (foto_ia) on public.listings to authenticated;
grant update (foto_ia) on public.listings to authenticated;
alter table public.listings drop constraint if exists listings_foto_ia_real;
alter table public.listings add constraint listings_foto_ia_real
  check (not foto_ia or cardinality(photos) >= 2) not valid;
