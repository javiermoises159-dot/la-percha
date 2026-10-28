#!/usr/bin/env python3
"""Sube los correos de Pavito (confirmar cuenta y recuperar contraseña) a Supabase Auth.
Usa SUPABASE_ACCESS_TOKEN (variable segura de Codemagic). Nunca imprime el token."""
import json, os, pathlib, sys, urllib.error, urllib.request
PROYECTO = "udhyuyokrxggdnnepbmr"
R = pathlib.Path(__file__).resolve().parent.parent / "supabase/correos"
token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
if not token:
    sys.exit("Falta SUPABASE_ACCESS_TOKEN")
cuerpo = {
    "mailer_subjects_confirmation": "Confirma tu correo en Pavito",
    "mailer_templates_confirmation_content": (R / "confirmacion.html").read_text(encoding="utf-8"),
    "mailer_subjects_recovery": "Cambia tu contraseña de Pavito",
    "mailer_templates_recovery_content": (R / "recuperar.html").read_text(encoding="utf-8"),
}
req = urllib.request.Request(
    f"https://api.supabase.com/v1/projects/{PROYECTO}/config/auth",
    data=json.dumps(cuerpo).encode(), method="PATCH",
    headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json", "User-Agent": "pavito-ci"})
try:
    with urllib.request.urlopen(req, timeout=60) as r:
        print("Correos de Pavito actualizados (HTTP", r.status, ")")
except urllib.error.HTTPError as e:
    sys.exit(f"Error {e.code}: {e.read().decode()[:300]}")
