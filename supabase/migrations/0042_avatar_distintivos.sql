-- Foto de perfil / logo de tienda + distintivos.
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles drop constraint if exists profiles_avatar_propio;
alter table public.profiles add constraint profiles_avatar_propio check (
  avatar_url is null or (char_length(avatar_url) <= 300 and avatar_url like
    'https://udhyuyokrxggdnnepbmr.supabase.co/storage/v1/object/public/avatares/' || id::text || '/%'));
grant select (avatar_url) on public.profiles to anon, authenticated;
grant update (avatar_url) on public.profiles to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatares', 'avatares', true, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;
drop policy if exists avatares_read on storage.objects;
create policy avatares_read on storage.objects for select using (bucket_id = 'avatares');
drop policy if exists avatares_insert on storage.objects;
create policy avatares_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'avatares' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists avatares_update on storage.objects;
create policy avatares_update on storage.objects for update to authenticated
  using (bucket_id = 'avatares' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists avatares_delete on storage.objects;
create policy avatares_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avatares' and (storage.foldername(name))[1] = auth.uid()::text);

-- Distintivos: se calculan siempre en el servidor, nadie puede marcárselos a mano.
create or replace function public.distintivos_de(p_user uuid) returns jsonb
language sql security definer stable set search_path = public as $$
  select jsonb_build_object(
    'foto',          coalesce((select avatar_url is not null from profiles where id = p_user), false),
    'primera_prenda',(select count(*) from listings where seller_id = p_user) >= 1,
    'closet_10',     (select count(*) from listings where seller_id = p_user) >= 10,
    'primera_venta', (select count(*) from orders where seller_id = p_user and status = 'liberado') >= 1,
    'vendedor_5',    (select count(*) from orders where seller_id = p_user and status = 'liberado') >= 5,
    'primera_compra',(select count(*) from orders where buyer_id = p_user and status = 'liberado') >= 1,
    'buena_fama',    (select count(*) >= 3 and coalesce(avg(stars), 0) >= 4.5 from reviews where target_id = p_user),
    'fundador',      coalesce((select fundador_n is not null from profiles where id = p_user), false),
    'verificado',    coalesce((select verificado from profiles where id = p_user), false)
  )
$$;
revoke all on function public.distintivos_de(uuid) from public;
grant execute on function public.distintivos_de(uuid) to anon, authenticated;
notify pgrst, 'reload schema';
