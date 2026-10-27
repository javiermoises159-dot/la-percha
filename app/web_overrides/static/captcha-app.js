// Página para la app de Android: muestra Turnstile y devuelve el token a la app.
(function () {
  function enviar(t) { try { PavitoApp.postMessage(t || ''); } catch (e) {} }
  window.pavitoListo = function () {
    var k = new URLSearchParams(location.search).get('k') || '';
    try {
      turnstile.render('#w', { sitekey: k, callback: enviar,
        'error-callback': function () { enviar(''); }, 'timeout-callback': function () { enviar(''); } });
    } catch (e) { enviar(''); }
  };
})();
