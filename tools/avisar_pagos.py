#!/usr/bin/env python3
"""Manda el correo "¡Ya abrimos los pagos!" a todos los usuarios con correo confirmado.
Necesita SUPABASE_ACCESS_TOKEN y RESEND_API_KEY. Úsalo UNA vez, cuando pagosAbiertos = true.
Primero prueba con:  python3 tools/avisar_pagos.py --prueba tu@correo.com"""
import json, os, pathlib, sys, time, urllib.request
PROYECTO = "udhyuyokrxggdnnepbmr"
HTML = (pathlib.Path(__file__).resolve().parent.parent / "supabase/correos/pagos_abiertos.html").read_text(encoding="utf-8")
DE = "Pavito <hola@pavito.app>"
def post(url, cuerpo, token):
    r = urllib.request.Request(url, data=json.dumps(cuerpo).encode(), method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json", "User-Agent": "pavito-ci"})
    return json.load(urllib.request.urlopen(r, timeout=60))
sb, rs = os.environ.get("SUPABASE_ACCESS_TOKEN", ""), os.environ.get("RESEND_API_KEY", "")
if not rs: sys.exit("Falta RESEND_API_KEY")
if len(sys.argv) > 2 and sys.argv[1] == "--prueba":
    correos = [sys.argv[2]]
else:
    if not sb: sys.exit("Falta SUPABASE_ACCESS_TOKEN")
    filas = post(f"https://api.supabase.com/v1/projects/{PROYECTO}/database/query",
        {"query": "select email from auth.users where email_confirmed_at is not null and email is not null"}, sb)
    correos = [f["email"] for f in filas]
print(len(correos), "correos")
for c in correos:
    post("https://api.resend.com/emails", {"from": DE, "to": [c], "subject": "¡Ya abrimos los pagos en Pavito!", "html": HTML}, rs)
    time.sleep(0.6)
print("listo")
