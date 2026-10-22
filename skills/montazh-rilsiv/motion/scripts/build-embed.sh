#!/bin/bash
# Builds the website embed: dist-embed/motion-assets/ (motion-embed.js + fonts + chrome). Copy that folder into the site.
# usage: scripts/build-embed.sh [site-folder]   (with a site folder it also copies motion-assets/ there)
set -euo pipefail
# Windows: python3 is often a Microsoft Store stub; use the first Python that really runs, in UTF-8 mode
for _c in python py python3; do command -v "$_c" >/dev/null 2>&1 && "$_c" -c "import sys" >/dev/null 2>&1 && { PY="$_c"; break; }; done
python3() { command "${PY:-python}" "$@"; }; export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
cd "$(dirname "$0")/.."
python3 scripts/sync-brand.py >/dev/null   # their brand.json -> colours, fonts, elements
out=dist-embed/motion-assets
rm -rf dist-embed && mkdir -p "$out"
node_modules/.bin/esbuild src/player/embed.tsx --bundle --minify --format=iife --target=es2020 \
  --define:process.env.NODE_ENV='"production"' --outfile="$out/motion-embed.js" --log-level=warning
cp -r public/fonts "$out/"; [ -d public/chrome ] && cp -r public/chrome "$out/"
cp scripts/embed-demo.html dist-embed/index.html
du -sh "$out" "$out/motion-embed.js"
if [ -n "${1:-}" ]; then rm -rf "$1/motion-assets"; cp -r "$out" "$1/"; echo "copied to $1/motion-assets"; fi
