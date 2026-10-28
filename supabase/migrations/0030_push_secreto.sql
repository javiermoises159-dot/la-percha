-- La función "push" ya no acepta llamadas de cualquiera: la base de datos le manda una
-- clave interna (guardada en una tabla que nadie de la app puede leer) y la función la comprueba.

create table if not exists public.secretos (
  clave text primary key,
  valor text not null
);
alter table public.secretos enable row level security;   -- sin políticas: la app no ve nada
revoke all on public.secretos from public, anon, authenticated;
grant select on public.secretos to service_role;

insert into public.secretos (clave, valor)
values ('push', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
on conflict (clave) do nothing;

create or replace function public.avisos_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare clave text;
begin
  if tg_op = 'UPDATE' and (new.texto is not distinct from old.texto or new.leido) then return new; end if;
  if not exists (select 1 from public.push_subs where user_id = new.user_id) then return new; end if;
  if to_regproc('net.http_post') is null then return new; end if;
  select valor into clave from public.secretos where secretos.clave = 'push';
  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
    using 'https://udhyuyokrxggdnnepbmr.supabase.co/functions/v1/push',
          jsonb_build_object('aviso', new.id),
          jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', coalesce(clave, ''));
  return new;
exception when others then
  return new; -- un fallo al notificar nunca debe frenar la app
end $$;
revoke all on function public.avisos_push() from public, anon, authenticated;
