-- Rebaja programada: el vendedor elige "bajar X % si no se vende en N días". Se aplica una sola vez.
alter table public.listings add column if not exists rebaja_pct int;
alter table public.listings add column if not exists rebaja_dias int;
alter table public.listings add column if not exists rebaja_en timestamptz;
alter table public.listings drop constraint if exists listings_rebaja_valida;
alter table public.listings add constraint listings_rebaja_valida check (
  (rebaja_pct is null and rebaja_dias is null and rebaja_en is null)
  or (rebaja_pct in (5,10,15,20,25) and rebaja_dias in (7,14,30) and rebaja_en is not null));
grant insert (rebaja_pct, rebaja_dias) on public.listings to authenticated;
grant update (rebaja_pct, rebaja_dias) on public.listings to authenticated;

-- La fecha la pone el servidor al elegir o cambiar la rebaja; la app no puede fijarla.
create or replace function public.listings_rebaja_fecha() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.rebaja_pct is null or new.rebaja_dias is null then
    new.rebaja_pct := null; new.rebaja_dias := null; new.rebaja_en := null;
  elsif tg_op = 'INSERT' or new.rebaja_pct is distinct from old.rebaja_pct
        or new.rebaja_dias is distinct from old.rebaja_dias then
    new.rebaja_en := now() + make_interval(days => new.rebaja_dias);
  else
    new.rebaja_en := old.rebaja_en;
  end if;
  return new;
end $$;
revoke all on function public.listings_rebaja_fecha() from public, anon, authenticated;
drop trigger if exists listings_rebaja_fecha on public.listings;
create trigger listings_rebaja_fecha before insert or update on public.listings
  for each row execute function public.listings_rebaja_fecha();

-- Solo el dueño ve su rebaja programada (a los compradores no se les adelanta).
create or replace function public.mi_rebaja(p_listing uuid) returns jsonb
language sql security definer stable set search_path = public as $$
  select jsonb_build_object('pct', rebaja_pct, 'dias', rebaja_dias, 'en', rebaja_en)
  from public.listings where id = p_listing and seller_id = auth.uid()
$$;
revoke all on function public.mi_rebaja(uuid) from public, anon;
grant execute on function public.mi_rebaja(uuid) to authenticated;

-- Aplica las rebajas vencidas. El trigger avisar_rebaja avisa a quienes lo tienen en favoritos.
create or replace function public.aplicar_rebajas() returns int
language plpgsql security definer set search_path = public as $$
declare n int := 0; l record; nuevo numeric;
begin
  for l in select id, price, rebaja_pct from public.listings
           where status = 'active' and rebaja_en is not null and rebaja_en <= now() limit 500 loop
    nuevo := round(l.price * (100 - l.rebaja_pct) / 100.0, 2);
    if nuevo >= 1 and nuevo < l.price then
      update public.listings set price = nuevo, rebaja_pct = null, rebaja_dias = null, rebaja_en = null where id = l.id;
      n := n + 1;
    else
      update public.listings set rebaja_pct = null, rebaja_dias = null, rebaja_en = null where id = l.id;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.aplicar_rebajas() from public, anon, authenticated;

do $$ begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'pavito_rebajas';
  perform cron.schedule('pavito_rebajas', '7 * * * *', 'select public.aplicar_rebajas()');
exception when others then
  raise notice 'pg_cron no disponible (%). La rebaja programada no correrá sola.', sqlerrm;
end $$;
notify pgrst, 'reload schema';
