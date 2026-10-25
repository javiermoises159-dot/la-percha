#!/usr/bin/env bash
# Compila La Percha para la web. Lo usa Cloudflare Pages (o cualquier hosting).
set -e
if [ ! -d "$HOME/flutter" ]; then
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter"
fi
export PATH="$HOME/flutter/bin:$PATH"
cd app
flutter config --no-analytics >/dev/null 2>&1 || true
flutter create --platforms=web --org com.lapercha --project-name la_percha .

# Iconos, pantalla de carga y datos de la página web
cp web_overrides/icons/Icon-192.png web/icons/Icon-192.png
cp web_overrides/icons/Icon-512.png web/icons/Icon-512.png
cp web_overrides/icons/Icon-maskable-192.png web/icons/Icon-maskable-192.png
cp web_overrides/icons/Icon-maskable-512.png web/icons/Icon-maskable-512.png
cp web_overrides/icons/favicon.png web/favicon.png
cp web_overrides/icons/apple-touch-icon.png web/icons/apple-touch-icon.png
python3 web_overrides/patch_web.py web

flutter pub get
flutter build web --release

# Cabeceras de seguridad (Cloudflare Pages las lee de este archivo)
cp web_overrides/_headers build/web/_headers
