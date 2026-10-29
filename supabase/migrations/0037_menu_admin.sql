-- La app necesita saber si la cuenta es de administrador para mostrar la entrada al panel
-- (que luego pide el código de verificación en dos pasos). Solo responde sobre la propia cuenta.
-- No da ningún permiso: todo lo del panel sigue exigiendo is_admin() con verificación en dos pasos.
create or replace function public.cuenta_es_admin() returns boolean
language sql security definer stable set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
$$;
revoke all on function public.cuenta_es_admin() from public, anon;
grant execute on function public.cuenta_es_admin() to authenticated;
