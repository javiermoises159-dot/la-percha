#!/usr/bin/env python3
"""Escribe build/web/_headers (Cloudflare Pages) con las cabeceras de seguridad.

La política de contenido (CSP) solo deja ejecutar el código de la propia web: cada
<script> en línea de index.html se autoriza por su huella sha256, así que un script
inyectado no corre. También impide meter la web en un iframe (clickjacking)."""
import base64, hashlib, re, sys, pathlib

web = pathlib.Path(sys.argv[1])
html = (web / "index.html").read_text(encoding="utf-8")
hashes = []
for m in re.finditer(r"<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>", html, re.S):
    h = base64.b64encode(hashlib.sha256(m.group(1).encode("utf-8")).digest()).decode()
    hashes.append(f"'sha256-{h}'")
SUPA = "udhyuyokrxggdnnepbmr.supabase.co"
csp = "; ".join([
    "default-src 'self'",
    "script-src 'self' 'wasm-unsafe-eval' https://challenges.cloudflare.com " + " ".join(hashes),
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    "font-src 'self' data: https://fonts.gstatic.com",
    f"img-src 'self' data: blob: https://{SUPA}",
    f"connect-src 'self' blob: https://{SUPA} wss://{SUPA} https://fonts.gstatic.com https://fonts.googleapis.com https://challenges.cloudflare.com",
    "frame-src https://challenges.cloudflare.com",
    "worker-src 'self' blob:",
    "manifest-src 'self'",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "object-src 'none'",
    "upgrade-insecure-requests",
])
reglas = f"""/*
  Content-Security-Policy: {csp}
  Strict-Transport-Security: max-age=31536000; includeSubDomains
  X-Frame-Options: DENY
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: camera=(self), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()
  Cross-Origin-Opener-Policy: same-origin
"""
(web / "_headers").write_text(reglas, encoding="utf-8")
print(f"_headers escrito ({len(hashes)} scripts en línea autorizados)")
