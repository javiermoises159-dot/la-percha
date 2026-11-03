-- 0045: ayudas para vender y comprar.
--  1. precios_parecidos: rango de precios de prendas parecidas ya publicadas en Pavito (solo si hay 5 o más).
--  2. resumen_semanal: cada lunes avisa a quien guardó "Mi talla" cuántas prendas nuevas llegaron en esa talla.

create or replace function public.precios_parecidos(p_category text, p_brand text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare mb int; usar_marca boolean := false; r record; marca text := lower(btrim(coalesce(p_brand, '')));
begin
  if auth.uid() is null or coalesce(p_category, '') = '' then return null; end if;
  if marca <> '' then
    select count(*) into mb from public.listings
      where category = p_category and lower(brand) = marca and status in ('active','reserved','sold') and seller_id <> auth.uid();
    usar_marca := mb >= 5;
  end if;
  select count(*) as n,
         percentile_cont(0.25) within group (order by price) as p25,
         percentile_cont(0.5)  within group (order by price) as p50,
         percentile_cont(0.75) within group (order by price) as p75
    into r
    from public.listings
   where category = p_category and status in ('active','reserved','sold') and seller_id <> auth.uid()
     and (not usar_marca or lower(brand) = marca);
  if r.n < 5 then return null; end if;
  return jsonb_build_object('n', r.n, 'bajo', round(r.p25::numeric, 0), 'medio', round(r.p50::numeric, 0),
                            'alto', round(r.p75::numeric, 0), 'marca', usar_marca);
end $$;
revoke all on function public.precios_parecidos(text, text) from public, anon;
grant execute on function public.precios_parecidos(text, text) to authenticated;

create or replace function public.resumen_semanal() returns void
language plpgsql security definer set search_path = public as $$
declare u record; n int;
begin
  for u in
    select pp.id as uid, nullif(btrim(pp.prefs->>'ropa'), '') as ropa, nullif(btrim(pp.prefs->>'calzado'), '') as calzado
      from public.private_profiles pp join public.profiles p on p.id = pp.id
     where pp.prefs is not null and not p.blocked
       and (nullif(btrim(pp.prefs->>'ropa'), '') is not null or nullif(btrim(pp.prefs->>'calzado'), '') is not null)
     limit 5000
  loop
    select count(*) into n from public.listings l
     where l.status = 'active' and l.seller_id <> u.uid and l.created_at > now() - interval '7 days'
       and (lower(l.size) = lower(coalesce(u.ropa, '#')) or lower(l.size) = lower(coalesce(u.calzado, '#')));
    if n >= 1 then
      perform public.avisar(u.uid, 'Esta semana llegaron ' || n || case when n = 1 then ' prenda nueva' else ' prendas nuevas' end
        || ' en tu talla. ¡Échales un vistazo!', 'perfil', null);
    end if;
  end loop;
end $$;
revoke all on function public.resumen_semanal() from public, anon, authenticated;
do $$ begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'pavito_resumen_semanal';
  perform cron.schedule('pavito_resumen_semanal', '0 15 * * 1', 'select public.resumen_semanal()');  -- lunes, 11 am en Venezuela
exception when others then
  raise notice 'Resumen semanal no programado (%).', sqlerrm;
end $$;
