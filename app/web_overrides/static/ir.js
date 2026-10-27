// Páginas de anuncio (/a/ID): las personas pasan directo a la app; los buscadores
// (Google y compañía) se quedan leyendo la ficha del anuncio.
(function () {
  var s = document.currentScript, d = s && s.getAttribute('data-destino');
  if (!d || d.indexOf(location.origin + '/') !== 0) return;
  if (/bot|crawl|spider|slurp|facebookexternalhit|whatsapp|telegram|preview|lighthouse/i.test(navigator.userAgent)) return;
  location.replace(d);
})();
