// Cloudflare Pages Function: /t/<usuario>  (la "tienda" de un vendedor)
// WhatsApp, Instagram y Telegram leen esta página y muestran foto, nombre y cuántas
// prendas tiene a la venta. Las personas pasan enseguida a la app con la tienda abierta.
const SUPA = 'https://udhyuyokrxggdnnepbmr.supabase.co';
// Clave pública ("publishable"): la misma que va dentro de la app.
const KEY = 'sb_publishable_PFt4DdXlWbQEvyEgP58BZQ_CKXaoHGG';

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

export async function onRequest({ params, request }) {
  const u = String(params.u || '').replace(/[^A-Za-z0-9_.]/g, '').slice(0, 20);
  const origin = new URL(request.url).origin;
  const destino = `${origin}/?t=${encodeURIComponent(u)}`;
  let titulo = 'Pavito · Vende lo que ya no usas';
  let texto = 'Compra y vende ropa usada en toda Venezuela con pago protegido.';
  let imagen = `${origin}/compartir.jpg`;
  let cuerpo = '<h1>Pavito</h1><p>Esta tienda no existe. Mira otras prendas en Pavito.</p>';
  let estado = 404;
  try {
    const h = { apikey: KEY, Authorization: `Bearer ${KEY}` };
    const pr = await fetch(`${SUPA}/rest/v1/profiles?select=id,username,city&username=ilike.${encodeURIComponent(u.replace(/_/g, '\\_'))}&limit=1`, { headers: h });
    const [p] = u.length >= 3 ? await pr.json() : [];
    if (p) {
      const lr = await fetch(`${SUPA}/rest/v1/listings?select=title,price,photos&status=eq.active&seller_id=eq.${p.id}&order=created_at.desc&limit=6`,
        { headers: { ...h, Prefer: 'count=exact' } });
      const ls = await lr.json();
      const total = Number((lr.headers.get('content-range') || '').split('/')[1]) || ls.length;
      const foto = ls.map((l) => Array.isArray(l.photos) && l.photos[0]).find((f) => f && String(f).startsWith(SUPA));
      if (foto) imagen = foto;
      titulo = `La tienda de @${p.username} en Pavito`;
      texto = total > 0
        ? `${total} ${total === 1 ? 'prenda' : 'prendas'} a la venta${p.city ? ` en ${p.city}` : ''}. Compra protegida: tu pago queda guardado hasta que lo recibes.`
        : `Mira lo que vende @${p.username}. Compra protegida en Pavito.`;
      estado = 200;
      const lista = ls.map((l) => `<li>${esc(l.title)} · $${esc(Number(l.price) % 1 ? Number(l.price).toFixed(2) : Number(l.price))}</li>`).join('');
      cuerpo = `<img src="${esc(imagen)}" alt="" width="320">
<h1>@${esc(p.username)}</h1>
<p>${esc(texto)}</p>
${lista ? `<ul>${lista}</ul>` : ''}`;
    }
  } catch (_) { /* si falla, se muestra la tarjeta genérica de Pavito */ }

  const html = `<!doctype html><html lang="es"><head><meta charset="utf-8">
<title>${esc(titulo)}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="${esc(texto)}">
<link rel="canonical" href="${esc(`${origin}/t/${u}`)}">
<meta property="og:type" content="profile">
<meta property="og:site_name" content="Pavito">
<meta property="og:title" content="${esc(titulo)}">
<meta property="og:description" content="${esc(texto)}">
<meta property="og:image" content="${esc(imagen)}">
<meta property="og:url" content="${esc(`${origin}/t/${u}`)}">
<meta name="twitter:card" content="summary_large_image">
<style>body{font-family:system-ui,sans-serif;max-width:560px;margin:0 auto;padding:20px;color:#1d1b19}img{max-width:100%;height:auto;border-radius:14px}a.b{display:inline-block;background:#E0452C;color:#fff;padding:14px 22px;border-radius:12px;text-decoration:none;font-weight:700}</style>
<script src="/ir.js" data-destino="${esc(destino)}"></script>
</head><body>
${cuerpo}
<p><a class="b" href="${esc(destino)}">Ver la tienda en Pavito</a></p>
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
