// Pavito — activar notificaciones en este dispositivo (Web Push).
(function () {
  function claveBytes(b64) {
    const p = '='.repeat((4 - (b64.length % 4)) % 4);
    const s = atob((b64 + p).replace(/-/g, '+').replace(/_/g, '/'));
    return Uint8Array.from(s, (c) => c.charCodeAt(0));
  }
  function ios() { return /iphone|ipad|ipod/i.test(navigator.userAgent); }
  function instalada() { return window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true; }
  async function registro() {
    const reg = await navigator.serviceWorker.register('/push/sw.js', { scope: '/push/' });
    if (!reg.active) {
      const sw = reg.installing || reg.waiting;
      if (sw) await new Promise((r) => { sw.addEventListener('statechange', () => { if (sw.state === 'activated') r(); }); setTimeout(r, 5000); });
    }
    return reg;
  }
  window.pavitoPush = {
    // 'activo' | 'pregunta' | 'bloqueado' | 'instalar_ios' | 'no_soportado'
    estado: async function () {
      if (ios() && !instalada()) return 'instalar_ios';
      if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) return 'no_soportado';
      if (Notification.permission === 'denied') return 'bloqueado';
      if (Notification.permission !== 'granted') return 'pregunta';
      try {
        const reg = await navigator.serviceWorker.getRegistration('/push/');
        const sub = reg && await reg.pushManager.getSubscription();
        return sub ? 'activo' : 'pregunta';
      } catch (_) { return 'pregunta'; }
    },
    // Devuelve la suscripción en JSON, o {"error": "..."}.
    activar: async function (vapid) {
      try {
        const perm = await Notification.requestPermission();
        if (perm !== 'granted') return JSON.stringify({ error: perm });
        const reg = await registro();
        let sub = await reg.pushManager.getSubscription();
        if (!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: claveBytes(vapid) });
        return JSON.stringify(sub.toJSON());
      } catch (e) { return JSON.stringify({ error: String(e && e.message || e) }); }
    },
    desactivar: async function () {
      try {
        const reg = await navigator.serviceWorker.getRegistration('/push/');
        const sub = reg && await reg.pushManager.getSubscription();
        if (!sub) return '';
        const ep = sub.endpoint; await sub.unsubscribe(); return ep;
      } catch (_) { return ''; }
    },
  };
})();
