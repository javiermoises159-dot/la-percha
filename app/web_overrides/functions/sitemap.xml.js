// Cloudflare Pages Function: /sitemap.xml
// Lista los anuncios activos para que Google los encuentre y los muestre en sus búsquedas.
const SUPA = 'https://udhyuyokrxggdnnepbmr.supabase.co';
const KEY = 'sb_publishable_PFt4DdXlWbQEvyEgP58BZQ_CKXaoHGG';

export async function onRequest({ request }) {
  const origin = new URL(request.url).origin;
  let filas = [];
  try {
    const r = await fetch(`${SUPA}/rest/v1/listings?select=id,created_at&status=eq.active&order=created_at.desc&limit=5000`,
      { headers: { apikey: KEY, Authorization: `Bearer ${KEY}` } });
    if (r.ok) filas = await r.json();
  } catch (_) {}
  const urls = [`<url><loc>${origin}/</loc><changefreq>hourly</changefreq></url>`]
    .concat(filas.filter((f) => /^[0-9a-f-]{36}$/.test(f.id)).map((f) =>
      `<url><loc>${origin}/a/${f.id}</loc><lastmod>${String(f.created_at).slice(0, 10)}</lastmod></url>`));
  const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.join('\n')}\n</urlset>\n`;
  return new Response(xml, { headers: { 'content-type': 'application/xml; charset=utf-8', 'cache-control': 'public, max-age=3600' } });
}
