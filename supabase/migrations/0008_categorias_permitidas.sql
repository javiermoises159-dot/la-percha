-- La Percha: solo se pueden publicar artículos de las categorías permitidas.
-- Electrónica queda fuera por ahora (alto riesgo de estafas).
alter table public.listings drop constraint if exists listings_categoria_permitida;
alter table public.listings add constraint listings_categoria_permitida check (category in (
  'Mujer', 'Hombre', 'Niños', 'Bebés', 'Zapatos', 'Accesorios',
  'Hogar', 'Libros y juegos', 'Deportes', 'Mascotas')) not valid;
