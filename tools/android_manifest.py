#!/usr/bin/env python3
"""Ajusta el AndroidManifest que genera `flutter create`:
- vuelta a la app después de entrar con Google (com.pavito.pavito://login-callback)
- permiso de internet (la comprobación anti-bots y todo lo demás lo necesitan)."""
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
filtro = """            <intent-filter android:autoVerify="false">
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="com.pavito.pavito" android:host="login-callback"/>
            </intent-filter>
"""
if "login-callback" not in s:
    i = s.index("</activity>")
    s = s[:i] + filtro + "        " + s[i:]
if "android.permission.INTERNET" not in s:
    s = s.replace("<application", '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
open(p, "w", encoding="utf-8").write(s)
print("AndroidManifest ajustado")
