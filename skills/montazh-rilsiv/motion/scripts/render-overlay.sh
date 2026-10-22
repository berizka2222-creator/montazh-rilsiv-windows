#!/bin/bash
# Transparent element for a reel (reel-editor overlay card): VP9 WebM with alpha, 1080x1920, bg forced to "none".
# usage: scripts/render-overlay.sh <ElementId> '<props json>' <out.webm>
#   e.g. scripts/render-overlay.sh Counter '{"value":87,"suffix":"%","label":"окупність","duration":3}' ~/reels/<reel>/overlays/roi.webm
set -euo pipefail
# Windows: python3 is often a Microsoft Store stub; use the first Python that really runs, in UTF-8 mode
for _c in python py python3; do command -v "$_c" >/dev/null 2>&1 && "$_c" -c "import sys" >/dev/null 2>&1 && { PY="$_c"; break; }; done
python3() { command "${PY:-python}" "$@"; }; export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
cd "$(dirname "$0")/.."
python3 scripts/sync-brand.py >/dev/null   # their brand.json -> colours, fonts, elements
id="$1"; props="${2:-{\}}"; out="$3"
mkdir -p "$(dirname "$out")"
merged=$(node -e 'const p=JSON.parse(process.argv[1]);p.bg="none";console.log(JSON.stringify(p))' "$props")
npx remotion render "$id" "$out" --props="$merged" --codec=vp9 --image-format=png --pixel-format=yuva420p --log=error
echo "overlay: $out"
