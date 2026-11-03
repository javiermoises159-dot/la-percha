-- 0046: al actualizar una foto de perfil, la nueva ruta también debe estar en la carpeta propia
-- (antes solo se comprobaba la ruta vieja).
drop policy if exists avatares_update on storage.objects;
create policy avatares_update on storage.objects for update to authenticated
  using (bucket_id = 'avatares' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatares' and (storage.foldername(name))[1] = auth.uid()::text);
