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
flutter pub get
flutter build web --release
