#!/usr/bin/env bash
# Whole-reel test of the skill, the way Claude runs it for a student: setup, cut, captions, graphics, draft render, QA, delivery.
# Runs on Windows (GitHub Actions, Git Bash) and on a Mac (to make the fixtures).
#   SKILL      the installed skill folder (default ~/.claude/skills/montazh-rilsiv)
#   REELS_HOME the workspace (a test one, never the real ~/reels)
#   FIX        tools/ci/fixture (speech.m4a, edl + transcripts)
#   MAKE_FIXTURES=1  transcribe for real with ElevenLabs and save the transcripts into FIX (Mac only)
# Every step is timed and logged; the run continues after a failed step so one report shows everything.
set -uo pipefail
SKILL="${SKILL:-$HOME/.claude/skills/montazh-rilsiv}"; S="$SKILL/scripts"
FIX="$(cd "$FIX" && pwd)"; OUTD="${OUTD:-$PWD/test-out}"; mkdir -p "$OUTD"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WIN=1; source "$S/_win.sh";; *) WIN=0; wp() { printf %s "$1"; };; esac
REEL="$REELS_HOME/2026-10-20-тест рілс"; mkdir -p "$REEL" "$REELS_HOME/fonts"
REPORT="$OUTD/report.md"; : > "$REPORT"; FAILS=0
step() {   # step "<name>" cmd...   -> logs/<n>.log, a row in report.md
  local name="$1"; shift; local n; n=$(printf %02d $(( $(grep -c '^|' "$REPORT") - 1 )))
  local t0; t0=$(date +%s); echo "::group::$n $name"
  "$@" > "$OUTD/$n.log" 2>&1; local rc=$?
  cat "$OUTD/$n.log"; echo "::endgroup::"
  local dt=$(( $(date +%s) - t0 ))
  if [ $rc = 0 ]; then echo "| ✅ | $name | ${dt}s |" >> "$REPORT"
  else echo "| ❌ | $name | ${dt}s · exit $rc · $(tail -3 "$OUTD/$n.log" | tr '\n|' '  ' | cut -c1-300) |" >> "$REPORT"; FAILS=$((FAILS + 1)); fi
  return $rc
}
py() { python3 "$@"; }

# ---- the test brand: Google fonts with Ukrainian letters (the real brand fonts are licensed, not in a public repo) ----
fonts() {
  # curl.exe can't write into a Cyrillic folder on an English Windows: download from inside it
  ( cd "$REELS_HOME/fonts" && curl -fsSL -o Montserrat.ttf "https://raw.githubusercontent.com/google/fonts/main/ofl/montserrat/Montserrat%5Bwght%5D.ttf" \
    && curl -fsSL -o Lora-Italic.ttf "https://raw.githubusercontent.com/google/fonts/main/ofl/lora/Lora-Italic%5Bwght%5D.ttf" )
  [ -s "$REELS_HOME/fonts/Montserrat.ttf" ] && [ -s "$REELS_HOME/fonts/Lora-Italic.ttf" ] || return 1
  local F; F="$(wp "$REELS_HOME/fonts")"; local DELIVER="~/Videos/Reels"; [ "$WIN" = 1 ] || DELIVER="$(wp "$REELS_HOME/delivered")"
  cat > "$REELS_HOME/brand.json" <<JSON
{"name": "Тест", "language": "uk", "resolution": [1080, 1920], "pacing": "natural", "graphics": "balanced", "max_seconds": 90,
 "colors": {"main": "#0D1A0F", "pop": "#FFC3CC", "light": "#FFFFFF", "soft": "#D2DB76", "deep": "#152A18",
            "caption": "#FFFFFF", "caption_accent": "#FFC3CC", "caption_accent_2": "#D2DB76"},
 "title_outline": null, "capcut": false, "sfx": "subtle", "deliver_dir": "$DELIVER", "grade": null, "covers": false,
 "captions": {"mode": "word", "case": "lower", "size": 84, "y": 1250, "pair_short": 3},
 "fonts": {"head": {"family": "Montserrat", "file": "$F/Montserrat.ttf", "weight": 700},
           "body": {"family": "Montserrat", "file": "$F/Montserrat.ttf", "weight": 400},
           "accent": {"family": "Lora", "file": "$F/Lora-Italic.ttf", "weight": 400, "style": "italic"}},
 "glass": true, "title_glass": false, "title_color": "#FFFFFF", "title_y": 1120, "title_max_px": 130, "cta_px": 62}
JSON
  printf '# Тест\n## Rules\n- тестовий бренд\n' > "$REELS_HOME/brand.md"
}
# a talking-head stand-in: a photo with a face (OpenCV's own sample) + the generated Ukrainian speech
clip() {
  ( cd "$OUTD" && curl -fsSL -o face.jpg "https://raw.githubusercontent.com/opencv/opencv/4.x/samples/data/messi5.jpg" )
  ffmpeg -v error -y -loop 1 -framerate 30 -i "$OUTD/face.jpg" -i "$FIX/speech.m4a" \
    -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,zoompan=z='1+0.0004*on':d=1:s=1080x1920:fps=30" \
    -shortest -c:v libx264 -pix_fmt yuv420p -preset veryfast -c:a aac "$REEL/raw.mp4"
}
transcript() {   # transcript <src> <out> <fixture-name>
  if [ "${MAKE_FIXTURES:-}" = 1 ]; then py "$S/transcribe.py" "$1" "$2" && cp "$2" "$FIX/$3.json"; else cp "$FIX/$3.json" "$2"; fi
}
mock_scribe() {   # CI has no ElevenLabs key: the transcriber hands back the fixture made on the Mac (raw clip vs cut reel)
  [ "${MAKE_FIXTURES:-}" = 1 ] && return 0
  py - "$S/transcribe.py" "$(wp "$FIX")" <<'PY'
import sys; p, fix = sys.argv[1], sys.argv[2]; t = open(p, encoding="utf-8").read()
hook = ("import shutil as _sh\nif __import__('os').environ.get('REEL_TEST_FIXTURES', '1') and len(sys.argv) > 2:\n"
        f"    _sh.copy(r'{fix}/' + ('raw' if 'raw' in Path(sys.argv[1]).name else 'master') + '.json', sys.argv[2]); print('transcribed with TEST FIXTURE'); sys.exit(0)\n")
t = t.replace("src, out = Path(sys.argv[1])", hook + "src, out = Path(sys.argv[1])", 1)
open(p, "w", encoding="utf-8").write(t)
PY
}
edl() {
  if [ "${MAKE_FIXTURES:-}" = 1 ]; then py - "$(wp "$REEL")" <<'PY'
import json, sys; from pathlib import Path
r = Path(sys.argv[1]); w = json.load(open(r / "transcript.json", encoding="utf-8"))
# keep everything from the first word to the last; the «ем» goes via tighten.py like on a real reel
json.dump({"source": "raw.mp4", "audio": "voice.wav", "keep": [[max(0, w[0]["start"] - 0.15), w[-1]["end"] + 0.35]]}, open(r / "edl.json", "w"))
PY
    cp "$REEL/edl.json" "$FIX/edl.json"
  else cp "$FIX/edl.json" "$REEL/edl.json"; fi
}
cards() {   # the graphics a real edit would add: hook title, list, catalog motions, text behind the person, camera move, CTA
  py - "$(wp "$REEL")" <<'PY'
import json, sys; from pathlib import Path
r = Path(sys.argv[1]); e = json.load(open(r / "edit.json", encoding="utf-8")); w = json.load(open(r / "master_transcript.json", encoding="utf-8"))
def at(word, k=0):
    hits = [x for x in w if word in x["text"].lower()]
    return hits[min(k, len(hits) - 1)] if hits else w[min(len(w) - 1, 3)]
end = w[-1]["end"]
for c in e["captions"]:
    for x in c.get("words", []):
        if x["text"].lower().strip(".,!?:") in ("клієнтів", "профіль", "першою"): x["accent"] = True
e["cards"] += [
  {"type": "title", "text": "ДЕ ВЗЯТИ / ПЕРШИХ / КЛІЄНТІВ?", "start": 0.1, "end": 3.6, "id": "hook", "sfx": {"name": "whoosh", "db": -12}},
  {"type": "list", "title": "три кроки", "rows": ["упакуй профіль", "запусти рекламу", "пиши першою"], "start": at("перше")["start"], "end": at("першою")["end"] + 0.4, "id": "steps"},
  {"type": "motion", "name": "count-up", "vars": {"start": 0, "end": 20, "prefix": "$", "suffix": ""}, "box": [140, 260, 800, 320], "start": at("двадцять")["start"] - 0.2, "end": at("доларів")["end"] + 0.8, "id": "usd"},
  {"type": "motion", "name": "per-word-rise", "vars": {"text": "пиши людям першою"}, "layout": "bubble", "place": "chest", "start": at("третє")["start"], "end": at("першою")["end"] + 0.3, "id": "rise"},
  {"type": "bigtext", "text": "клієнти", "y": 300, "behind": True, "start": at("сьогодні")["start"], "end": at("сьогодні")["start"] + 1.4, "id": "behind"},
  {"type": "camera", "move": "whip", "start": at("підписуйся")["start"], "end": at("підписуйся")["start"] + 0.8, "id": "whip"},
  {"type": "cta", "text": "підписуйся", "start": at("підписуйся")["start"], "end": end, "id": "cta"},
]
if (r / "overlays/brand-Counter-test.webm").exists():   # a transparent Remotion element from the motion library (setup_motion.sh)
    a = at("клієнтів", 1)["start"]
    e["cards"].append({"type": "overlay", "brand": "Counter", "src": "overlays/brand-Counter-test.webm", "start": a, "end": a + 2.0, "id": "remotion"})
json.dump(e, open(r / "edit.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(len(e["cards"]), "cards,", len(e["captions"]), "captions")
PY
}
remotion_overlay() {   # the motion library (~/motion) renders a transparent VP9 element for the reel
  bash "${MOTION_HOME:-$HOME/motion}/scripts/render-overlay.sh" Counter '{"value":20,"suffix":"$","label":"за день","duration":2,"place":"top"}' \
    "$REEL/overlays/brand-Counter-test.webm" && ffprobe -v error -show_entries stream=codec_name:stream_tags=alpha_mode -of compact "$REEL/overlays/brand-Counter-test.webm"
}
frames() {   # stills from the draft for the report: the hook, the list, the motions, the text behind
  for t in 1.5 3 6 9 12 15; do ffmpeg -v error -y -ss "$t" -i "$REEL/draft.mp4" -frames:v 1 "$OUTD/frame_$t.jpg"; done
  ffmpeg -v error -y -i "$REEL/draft.mp4" -vf "fps=1/2,scale=180:-2,tile=6x2" -frames:v 1 "$OUTD/contact.jpg"
}
queue() {
  py "$S/render_queue.py" add "$(wp "$REEL")" --preview && py "$S/render_queue.py" status \
  && rm -f "$REELS_HOME/.queue/jobs.jsonl" && py "$S/render_queue.py" run   # the lock + empty-queue path (no second render)
}
review_export() {
  py - "$(wp "$REEL")" <<'PY'
import json, sys; from pathlib import Path
r = Path(sys.argv[1]); k = json.load(open(r / "edl.json"))["keep"]
json.dump({"title": "Тест рілс", "proposedCut": k, "accentWords": ["клієнтів"], "cards": []}, open(r / "proposal.json", "w", encoding="utf-8"), ensure_ascii=False)
PY
  py "$S/review_sync.py" export "$(wp "$REEL")" "$(wp "$REEL/proposal.json")" "$(wp "$REEL/review_out")" && ls "$REEL/review_out"
}

echo "| | step | time |" > "$REPORT"; echo "|---|---|---|" >> "$REPORT"
step "test brand + fonts"            fonts
step "test clip (face photo + speech)" clip
step "doctor.sh"                     bash "$S/doctor.sh"
step "setup_engine.sh (86 motions)"  bash "$S/setup_engine.sh"
step "setup_motion.sh (Remotion)"    bash "$S/setup_motion.sh"
mock_scribe
step "transcribe raw"                transcript "$(wp "$REEL/raw.mp4")" "$(wp "$REEL/transcript.json")" raw
step "clean_audio.sh"                bash "$S/clean_audio.sh" "$REEL/raw.mp4" "$REEL/voice.wav"
step "face_box.py (OpenCV)"          py "$S/face_box.py" "$(wp "$REEL")"
step "edl.json"                      edl
step "review_sync export (page data)" review_export
step "tighten.py"                    py "$S/tighten.py" "$(wp "$REEL")"
step "snap_joins.py"                 py "$S/snap_joins.py" "$(wp "$REEL")"
step "cut.py (preview)"              env REEL_PREVIEW=1 python3 "$S/cut.py" "$(wp "$REEL")"
step "transcribe master"             transcript "$(wp "$REEL/master.mp4")" "$(wp "$REEL/master_transcript.json")" master
step "auto_edit.py"                  py "$S/auto_edit.py" "$(wp "$REEL")"
step "Remotion overlay element"      remotion_overlay
step "graphics cards"                cards
step "motions.py ideas"              py "$S/motions.py" ideas "$(wp "$REEL")"
step "precheck.py"                   py "$S/precheck.py" "$(wp "$REEL")"
step "test_motions.py (2 motions)"   py "$S/test_motions.py" "$(wp "$REEL")" "$(wp "$OUTD/motions")" --names count-up,per-word-rise --workers 1
step "render draft (incl. cut-out behind)" env REEL_DRAFT=1 REEL_PREVIEW=1 REEL_WORKERS=2 bash "$S/render.sh" "$REEL"
qa_draft() {   # the draft is 540x960 on purpose and only the final gets the -14 LUFS pass, so size and loudness may FAIL here
  local o; o="$(REEL_PREVIEW=1 python3 "$S/qa.py" "$(wp "$REEL")" draft.mp4 2>&1)"; echo "$o"
  local bad; bad="$(printf '%s\n' "$o" | grep '^FAIL' | grep -vE '^FAIL: (size|loudness|size, loudness)$')"; [ -z "$bad" ] || return 1
  printf '%s\n' "$o" | grep -qE '^(PASS|FAIL)'
}
step "qa.py on draft"                qa_draft
step "frames from draft"             frames
step "render_queue (locks)"          queue
step "deliver.sh"                    bash "$S/deliver.sh" "$REEL/draft.mp4" "Тест рілс"
step "motions.py log"                py "$S/motions.py" log "$(wp "$REEL")"

# ---- 2026-10-24 features: faster cut (cache), captions off under every effect, split framed on the face, real UIs in their
# own colours, a font per hook line + line spacing, the step-2 video with the effects (graphics_preview.py), page proxy ----
cut_cache() {   # the same cut twice: the second call keeps master.mp4
  local o; o="$(REEL_PREVIEW=1 python3 "$S/cut.py" "$(wp "$REEL")" 2>&1)"; echo "$o"; printf '%s\n' "$o" | grep -q "up to date"
}
sync_check() {  # picture and sound of the cut are the same length (per-span inputs on whole frames)
  py - "$(wp "$REEL/master.mp4")" <<'PY'
import subprocess, sys
d = {l.split(",")[0]: float(l.split(",")[1]) for l in subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,duration",
     "-of", "csv=p=0", sys.argv[1]], capture_output=True, text=True).stdout.split() if "," in l}
print(d); sys.exit(0 if abs(d["video"] - d["audio"]) < 0.1 else 1)
PY
}
page_proxy() {
  bash "$S/page_proxy.sh" "$REEL/raw.mp4" "$REEL/voice.wav" "$OUTD/src.mp4" && py - "$(wp "$OUTD/src.mp4")" <<'PY'
import os, subprocess, sys
wh = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", sys.argv[1]],
                    capture_output=True, text=True).stdout.strip()
mb = os.path.getsize(sys.argv[1]) / 1048576; print(wh, f"{mb:.1f} MB"); sys.exit(0 if wh == "540,960" and mb < 19.5 else 1)
PY
}
TREEL="$REELS_HOME/2026-10-24-тест нове"
today_cards() {   # a copy of the reel with today's card kinds
  rm -rf "$TREEL"; mkdir -p "$TREEL"; cp -R "$REEL"/. "$TREEL"/; rm -rf "$TREEL/proj" "$TREEL/cutouts" "$TREEL/.cache"
  py - "$(wp "$TREEL")" "$(wp "$REELS_HOME/fonts")" <<'PY'
import json, sys; from pathlib import Path
r, F = Path(sys.argv[1]), sys.argv[2]; e = json.load(open(r / "edit.json", encoding="utf-8"))
end = json.load(open(r / "master_transcript.json", encoding="utf-8"))[-1]["end"]
e["caption_style"] = "caption-neon-accent"
e["text_look"] = {"hook": {"lh": 120, "lines": [{"c1": "#FFC3CC"}, {"ff": {"family": "Lora", "file": F + "/Lora-Italic.ttf", "style": "italic"}}]}}
e["cards"] = [
  {"type": "title", "text": "ДЕ ВЗЯТИ / ПЕРШИХ / КЛІЄНТІВ?", "start": 0.1, "end": 3.6, "id": "hook"},
  {"type": "split", "title": "три кроки", "rows": ["упакуй профіль", "запусти рекламу", "пиши першою"], "start": 4.0, "end": 8.0, "id": "split"},
  {"type": "motion", "name": "message-thread-reveal", "layout": "dim", "full": True, "quiet": True, "start": 8.5, "end": 11.5, "id": "chat",
   "vars": {"contactName": "Клієнт", "questionMessage": "Скільки коштує таргет?", "teaserMessage": "Ось прайс"}},
  {"type": "head", "look": "circle", "words": ["пиши", "першою"], "start": 12.0, "end": min(14.0, end), "id": "circle"},
  {"type": "fx", "fx": "spotlight", "text": "КЛІЄНТИ", "start": 14.2, "end": min(15.8, end - 0.2), "id": "fx_spot"},
  {"type": "fx", "fx": "orbit", "start": 14.6, "end": min(16.0, end - 0.1), "id": "fx_orbit"},
]
json.dump(e, open(r / "edit.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1); print(len(e["cards"]), "cards")
PY
}
today_render() {
  local o; o="$(REEL_DRAFT=1 REEL_PREVIEW=1 REEL_WORKERS=2 bash "$S/render.sh" "$TREEL" 2>&1)"; local rc=$?; echo "$o" | tail -20; [ $rc = 0 ] || return $rc
  ! printf '%s\n' "$o" | grep -E "Traceback|Error:"
}
today_check() {   # what the build wrote: each of today's fixes is in the page the renderer saw
  py - "$(wp "$TREEL")" <<'PY'
import re, sys; from pathlib import Path
r = Path(sys.argv[1]); idx = (r / "proj/index.html").read_text(encoding="utf-8"); bad = 0
def ok(name, cond): global bad; bad += not cond; print(("ok  " if cond else "BAD ") + name)
cap = next((p for p in (r / "proj/compositions").rglob("caption-neon-accent.html")), None)
ok("captions hide under the cards (style timeline gets the spans)", bool(cap) and "autoAlpha:0" in cap.read_text(encoding="utf-8"))
ok("split: the video slides to the face", bool(re.search(r'tl\.to\("#k\d+v",\{y:-\d+', idx)))
chat = next((p for p in (r / "proj/compositions").rglob("message-thread-reveal.html")), None)
ok("chat keeps its own look (no brand font / recolour)", bool(chat) and "BrandSans" not in chat.read_text(encoding="utf-8"))
ok("chat dims with neutral black", "rgba(0,0,0,0.70)" in idx)
ok("hook line 2 in its own font", "Lora-hk1" in idx)
ok("hook line spacing 120%", "line-height:1.056" in idx)
ok("Vibha's effects drawn into the draft video (master_fx_540.mp4)", (r / "master_fx_540.mp4").exists() and (r / "proj/master.mp4").stat().st_size == (r / "master_fx_540.mp4").stat().st_size)
sys.exit(1 if bad else 0)
PY
}
today_frames() { for t in 2 6 10 13 14.8; do ffmpeg -v error -y -ss "$t" -i "$TREEL/draft.mp4" -frames:v 1 "$OUTD/today_$t.jpg"; done; cp -f "$TREEL/draft.mp4" "$OUTD/today_draft.mp4"; }
step2_video() {   # the step-2 video with the effects, from the page's decisions: import (sounds, a font per line, a «+» effect) + cut + render
  rm -rf "$TREEL/proj"
  py - "$(wp "$TREEL")" <<'PY'
import json, sys; from pathlib import Path
r = Path(sys.argv[1]); rj = json.load(open(r / "review_out/reel.json", encoding="utf-8"))
rj["board"] = [{"id": "hook", "type": "title", "kind": "Хук", "text": "ТВІЙ / ХУК", "w0": 0, "place": [90, 1000, 900, 320], "sfx": {"name": "whoosh", "db": -12}}]
json.dump(rj, open(r / "review_reel.json", "w", encoding="utf-8"), ensure_ascii=False)
json.dump({"hook": "ДЕ ВЗЯТИ / ПЕРШИХ", "board": {}, "graphicsRequest": {"cutHash": "t"},
           "look": {"hook": {"lh": 110, "lines": [{}, {"ff": {"family": "Lora", "gf": "Lora:ital,wght@1,400", "weight": 400, "style": "italic"}}]}},
           "effects": [{"id": "ef1", "w0": 5, "at": 2.0, "dur": 3, "text": "№42 count-up: цифра рахує", "files": []}],
           "sfxSwap": {"ef1": "pop", "hook": "swish"}}, open(r / "review.json", "w", encoding="utf-8"), ensure_ascii=False)
PY
  local o; o="$(python3 "$S/graphics_preview.py" "$(wp "$TREEL")" "$(wp "$TREEL/review.json")" 2>&1)"; local rc=$?; echo "$o" | tail -25; [ $rc = 0 ] || return $rc
  printf '%s\n' "$o" | grep -q "| sound: pop" && printf '%s\n' "$o" | grep -q "HOOK LINE 2 FONT: Lora" && [ -s "$TREEL/gfx_preview.mp4" ] \
    && grep -q '"rendered": true' "$TREEL/gfx_preview.json"
}
precheck_cache() { local o; o="$(python3 "$S/precheck.py" "$(wp "$TREEL")" 2>&1)"; echo "$o"; printf '%s\n' "$o" | grep -q "not transcribing again"; }
step "cut.py cache (same cut = no re-cut)" cut_cache
step "cut: picture and sound in sync" sync_check
step "page_proxy.sh (540p, under 20 MB)" page_proxy
step "setup_fx.sh (Vibha's effects: Python 3.12 + MediaPipe)" bash "$S/setup_fx.sh"
fx_previews() { python3 "$S/fx_pass.py" "$(wp "$REEL")" --previews --names spotlight,orbit,the-bill,tier-list,apple-toggles && ls "$REELS_HOME/menu"/fx-*.mp4; }
step "fx menu clips (5 of 42)"       fx_previews
step "today: cards (split, chat, head, caption style, hook fonts, Vibha fx)" today_cards
step "today: render draft"           today_render
step "today: fixes in the build"     today_check
step "today: frames"                 today_frames
step "step-2 video (graphics_preview.py)" step2_video
step "precheck cache"                precheck_cache
cp -f "$TREEL/gfx_preview.mp4" "$OUTD/gfx_preview.mp4" 2>/dev/null

# ---- «подачі голови» (scripts/heads.py): a second reel made of the same cut, its video shrinks into shapes on brand colours ----
HREEL="$REELS_HOME/2026-10-20-подачі голови"
heads_links() {   # the scripts link files with os.symlink, which needs admin rights on a student's PC: _win.py makes a hard link
  py - "$(wp "$S")" "$(wp "$REEL")" "$(wp "$HREEL")" <<'PY'   # (file) or a junction (folder) instead, never a real symlink
import os, sys; from pathlib import Path
sys.path.insert(0, sys.argv[1])
try: import _win  # noqa: F401  the same layer every script imports (Windows version only)
except ImportError: pass
r, h = Path(sys.argv[2]), Path(sys.argv[3]); h.mkdir(parents=True, exist_ok=True)
(r / "overlays").mkdir(exist_ok=True); (r / "overlays" / "probe.txt").write_text("тест", encoding="utf-8")
for f in ("master.mp4", "master_540.mp4", "master_transcript.json", "face.json", "overlays"):
    if (r / f).exists() and not (h / f).exists(): os.symlink(r / f, h / f)
for f in ("master.mp4", "master_transcript.json", "overlays"):
    p = h / f; assert p.exists() and (os.name != "nt" or not p.is_symlink()), f"{f}: missing or a real symlink"
    print(f"{f}: {'folder ' + str(sorted(x.name for x in p.iterdir())) if p.is_dir() else str(p.stat().st_size) + ' bytes, links ' + str(p.stat().st_nlink)}")
assert (h / "overlays" / "probe.txt").read_text(encoding="utf-8") == "тест"
PY
}
heads_cards() {   # four looks the task names (window, circle, cloud, polaroid without photos) + one picked by its catalog name
  py - "$(wp "$REEL")" "$(wp "$HREEL")" <<'PY'
import json, sys; from pathlib import Path
r, h = Path(sys.argv[1]), Path(sys.argv[2]); e = json.load(open(r / "edit.json", encoding="utf-8"))
e["cards"] = [
  {"type": "head", "look": "window",   "words": ["сьогодні", "знайти", "клієнтів"], "start": 0.8, "end": 4.4, "id": "h_window"},
  {"type": "head", "look": "circle",   "words": ["перше", "упакуй", "профіль"], "start": 5.3, "end": 7.3, "id": "h_circle"},
  {"type": "head", "look": "cloud",    "words": ["запусти", "рекламу", "двадцять", "доларів"], "start": 7.6, "end": 11.0, "id": "h_cloud"},
  {"type": "head", "look": "polaroid", "words": ["третє", "пиши", "людям", "першою"], "start": 11.8, "end": 14.2, "id": "h_polaroid"},
  {"type": "motion", "name": "head-top", "vars": {"text": "підписуйся"}, "start": 14.3, "end": 16.3, "id": "h_top"},
]
json.dump(e, open(h / "edit.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(len(e["cards"]), "head cards,", len(e["captions"]), "captions")
PY
}
heads_render() {
  local o; o="$(REEL_DRAFT=1 REEL_PREVIEW=1 REEL_WORKERS=2 bash "$S/render.sh" "$HREEL" 2>&1)"; local rc=$?; echo "$o"; [ $rc = 0 ] || return $rc
  ! printf '%s\n' "$o" | grep -E "head: unknown look|drawn as window|Traceback"   # every look built as itself
}
heads_check() {   # mid-card frames: the brand background must fill the frame around the small video window
  py - "$(wp "$HREEL/draft.mp4")" "$(wp "$OUTD")" <<'PY'
import subprocess, sys
src, out = sys.argv[1], sys.argv[2]
# (look, second, x, y in the 540x960 draft, expected colour or None): light = #FAFAF7 (light #FFFFFF), pop #FFC3CC, soft #D2DB76
checks = [("window", 2.6, 8, 8, (0xFA, 0xFA, 0xF7)), ("circle", 6.3, 8, 8, (0xFF, 0xC3, 0xCC)), ("cloud", 9.2, 8, 8, (0xD2, 0xDB, 0x76)),
          ("polaroid", 13.0, 8, 8, None), ("top", 15.3, 8, 940, (0xFA, 0xFA, 0xF7))]
bad = 0
for look, t, x, y, want in checks:
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(t), "-i", src, "-frames:v", "1", f"{out}/head_{look}.jpg"], check=True)
    px = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(t), "-i", src, "-frames:v", "1", "-vf", f"crop=4:4:{x}:{y},scale=1:1",
                         "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True, check=True).stdout[:3]
    got = tuple(px); ok = want is None or all(abs(a - b) <= 28 for a, b in zip(got, want))
    bad += not ok; print(f"{'ok ' if ok else 'BAD'} {look:9s} {t:5.1f}s  pixel {got}  want {want or 'any (photo tint)'}")
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-vf", "fps=1,scale=150:-2,tile=6x3", "-frames:v", "1", f"{out}/heads_contact.jpg"])
sys.exit(1 if bad else 0)
PY
}
heads_menu() {   # the effects menu's «Подачі голови»: all 11 looks on their own clip (menu_previews.heads links files with os.symlink)
  local o; o="$(py "$S/menu_previews.py" "$(wp "$HREEL")" --only heads --workers 1 2>&1)"; echo "$o"
  local n; n=$(printf '%s\n' "$o" | grep -c '^ok head-'); echo "rendered $n of 11"
  mkdir -p "$OUTD/menu"; cp -f "$REELS_HOME"/menu/head-*.mp4 "$OUTD/menu/" 2>/dev/null
  [ "$n" = 11 ]
}
step "heads: linked files (no symlinks)" heads_links
step "heads: 5 head cards"           heads_cards
step "heads: render draft"           heads_render
step "heads: brand colour around the window" heads_check
step "heads: effects menu (11 looks)" heads_menu
cp -f "$HREEL/draft.mp4" "$OUTD/heads_draft.mp4" 2>/dev/null
cp -f "$REEL"/edit.json "$REEL"/face.json "$REEL"/safezones.json "$REEL"/timings.log "$OUTD/" 2>/dev/null
cp -f "$REEL/draft.mp4" "$OUTD/draft.mp4" 2>/dev/null
echo; cat "$REPORT"
[ $FAILS = 0 ] && echo "ALL STEPS PASSED" || { echo "$FAILS STEP(S) FAILED"; exit 1; }
