-- Aceptar los términos es obligatorio para crear el perfil, y queda registrado con la fecha del servidor.
alter table public.profiles add column if not exists terminos_at timestamptz;
grant insert (terminos_at) on public.profiles to authenticated;

create or replace function public.profiles_terminos() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    if new.terminos_at is null then
      raise exception 'Debes aceptar los términos y condiciones para crear tu cuenta';
    end if;
    new.terminos_at := now();   -- la hora la pone el servidor, no la app
  end if;
  return new;
end $$;
drop trigger if exists profiles_terminos on public.profiles;
create trigger profiles_terminos before insert on public.profiles
  for each row execute function public.profiles_terminos();
