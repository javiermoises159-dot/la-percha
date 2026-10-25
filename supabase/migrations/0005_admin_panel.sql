-- Panel de administración: bloquear / desbloquear usuarios (solo admins).
create or replace function public.admin_set_blocked(uid uuid, flag boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if exists (select 1 from public.profiles where id = uid and is_admin) then
    raise exception 'No se puede bloquear a un administrador';
  end if;
  update public.profiles set blocked = flag where id = uid;
end $$;
revoke all on function public.admin_set_blocked(uuid, boolean) from public, anon;
grant execute on function public.admin_set_blocked(uuid, boolean) to authenticated;
