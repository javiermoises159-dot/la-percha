-- 0024: enterarse cuando algo falla.
--  1. Registro de errores de la app (lo que falla en el teléfono de alguien).
--  2. Alertas en el panel: errores recientes, tasa del BCV sin actualizar, pagos atascados.

create table if not exists public.errores_app (
  id bigint generated always as identity primary key,
  user_id uuid,
  mensaje text not null,
  pila text,
  plataforma text,
  version text,
  url text,
  creado timestamptz not null default now()
);
create index if not exists errores_app_creado on public.errores_app (creado desc);
alter table public.errores_app enable row level security;
revoke all on public.errores_app from anon, authenticated;
grant select on public.errores_app to authenticated;
drop policy if exists errores_admin on public.errores_app;
create policy errores_admin on public.errores_app for select to authenticated using (public.is_admin());

-- La app reporta sus errores. Con límites para que nadie llene la tabla.
create or replace function public.reportar_error(p_mensaje text, p_pila text default null, p_plataforma text default null,
                                                 p_version text default null, p_url text default null) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if coalesce(btrim(p_mensaje), '') = '' then return; end if;
  select count(*) into n from public.errores_app where creado > now() - interval '1 minute';
  if n >= 60 then return; end if;
  if auth.uid() is not null then
    select count(*) into n from public.errores_app where user_id = auth.uid() and creado > now() - interval '1 hour';
    if n >= 20 then return; end if;
  end if;
  -- Mismo error de la misma persona en los últimos 10 minutos: no se repite.
  if exists (select 1 from public.errores_app where mensaje = left(p_mensaje, 500)
             and user_id is not distinct from auth.uid() and creado > now() - interval '10 minutes') then
    return;
  end if;
  insert into public.errores_app (user_id, mensaje, pila, plataforma, version, url)
  values (auth.uid(), left(p_mensaje, 500), left(p_pila, 2000), left(p_plataforma, 40), left(p_version, 20), left(p_url, 300));
  delete from public.errores_app where creado < now() - interval '30 days';
end $$;
revoke all on function public.reportar_error(text, text, text, text, text) from public;
grant execute on function public.reportar_error(text, text, text, text, text) to anon, authenticated;

-- Alertas del panel en un solo pedido.
create or replace function public.admin_alertas() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_admin() then null else jsonb_build_object(
    'errores_24h', (select count(*) from public.errores_app where creado > now() - interval '24 hours'),
    'tasa_horas', (select round(extract(epoch from now() - actualizado) / 3600, 1) from public.ajustes where clave = 'tasa_bs'),
    'tasa', (select valor from public.ajustes where clave = 'tasa_bs'),
    'pagos_atascados', (select count(distinct coalesce(bundle_id, id)) from public.orders
                        where status = 'revision' and updated_at < now() - interval '12 hours'),
    'retiros_atrasados', (select count(*) from public.retiros where estado = 'pendiente'
                          and now() > public.lp_mas_habiles(creado, 2))
  ) end
$$;
revoke all on function public.admin_alertas() from public, anon;
grant execute on function public.admin_alertas() to authenticated;
