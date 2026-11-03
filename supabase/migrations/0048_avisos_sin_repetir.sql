-- 0048: no repetir el mismo mensaje del panel si se toca "Enviar" varias veces.
create or replace function public.avisos_pavito_sin_repetir() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.tipo = 'pavito' and exists (
       select 1 from public.avisos a
        where a.user_id = new.user_id and a.tipo = 'pavito' and a.texto = new.texto
          and a.creado > now() - interval '1 hour') then
    return null; -- ya lo tiene: no se inserta otra vez
  end if;
  return new;
end $$;
revoke all on function public.avisos_pavito_sin_repetir() from public, anon, authenticated;
drop trigger if exists avisos_pavito_sin_repetir on public.avisos;
create trigger avisos_pavito_sin_repetir before insert on public.avisos
  for each row execute function public.avisos_pavito_sin_repetir();
