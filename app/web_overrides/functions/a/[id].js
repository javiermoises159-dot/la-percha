// Cloudflare Pages Function: /a/<id>
// Cuando alguien comparte un anuncio por WhatsApp, Instagram o Telegram, esos servicios
// leen esta página (no ejecutan la app) y muestran la foto, el título y el precio.
// Las personas son llevadas enseguida a la app con el anuncio abierto.
const SUPA = 'https://udhyuyokrxggdnnepbmr.supabase.co';
// Clave pública ("publishable"): la misma que va dentro de la app. Solo lee anuncios activos.
const KEY = 'sb_publishable_PFt4DdXlWbQEvyEgP58BZQ_CKXaoHGG';

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

export async function onRequest({ params, request }) {
  const id = String(params.id || '').toLowerCase().replace(/[^0-9a-f-]/g, '').slice(0, 36);
  const origin = new URL(request.url).origin;
  const destino = `${origin}/?a=${id}`;
  let titulo = 'Pavito · Vende lo que ya no usas';
  let texto = 'Compra y vende en toda Venezuela con pago protegido. Vender es gratis.';
  let imagen = `${origin}/icons/Icon-512.png`;
  try {
    const h = { apikey: KEY, Authorization: `Bearer ${KEY}` };
    const [r, t] = await Promise.all([
      fetch(`${SUPA}/rest/v1/listings?select=title,price,size,condition,city,photos&status=in.(active,reserved)&id=eq.${id}`, { headers: h }),
      fetch(`${SUPA}/rest/v1/ajustes?select=valor&clave=eq.tasa_bs`, { headers: h }),
    ]);
    const [l] = await r.json();
    const [tasa] = await t.json().catch(() => []);
    if (l) {
      const usd = Number(l.price);
      const bs = tasa && Number(tasa.valor) > 0 ? ` (Bs ${Math.round(usd * Number(tasa.valor)).toLocaleString('es-VE')})` : '';
      titulo = `${l.title} · $${usd % 1 ? usd.toFixed(2) : usd}${bs}`;
      texto = `${l.size} · ${l.condition} · ${l.city}. Compra protegida en Pavito: tu pago queda guardado hasta que lo recibes.`;
      if (Array.isArray(l.photos) && l.photos[0] && String(l.photos[0]).startsWith(SUPA)) imagen = l.photos[0];
    }
  } catch (_) { /* si falla, se muestra la tarjeta genérica de Pavito */ }

  const html = `<!doctype html><html lang="es"><head><meta charset="utf-8">
<title>${esc(titulo)}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="${esc(texto)}">
<meta property="og:type" content="product">
<meta property="og:site_name" content="Pavito">
<meta property="og:title" content="${esc(titulo)}">
<meta property="og:description" content="${esc(texto)}">
<meta property="og:image" content="${esc(imagen)}">
<meta property="og:url" content="${esc(`${origin}/a/${id}`)}">
<meta name="twitter:card" content="summary_large_image">
<meta http-equiv="refresh" content="0; url=${esc(destino)}">
<style>body{font-family:system-ui,sans-serif;background:#E0452C;color:#fff;display:grid;place-items:center;height:100vh;margin:0}a{color:#fff}</style>
</head><body><p>Abriendo en Pavito… <a href="${esc(destino)}">Toca aquí si no abre</a></p></body></html>`;
  return new Response(html, {
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'public, max-age=300',
      'x-content-type-options': 'nosniff',
      'x-frame-options': 'DENY',
      'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; base-uri 'none'",
    },
  });
}
