#!/usr/bin/env bash
# Compila la web y la publica en GitHub Pages (rama gh-pages):
# https://javiermoises159-dot.github.io/la-percha/
set -e
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
cp -r "$RAIZ/app" "$TMP/app" && cd "$TMP/app"
rm -rf build .dart_tool
flutter create --platforms=web --org com.lapercha --project-name la_percha . >/dev/null
for f in Icon-192 Icon-512 Icon-maskable-192 Icon-maskable-512 apple-touch-icon; do
  cp "web_overrides/icons/$f.png" web/icons/
done
cp web_overrides/icons/favicon.png web/favicon.png
python3 web_overrides/patch_web.py web
flutter pub get >/dev/null
flutter build web --release --base-href /la-percha/
touch build/web/.nojekyll
cd build/web
git init -q -b gh-pages
git add -A
git -c user.name=la-percha -c user.email=noreply@github.com commit -q -m "Publicar web"
git push -q -f https://github.com/javiermoises159-dot/la-percha gh-pages
echo "Publicado en https://javiermoises159-dot.github.io/la-percha/"
