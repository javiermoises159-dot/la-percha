-- La Percha fase 2: tasa BCV, seguir vendedores, aviso de bajada de precio y destacar anuncios.

-- ============ Ajustes públicos (tasa BCV) ============
create table if not exists public.ajustes (
  clave text primary key,
  valor numeric not null,
  actualizado timestamptz not null default now()
);
alter table public.ajustes enable row level security;
revoke all on public.ajustes from anon, authenticated;
grant select on public.ajustes to anon, authenticated;
drop policy if exists ajustes_read on public.ajustes;
create policy ajustes_read on public.ajustes for select using (true);
insert into public.ajustes (clave, valor) values ('tasa_bs', 0) on conflict do nothing;

-- Guarda una tasa nueva solo si es razonable (evita que una fuente rota o falsa
-- ponga precios absurdos): positiva y, si ya hay una, entre la mitad y el doble.
create or replace function public.guardar_tasa(v numeric) returns boolean
language plpgsql security definer set search_path = public as $$
declare actual numeric;
begin
  select valor into actual from public.ajustes where clave = 'tasa_bs';
  if v is null or v <= 0 or v > 1000000 then return false; end if;
  if coalesce(actual, 0) > 0 and (v < actual * 0.5 or v > actual * 2) then return false; end if;
  update public.ajustes set valor = round(v, 4), actualizado = now() where clave = 'tasa_bs';
  return true;
end $$;
revoke all on function public.guardar_tasa(numeric) from public, anon, authenticated;

-- El admin puede fijarla a mano (sin el filtro, por si la fuente falla días).
create or replace function public.admin_set_tasa(v numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v is null or v <= 0 then raise exception 'Tasa no válida'; end if;
  update public.ajustes set valor = round(v, 4), actualizado = now() where clave = 'tasa_bs';
end $$;
revoke all on function public.admin_set_tasa(numeric) from public, anon;
grant execute on function public.admin_set_tasa(numeric) to authenticated;

-- Lee la última respuesta de DolarAPI (pedida por pg_net) y guarda el promedio.
create or replace function public.tasa_desde_respuesta() returns void
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  execute $q$ select content from net._http_response
              where status_code = 200 and content like '%promedio%'
                and created > now() - interval '2 hours'
              order by created desc limit 1 $q$ into c;
  if c is not null then
    perform public.guardar_tasa((c::jsonb ->> 'promedio')::numeric);
  end if;
exception when others then
  raise notice 'No se pudo leer la tasa: %', sqlerrm;
end $$;
revoke all on function public.tasa_desde_respuesta() from public, anon, authenticated;

do $$ begin
  create extension if not exists pg_net;
  perform cron.unschedule(jobid) from cron.job where jobname in ('lapercha_tasa_pedir', 'lapercha_tasa_guardar');
  perform cron.schedule('lapercha_tasa_pedir', '7 * * * *',
    $c$ select net.http_get('https://ve.dolarapi.com/v1/dolares/oficial') $c$);
  perform cron.schedule('lapercha_tasa_guardar', '9 * * * *',
    'select public.tasa_desde_respuesta()');
exception when others then
  raise notice 'Tasa automática no programada (%). Se puede fijar a mano en el panel.', sqlerrm;
end $$;

-- ============ Seguir vendedores ============
create table if not exists public.follows (
  follower_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, seller_id),
  check (follower_id <> seller_id)
);
alter table public.follows enable row level security;
revoke all on public.follows from anon, authenticated;
grant select, delete on public.follows to authenticated;
grant insert (seller_id) on public.follows to authenticated;
drop policy if exists follows_own on public.follows;
create policy follows_own on public.follows for all to authenticated
  using (follower_id = auth.uid()) with check (follower_id = auth.uid() and not public.is_blocked());
drop trigger if exists follows_rate on public.follows;
create trigger follows_rate before insert on public.follows
  for each row execute function public.rate_limit('follower_id', '100', '3600');

-- Cuántos seguidores tiene alguien (sin revelar quiénes).
create or replace function public.followers_count(p_user uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.follows where seller_id = p_user
$$;
grant execute on function public.followers_count(uuid) to anon, authenticated;

-- ============ Favoritos: precio al guardarlo (para avisar si baja) ============
alter table public.favorites add column if not exists price_at numeric(8,2);
create or replace function public.favorites_price_at() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.price_at := (select price from public.listings where id = new.listing_id);
  return new;
end $$;
drop trigger if exists favorites_price_at on public.favorites;
create trigger favorites_price_at before insert on public.favorites
  for each row execute function public.favorites_price_at();

-- ============ Destacar anuncios ============
alter table public.listings add column if not exists featured_until timestamptz;
-- Nadie lo puede escribir desde la app: no está entre las columnas permitidas,
-- y el guardián rechaza el cambio si no viene de un admin.
create or replace function public.listings_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_admin() or public.lp_sistema() then
    return new;
  end if;
  if new.seller_id <> old.seller_id or new.created_at <> old.created_at
     or new.featured_until is distinct from old.featured_until then
    raise exception 'Campos protegidos';
  end if;
  if old.status in ('reserved','sold') then
    raise exception 'Este anuncio tiene un pedido y no se puede cambiar';
  end if;
  if new.status not in ('active','hidden') then
    raise exception 'Estado no permitido';
  end if;
  return new;
end $$;

create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  days int not null check (days in (3, 7)),
  amount numeric(8,2) not null,
  pay_ref text not null check (char_length(pay_ref) between 4 and 40),
  status text not null default 'revision' check (status in ('revision','activa','rechazada')),
  created_at timestamptz not null default now()
);
do $$ begin
  create unique index if not exists promotions_pay_ref_unica on public.promotions (lower(btrim(pay_ref)))
    where status <> 'rechazada';
exception when others then raise notice '%', sqlerrm; end $$;
alter table public.promotions enable row level security;
revoke all on public.promotions from anon, authenticated;
grant select on public.promotions to authenticated;
drop policy if exists promotions_read on public.promotions;
create policy promotions_read on public.promotions for select to authenticated
  using (seller_id = auth.uid() or public.is_admin());

create or replace function public.request_promotion(p_listing uuid, p_days int, p_pay_ref text)
returns uuid language plpgsql security definer set search_path = public as $$
declare l public.listings; v_id uuid; n int;
begin
  if auth.uid() is null or public.is_blocked() then raise exception 'No autorizado'; end if;
  select * into l from public.listings where id = p_listing;
  if l.id is null or l.seller_id <> auth.uid() then raise exception 'No autorizado'; end if;
  if l.status <> 'active' then raise exception 'Solo puedes destacar anuncios activos'; end if;
  if p_days not in (3, 7) then raise exception 'Elige 3 o 7 días'; end if;
  if coalesce(btrim(p_pay_ref), '') = '' then raise exception 'Escribe la referencia del Pago Móvil'; end if;
  if exists (select 1 from public.orders where lower(btrim(pay_ref)) = lower(btrim(p_pay_ref))
               and status <> 'cancelado') then
    raise exception 'Esa referencia ya se usó';
  end if;
  select count(*) into n from public.promotions
    where seller_id = auth.uid() and created_at > now() - interval '1 day';
  if n >= 10 then raise exception 'Demasiadas solicitudes hoy'; end if;
  insert into public.promotions (listing_id, seller_id, days, amount, pay_ref)
    values (l.id, auth.uid(), p_days, case p_days when 3 then 1 else 2 end, btrim(p_pay_ref))
    returning id into v_id;
  return v_id;
end $$;
revoke all on function public.request_promotion(uuid, int, text) from public, anon;
grant execute on function public.request_promotion(uuid, int, text) to authenticated;

create or replace function public.admin_review_promotion(p_id uuid, p_ok boolean)
returns void language plpgsql security definer set search_path = public as $$
declare p public.promotions;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  select * into p from public.promotions where id = p_id for update;
  if p.id is null or p.status <> 'revision' then raise exception 'Ya revisada'; end if;
  update public.promotions set status = case when p_ok then 'activa' else 'rechazada' end where id = p.id;
  if p_ok then
    update public.listings
      set featured_until = greatest(coalesce(featured_until, now()), now()) + make_interval(days => p.days)
      where id = p.listing_id;
  end if;
end $$;
revoke all on function public.admin_review_promotion(uuid, boolean) from public, anon;
grant execute on function public.admin_review_promotion(uuid, boolean) to authenticated;
