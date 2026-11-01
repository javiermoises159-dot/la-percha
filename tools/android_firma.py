#!/usr/bin/env python3
"""Hace que la compilación "release" de Android se firme con la llave de Pavito
(Codemagic la entrega en CM_KEYSTORE_PATH, CM_KEYSTORE_PASSWORD, CM_KEY_ALIAS, CM_KEY_PASSWORD).
Uso: python3 android_firma.py android/app"""
import os, re, sys
d = sys.argv[1]
kts, grd = os.path.join(d, "build.gradle.kts"), os.path.join(d, "build.gradle")
if os.path.exists(kts):
    s = open(kts, encoding="utf-8").read()
    if "CM_KEYSTORE_PATH" not in s:
        bloque = '''    signingConfigs {
        create("pavitoRelease") {
            storeFile = file(System.getenv("CM_KEYSTORE_PATH"))
            storePassword = System.getenv("CM_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("CM_KEY_ALIAS")
            keyPassword = System.getenv("CM_KEY_PASSWORD")
        }
    }
'''
        s, n = re.subn(r"(\n\s*buildTypes\s*\{)", "\n" + bloque + r"\1", s, count=1)
        s, m = re.subn(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)', 'signingConfig = signingConfigs.getByName("pavitoRelease")', s, count=1)
        if not (n and m):
            sys.exit("No pude preparar la firma en build.gradle.kts (cambió la plantilla de Flutter)")
        open(kts, "w", encoding="utf-8").write(s)
elif os.path.exists(grd):
    s = open(grd, encoding="utf-8").read()
    if "CM_KEYSTORE_PATH" not in s:
        bloque = '''    signingConfigs {
        pavitoRelease {
            storeFile file(System.getenv("CM_KEYSTORE_PATH"))
            storePassword System.getenv("CM_KEYSTORE_PASSWORD")
            keyAlias System.getenv("CM_KEY_ALIAS")
            keyPassword System.getenv("CM_KEY_PASSWORD")
        }
    }
'''
        s, n = re.subn(r"(\n\s*buildTypes\s*\{)", "\n" + bloque + r"\1", s, count=1)
        s, m = re.subn(r"signingConfig\s+signingConfigs\.debug", "signingConfig signingConfigs.pavitoRelease", s, count=1)
        if not (n and m):
            sys.exit("No pude preparar la firma en build.gradle (cambió la plantilla de Flutter)")
        open(grd, "w", encoding="utf-8").write(s)
else:
    sys.exit("No encuentro build.gradle(.kts)")
print("Firma de release preparada")
