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
  let cuerpo = '<h1>Pavito</h1><p>Este anuncio ya no está disponible. Mira otras prendas en Pavito.</p>';
  let ld = '';
  let estado = 404;
  try {
    const h = { apikey: KEY, Authorization: `Bearer ${KEY}` };
    const [r, t] = await Promise.all([
      fetch(`${SUPA}/rest/v1/listings?select=title,description,price,size,condition,city,category,photos,status,profiles!listings_seller_id_fkey(username)&status=in.(active,reserved)&id=eq.${id}`, { headers: h }),
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
      estado = 200;
      const vendedor = l.profiles && l.profiles.username ? l.profiles.username : '';
      const desc = String(l.description || '').slice(0, 600);
      cuerpo = `<img src="${esc(imagen)}" alt="${esc(l.title)}" width="320">
<h1>${esc(l.title)}</h1>
<p class="p">$${esc(usd % 1 ? usd.toFixed(2) : usd)}${esc(bs)}</p>
<p>${esc(l.category)} · Talla ${esc(l.size)} · ${esc(l.condition)} · ${esc(l.city)}</p>
<p>${esc(desc)}</p>
${vendedor ? `<p>Vende: @${esc(vendedor)}</p>` : ''}
<p>Compra protegida en Pavito: tu pago queda guardado hasta que recibes la prenda.</p>`;
      ld = JSON.stringify({
        '@context': 'https://schema.org', '@type': 'Product', name: l.title, description: desc || texto,
        image: [imagen], category: l.category,
        offers: { '@type': 'Offer', price: usd.toFixed(2), priceCurrency: 'USD', url: `${origin}/a/${id}`,
          availability: l.status === 'active' ? 'https://schema.org/InStock' : 'https://schema.org/SoldOut',
          itemCondition: /nuevo/i.test(l.condition) ? 'https://schema.org/NewCondition' : 'https://schema.org/UsedCondition' },
      }).replace(/</g, '\\u003c');
    }
  } catch (_) { /* si falla, se muestra la tarjeta genérica de Pavito */ }

  const html = `<!doctype html><html lang="es"><head><meta charset="utf-8">
<title>${esc(titulo)} | Pavito</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="${esc(texto)}">
<link rel="canonical" href="${esc(`${origin}/a/${id}`)}">
<meta property="og:type" content="product">
<meta property="og:site_name" content="Pavito">
<meta property="og:title" content="${esc(titulo)}">
<meta property="og:description" content="${esc(texto)}">
<meta property="og:image" content="${esc(imagen)}">
<meta property="og:url" content="${esc(`${origin}/a/${id}`)}">
<meta name="twitter:card" content="summary_large_image">
${ld ? `<script type="application/ld+json">${ld}</script>` : ''}
<style>body{font-family:system-ui,sans-serif;max-width:560px;margin:0 auto;padding:20px;color:#1d1b19}img{max-width:100%;height:auto;border-radius:14px}.p{font-size:24px;font-weight:800}a.b{display:inline-block;background:#E0452C;color:#fff;padding:14px 22px;border-radius:12px;text-decoration:none;font-weight:700}</style>
<script src="/ir.js" data-destino="${esc(destino)}"></script>
</head><body>
${cuerpo}
<p><a class="b" href="${esc(destino)}">Ver en Pavito</a></p>
<p><a href="${esc(origin)}/">Más ropa usada en Venezuela en Pavito</a></p>
</body></html>`;
  return new Response(html, {
    status: estado,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'public, max-age=300',
      'x-content-type-options': 'nosniff',
      'x-frame-options': 'DENY',
      'content-security-policy': `default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; img-src 'self' ${SUPA}; base-uri 'none'`,
    },
  });
}
