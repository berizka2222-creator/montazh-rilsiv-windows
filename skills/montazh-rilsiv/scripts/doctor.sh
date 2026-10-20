#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/_win.sh"
# Check everything the reel editor needs and say plainly whether you can edit.
# Ends with one of: READY · READY WITH LIMITS (works, something optional is missing) · MISSING (fix before editing).
ok()   { printf '  ✅ %s\n' "$1"; }
warn() { printf '  ⚠️  %s\n     %s\n' "$1" "$2"; LIMITS=1; }
no()   { printf '  ❌ %s\n     fix: %s\n' "$1" "$2"; MISSING=1; }
MISSING=0; LIMITS=0
echo "Reel editor check"

command -v ffmpeg >/dev/null && ok "ffmpeg" || no "ffmpeg" "winget install -e --id Gyan.FFmpeg"
command -v node >/dev/null && ok "Node.js $(node -v)" || no "Node.js" "winget install -e --id OpenJS.NodeJS.LTS"
[ -n "${PY:-}" ] && ok "Python 3 ($PY)" || no "Python 3" "winget install -e --id Python.Python.3.12 --scope user"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ok "Windows (Git Bash)";; *) warn "not Windows" "this is the Windows version of the skill: on a Mac install montazh-rilsiv instead";; esac

HF=0; for d in ~/.claude/skills/hyperframes ~/.agents/skills/hyperframes; do [ -d "$d" ] && HF=1; done   # either location is fine
[ "$HF" = 1 ] && ok "HyperFrames skills" || no "HyperFrames skills" "npx skills add heygen-com/hyperframes"

ENG="$(cd "$(dirname "$0")/.." && pwd)/engine"
if [ -s "$ENG/gsap.min.js" ] && [ -s "$ENG/sfx/whoosh.wav" ]; then ok "reel template engine"
else bash "$(dirname "$0")/setup_engine.sh" >/dev/null 2>&1 && ok "reel template engine (just set up)" || no "reel template engine" "bash scripts/setup_engine.sh"; fi

ENVF="$HOME/.config/reels/.env"
grep -q '^ELEVENLABS_API_KEY=sk_' "$ENVF" 2>/dev/null && ok "ElevenLabs key (speech recognition)" \
  || no "ElevenLabs key" "speech recognition runs only on ElevenLabs Scribe: connect it (SKILL.md, «Connecting ElevenLabs Scribe»)"

command -v deepFilter >/dev/null && ok "noise removal (DeepFilterNet)" \
  || warn "DeepFilterNet not installed" "background noise removal falls back to ffmpeg's weaker filter. Install: uv tool install deepfilternet"

HOME_DIR="${REELS_HOME:-$HOME/reels}"
if [ -f "$HOME_DIR/brand.json" ]; then
  ok "brand file ($HOME_DIR)"
  # every font the brand names must exist, or captions silently fall back to a system font
  python3 - "$(wp "$HOME_DIR/brand.json")" <<'PY' || LIMITS=1
import json, os, sys
b = json.load(open(sys.argv[1])); bad = 0
for role, f in (b.get("fonts") or {}).items():
    p = f.get("file")
    if p and not os.path.exists(os.path.expanduser(p)):
        print(f"  ⚠️  {role} font file missing: {p}\n     captions/titles will use a fallback font until it's in place"); bad = 1
    elif p: print(f"  ✅ {role} font ({f.get('family')})")
sys.exit(bad)
PY
  if python3 -c "import json,sys;sys.exit(0 if json.load(open(sys.argv[1])).get('capcut') else 1)" "$(wp "$HOME_DIR/brand.json")"; then
    [ -d "${CAPCUT_SKILLS_DIR:-$HOME/reels/capcut/plugins/codex/skills}/capcut-stdraft-builder" ] && ok "CapCut helper scripts" \
      || warn "CapCut helper scripts not found" "the MP4 still works; for CapCut see references/capcut.md step 3"
    claude mcp list 2>/dev/null | grep -q capcut_creation && ok "CapCut connector added" \
      || warn "CapCut connector not added" "the MP4 still works; for CapCut see references/capcut.md step 2"
  fi
else
  echo "  ➖ no brand file yet - the setup interview will make one"
fi
echo "  ℹ️  the review page needs Claude Code's Artifact tools; Claude checks this when you start an edit (chat review otherwise)"

# text widths are measured in the real fonts (fontTools in ~/reels/.venv), so wide display fonts never spill out of the frame
VENV="${REELS_HOME:-$HOME/reels}/.venv"; VPY="$VENV/Scripts/python.exe"
if [ -x "$VPY" ] && "$VPY" -c "import fontTools, brotli, cv2" 2>/dev/null; then ok "font measuring + face finding (fontTools, OpenCV)"
elif { [ -x "$VPY" ] || python3 -m venv "$(wp "$VENV")" >/dev/null 2>&1; } && "$VPY" -m pip install -q fonttools brotli Pillow opencv-python-headless >/dev/null 2>&1; then ok "font measuring + face finding installed in $VENV"
else warn "fontTools/OpenCV not installed" "text sizes fall back to an estimate and graphics use the default face zone; run: python -m venv ~/reels/.venv && ~/reels/.venv/Scripts/python.exe -m pip install fonttools brotli Pillow opencv-python-headless"; fi

FREE_GB=$(df -Pk "$HOME" | awk 'NR==2{print int($4/1048576)}')
[ "$FREE_GB" -ge 10 ] && ok "${FREE_GB} GB free disk" || no "only ${FREE_GB} GB free disk" "free up 10+ GB (35+ GB for 4K exports)"

if [ "$MISSING" = 1 ]; then echo "MISSING: fix the ❌ items, then run this again."; exit 1
elif [ "$LIMITS" = 1 ]; then echo "READY WITH LIMITS: you can edit; the ⚠️ items reduce quality or skip an optional extra."
else echo "READY"; fi
