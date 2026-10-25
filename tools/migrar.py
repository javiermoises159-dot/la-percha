#!/usr/bin/env python3
"""Aplica las migraciones nuevas de supabase/migrations a la base de datos.

Usa la API de gestión de Supabase con SUPABASE_ACCESS_TOKEN, sin contraseña
de la base de datos. Lleva la cuenta de lo aplicado en interno.migraciones.
Las migraciones 0001-0006 se pegaron a mano y se marcan como ya aplicadas.
"""
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

PROYECTO = "udhyuyokrxggdnnepbmr"
YA_APLICADAS = ["0001", "0002", "0003", "0004", "0005", "0006"]
CARPETA = pathlib.Path(__file__).resolve().parent.parent / "supabase" / "migrations"


def sql(query):
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if not token:
        sys.exit("Falta la variable SUPABASE_ACCESS_TOKEN en Codemagic.")
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{PROYECTO}/database/query",
        data=json.dumps({"query": query}).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json",
                 "User-Agent": "la-percha-migrar"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read() or b"[]")
    except urllib.error.HTTPError as e:
        detalle = e.read().decode(errors="replace")[:1500]
        if e.code in (401, 403):
            detalle += "\n-> El token no es válido o no tiene permiso de escritura en Database."
        raise RuntimeError(f"HTTP {e.code}: {detalle}") from None


def main():
    sembrar = ",".join(f"('{v}')" for v in YA_APLICADAS)
    sql(f"""
      create schema if not exists interno;
      revoke all on schema interno from public, anon, authenticated;
      create table if not exists interno.migraciones (
        version text primary key, aplicada timestamptz not null default now());
      insert into interno.migraciones (version) values {sembrar} on conflict do nothing;
    """)
    hechas = {f["version"] for f in sql("select version from interno.migraciones")}

    nuevas = [f for f in sorted(CARPETA.glob("*.sql")) if f.name.split("_")[0] not in hechas]
    if not nuevas:
        print("Base de datos al día: no hay migraciones nuevas.")
        return
    for f in nuevas:
        version = f.name.split("_")[0]
        print(f"Aplicando {f.name} ...")
        cuerpo = f.read_text(encoding="utf-8")
        try:
            # Todo en una transacción: o se aplica entera y se anota, o no cambia nada.
            sql(f"begin;\n{cuerpo}\n;insert into interno.migraciones (version) "
                f"values ('{version}');\ncommit;")
        except RuntimeError as e:
            print(f"=== ERROR EN {f.name} ===\n{e}")
            sys.exit(1)
        print(f"  OK {f.name}")
    print("Base de datos actualizada.")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as e:
        print(f"=== ERROR CONECTANDO CON SUPABASE ===\n{e}")
        sys.exit(1)
