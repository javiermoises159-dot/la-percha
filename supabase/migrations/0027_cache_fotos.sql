-- 0027: las fotos de anuncios no cambian nunca (cada una tiene nombre único),
-- así que el navegador y la CDN pueden guardarlas un año en vez de 1 hora.
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'storage' and table_name = 'objects' and column_name = 'metadata') then
    update storage.objects
       set metadata = jsonb_set(coalesce(metadata, '{}'::jsonb), '{cacheControl}', '"max-age=31536000"')
     where bucket_id = 'listing-photos'
       and coalesce(metadata->>'cacheControl', '') <> 'max-age=31536000';
  end if;
end $$;
