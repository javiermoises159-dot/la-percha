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

-- El contador de "enviados" solo cuenta los avisos que de verdad se crearon.
create or replace function public.admin_enviar_aviso(p_texto text, p_grupo text, p_ciudad text default null,
                                                     p_usuario uuid default null, p_simular boolean default false)
returns int language plpgsql security definer set search_path = public, interno as $$
declare t text := btrim(coalesce(p_texto, '')); n int := 0; k int; r record;
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  if p_grupo not in ('todos','sin_prendas','con_prendas','fundadores','ciudad','usuario') then raise exception 'Grupo no válido'; end if;
  if p_grupo = 'ciudad' and coalesce(btrim(p_ciudad), '') = '' then raise exception 'Indica la ciudad'; end if;
  if p_grupo = 'usuario' and p_usuario is null then raise exception 'Indica el usuario'; end if;
  if not p_simular then
    if char_length(t) < 5 or char_length(t) > 160 then raise exception 'El mensaje debe tener entre 5 y 160 caracteres'; end if;
    if p_grupo <> 'usuario' and (select count(*) from interno.comunicados
         where grupo <> 'usuario' and creado > now() - interval '1 day') >= 5 then
      raise exception 'Máximo 5 mensajes masivos por día, para no cansar a la gente';
    end if;
  end if;
  for r in
    select p.id from public.profiles p
     where not p.is_admin and not p.blocked
       and case p_grupo
             when 'todos' then true
             when 'sin_prendas' then not exists (select 1 from public.listings l where l.seller_id = p.id and l.status in ('active','reserved'))
             when 'con_prendas' then exists (select 1 from public.listings l where l.seller_id = p.id and l.status in ('active','reserved'))
             when 'fundadores' then p.fundador_n is not null
             when 'ciudad' then public.lp_sin_tildes(p.city) = public.lp_sin_tildes(btrim(p_ciudad))
             when 'usuario' then p.id = p_usuario
           end
  loop
    if p_simular then
      n := n + 1;
    else
      insert into public.avisos (user_id, texto, tipo, ref_id) values (r.id, t, 'pavito', null);
      get diagnostics k = row_count;
      n := n + k;
    end if;
  end loop;
  if not p_simular and n > 0 then
    insert into interno.comunicados (admin_id, texto, grupo, ciudad, enviados)
    values (auth.uid(), t, p_grupo, nullif(btrim(coalesce(p_ciudad, '')), ''), n);
  end if;
  return n;
end $$;
revoke all on function public.admin_enviar_aviso(text, text, text, uuid, boolean) from public, anon;
grant execute on function public.admin_enviar_aviso(text, text, text, uuid, boolean) to authenticated;
