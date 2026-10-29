-- Envío gratis: el vendedor puede ofrecer pagar el envío (opcional, por anuncio).
alter table public.listings add column if not exists envio_gratis boolean not null default false;
grant select (envio_gratis) on public.listings to anon, authenticated;
grant insert (envio_gratis) on public.listings to authenticated;
grant update (envio_gratis) on public.listings to authenticated;
