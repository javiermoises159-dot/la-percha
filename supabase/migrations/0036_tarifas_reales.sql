-- Tarifas de envío basadas en las tarifas públicas de Tealca (carga nacional, contado,
-- vigentes desde el 8/01/2026) más 16 % de IVA. Son referenciales: el admin las puede ajustar.
-- Pequeño = hasta 1 kg, Mediano = hasta 2 kg, Grande = hasta 4 kg.
-- Zonas: misma ciudad (Zona 1), misma región (Zona 2), resto del país (Zona 4), Isla de Margarita (Zona 5).
insert into public.ajustes (clave, valor) values
  ('envio_chico_ciudad', 3.90),   ('envio_chico_region', 5.50),   ('envio_chico_pais', 6.10),   ('envio_chico_isla', 7.00),
  ('envio_mediano_ciudad', 5.90), ('envio_mediano_region', 7.60), ('envio_mediano_pais', 8.50), ('envio_mediano_isla', 9.80),
  ('envio_grande_ciudad', 10.00), ('envio_grande_region', 13.50), ('envio_grande_pais', 16.00), ('envio_grande_isla', 17.80)
on conflict (clave) do update set valor = excluded.valor, actualizado = now();

-- Regiones donde una ciudad queda a menos de ~300 km de otra.
create or replace function public.lp_region(ciudad text) returns text
language sql immutable as $$
  select case
    when ciudad in ('Caracas', 'Valencia', 'Maracay') then 'centro'
    when ciudad in ('Mérida', 'San Cristóbal') then 'andes'
    else null end $$;

create or replace function public.lp_zona(origen text, destino text) returns text
language sql immutable as $$
  select case
    when origen is not null and origen = destino then 'ciudad'
    when origen = 'Isla de Margarita' or destino = 'Isla de Margarita' then 'isla'
    when public.lp_region(origen) is not null and public.lp_region(origen) = public.lp_region(destino) then 'region'
    else 'pais' end $$;

create or replace function public.admin_set_envio(p_clave text, p_valor numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_clave !~ '^envio_(chico|mediano|grande)_(ciudad|region|pais|isla)$' then raise exception 'Tarifa no válida'; end if;
  if p_valor is null or p_valor < 0 or p_valor > 100 then raise exception 'La tarifa debe estar entre 0 y 100 USD'; end if;
  update public.ajustes set valor = round(p_valor, 2), actualizado = now() where clave = p_clave;
end $$;
revoke all on function public.admin_set_envio(text, numeric) from public, anon;
grant execute on function public.admin_set_envio(text, numeric) to authenticated;
