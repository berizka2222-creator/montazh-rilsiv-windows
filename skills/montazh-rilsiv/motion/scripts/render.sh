#!/bin/bash
# Finished video (brand background): H.264 MP4 for Instagram / ads.
# usage: scripts/render.sh <CompositionId> <props.json> <out.mp4>     (MotionReel for a whole motion reel)
set -euo pipefail
# Windows: python3 is often a Microsoft Store stub; use the first Python that really runs, in UTF-8 mode
for _c in python py python3; do command -v "$_c" >/dev/null 2>&1 && "$_c" -c "import sys" >/dev/null 2>&1 && { PY="$_c"; break; }; done
python3() { command "${PY:-python}" "$@"; }; export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
cd "$(dirname "$0")/.."
python3 scripts/sync-brand.py >/dev/null   # their brand.json -> colours, fonts, elements
id="$1"; props="$2"; out="$3"
mkdir -p "$(dirname "$out")"
npx remotion render "$id" "$out" --props="$props" --codec=h264 --crf=16 --image-format=jpeg --jpeg-quality=95 --log=error
echo "video: $out"
