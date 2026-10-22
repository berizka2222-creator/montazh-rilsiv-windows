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
qa_draft() {   # the draft is 540x960 on purpose, so the size check is the one FAIL allowed here
  local o; o="$(REEL_PREVIEW=1 python3 "$S/qa.py" "$(wp "$REEL")" draft.mp4 2>&1)"; echo "$o"
  [ "$(printf '%s\n' "$o" | grep '^FAIL')" = "FAIL: size" ] || printf '%s\n' "$o" | grep -q '^PASS'
}
step "qa.py on draft"                qa_draft
step "frames from draft"             frames
step "render_queue (locks)"          queue
step "deliver.sh"                    bash "$S/deliver.sh" "$REEL/draft.mp4" "Тест рілс"
step "motions.py log"                py "$S/motions.py" log "$(wp "$REEL")"
cp -f "$REEL"/edit.json "$REEL"/face.json "$REEL"/safezones.json "$REEL"/timings.log "$OUTD/" 2>/dev/null
cp -f "$REEL/draft.mp4" "$OUTD/draft.mp4" 2>/dev/null
echo; cat "$REPORT"
[ $FAILS = 0 ] && echo "ALL STEPS PASSED" || { echo "$FAILS STEP(S) FAILED"; exit 1; }
