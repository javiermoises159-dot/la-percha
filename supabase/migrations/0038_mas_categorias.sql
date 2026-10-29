-- Pavito: más categorías para publicar (Electrónica sigue fuera por riesgo de estafas).
alter table public.listings drop constraint if exists listings_categoria_permitida;
alter table public.listings add constraint listings_categoria_permitida check (category in (
  'Mujer', 'Hombre', 'Niños', 'Bebés', 'Zapatos', 'Accesorios',
  'Hogar', 'Libros y juegos', 'Deportes', 'Mascotas',
  'Belleza', 'Juguetes', 'Arte y manualidades', 'Música', 'Otros')) not valid;

create or replace function public.lp_envio_tamano(cat text) returns text
language sql immutable as $$
  select case
    when cat in ('Accesorios', 'Bebés', 'Libros y juegos', 'Mascotas', 'Belleza') then 'chico'
    when cat in ('Zapatos', 'Hogar', 'Deportes', 'Música') then 'grande'
    else 'mediano' end $$;
