-- Pavito (antes La Percha): el nombre de la marca queda reservado para usuarios.
create or replace function public.profiles_check_username() returns trigger
language plpgsql set search_path = public as $$
declare u text := lower(regexp_replace(new.username, '[._0-9]', '', 'g'));
begin
  if new.username !~ '^[A-Za-z0-9_.]{3,20}$' then
    raise exception 'Usa de 3 a 20 letras, números, punto o guion bajo';
  end if;
  if (tg_op = 'INSERT' or new.username is distinct from old.username)
     and not coalesce(public.is_admin(), false)
     and u ~ '(admin|pavito|lapercha|percha|soporte|support|moderador|oficial|staff)' then
    raise exception 'Ese nombre de usuario está reservado';
  end if;
  return new;
end $$;
