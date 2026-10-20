#!/usr/bin/env python3
"""Build the Windows skill from the Mac one. Re-run after every update of the Mac skill:
    python3 tools/port_from_mac.py ~/montazh-rilsiv/skills/montazh-rilsiv
It replaces skills/montazh-rilsiv/ with a fresh copy of the Mac skill plus the Windows layer:
- every .py imports scripts/_win.py first (UTF-8 mode, npx/nice/bash lookup, fcntl/symlink stand-ins);
- every .sh sources scripts/_win.sh (real Python instead of the python3 stub, C:/ paths, notifications);
- the Mac-only lines below are swapped for Windows ones. A patch that no longer matches stops the port with its name,
  so a change in the Mac skill is never silently left Mac-only."""
import ast, re, shutil, sys
from pathlib import Path

SRC = Path(sys.argv[1]).expanduser().resolve()
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "skills" / "montazh-rilsiv"
OVERLAY = ROOT / "tools" / "overlay"
MAC_ONLY = {"scripts/face_box.swift"}

# (file, old, new): exact text swaps
PATCHES = [
    # ---- shell scripts ----
    ("scripts/render.sh", 'MEM_GB=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 17179869184) / 1073741824 ))', 'MEM_GB="$(mem_gb)"; MEM_GB="${MEM_GB:-16}"'),
    ("scripts/render.sh", 'BRAND="${REELS_HOME:-$HOME/reels}/brand.json"', 'BRAND="$(wp "${REELS_HOME:-$HOME/reels}/brand.json")"'),
    ("scripts/render.sh", "nice -n 15 npx", '"${NICE[@]}" npx'),
    ("scripts/render.sh", "# a Mac notification when the render is done (the person may be away from the screen)\n"
                          'command -v osascript >/dev/null && osascript -e "display notification \\"$(basename "$REEL")\\" with title \\"Рілс відрендерено\\" sound name \\"Glass\\"" >/dev/null 2>&1 || true',
                          "# a Windows notification when the render is done (the person may be away from the screen)\n"
                          'notify_win "$(basename "$REEL")" || true'),
    ("scripts/deliver.sh", 'BRAND="${REELS_HOME:-$HOME/reels}/brand.json"', 'BRAND="$(wp "${REELS_HOME:-$HOME/reels}/brand.json")"'),
    ("scripts/deliver.sh", "'~/Movies/Reels'", "'~/Videos/Reels'"),
    ("scripts/deliver.sh", 'mkdir -p "$DIR"; OUT=', 'DIR="$(cygpath -u "$DIR" 2>/dev/null || printf %s "$DIR")"; mkdir -p "$DIR"; OUT='),
    ("scripts/clean_audio.sh", 'BRAND="${REELS_HOME:-$HOME/reels}/brand.json"', 'BRAND="$(wp "${REELS_HOME:-$HOME/reels}/brand.json")"'),
    ("scripts/screenshot.sh", 'for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \\\n'
                              '         "/Applications/Chromium.app/Contents/MacOS/Chromium" \\\n'
                              '         "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \\\n',
                              'for c in "/c/Program Files/Google/Chrome/Application/chrome.exe" \\\n'
                              '         "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \\\n'
                              '         "${LOCALAPPDATA:-}/Google/Chrome/Application/chrome.exe" \\\n'
                              '         "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \\\n'
                              '         "/c/Program Files/Microsoft/Edge/Application/msedge.exe" \\\n'),
    ("scripts/screenshot.sh", '--screenshot="$OUT"', '--screenshot="$(wp "$OUT")"'),
    ("scripts/setup_engine.sh", '"$(shasum -a 256 "$E/gsap.min.js.tmp" | cut -d\' \' -f1)"',
                                '"$({ sha256sum "$E/gsap.min.js.tmp" 2>/dev/null || shasum -a 256 "$E/gsap.min.js.tmp"; } | cut -d\' \' -f1)"'),
    ("scripts/setup_engine.sh", '"$(dirname "$E")/references/motion_catalog.json")"', '"$(wp "$(dirname "$E")/references/motion_catalog.json")")"'),
    ("scripts/doctor.sh", 'command -v ffmpeg >/dev/null && ok "ffmpeg" || no "ffmpeg" "macOS: brew install ffmpeg"',
                          'command -v ffmpeg >/dev/null && ok "ffmpeg" || no "ffmpeg" "winget install -e --id Gyan.FFmpeg"'),
    ("scripts/doctor.sh", 'no "Node.js" "install the LTS version from https://nodejs.org"', 'no "Node.js" "winget install -e --id OpenJS.NodeJS.LTS"'),
    ("scripts/doctor.sh", 'command -v python3 >/dev/null && ok "Python 3" || no "Python 3" "macOS: xcode-select --install"',
                          '[ -n "${PY:-}" ] && ok "Python 3 ($PY)" || no "Python 3" "winget install -e --id Python.Python.3.12 --scope user"'),
    ("scripts/doctor.sh", '[ "$(uname)" = "Darwin" ] || warn "not macOS" "macOS is the tested platform; Windows and Linux are untested"',
                          'case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ok "Windows (Git Bash)";; *) warn "not Windows" "this is the Windows version of the skill: on a Mac install montazh-rilsiv instead";; esac'),
    ("scripts/doctor.sh", 'python3 - "$HOME_DIR/brand.json" <<', 'python3 - "$(wp "$HOME_DIR/brand.json")" <<'),
    ("scripts/doctor.sh", '.get(\'capcut\') else 1)" "$HOME_DIR/brand.json"', '.get(\'capcut\') else 1)" "$(wp "$HOME_DIR/brand.json")"'),
    # the font/face venv: Windows keeps the interpreter in Scripts/, and OpenCV does the face finding macOS Vision does on a Mac
    ("scripts/doctor.sh", 'VENV="${REELS_HOME:-$HOME/reels}/.venv"\n', 'VENV="${REELS_HOME:-$HOME/reels}/.venv"; VPY="$VENV/Scripts/python.exe"\n'),
    ("scripts/doctor.sh", 'if [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c "import fontTools, brotli" 2>/dev/null; then ok "font measuring (fontTools)"\n'
                          'elif python3 -m venv "$VENV" >/dev/null 2>&1 && "$VENV/bin/pip" install -q fonttools brotli Pillow >/dev/null 2>&1; then ok "font measuring (fontTools) installed in $VENV"\n'
                          'else warn "fontTools not installed" "text sizes fall back to an estimate; run: python3 -m venv ~/reels/.venv && ~/reels/.venv/bin/pip install fonttools brotli Pillow"; fi',
                          'if [ -x "$VPY" ] && "$VPY" -c "import fontTools, brotli, cv2" 2>/dev/null; then ok "font measuring + face finding (fontTools, OpenCV)"\n'
                          'elif { [ -x "$VPY" ] || python3 -m venv "$(wp "$VENV")" >/dev/null 2>&1; } && "$VPY" -m pip install -q fonttools brotli Pillow opencv-python-headless >/dev/null 2>&1; then ok "font measuring + face finding installed in $VENV"\n'
                          'else warn "fontTools/OpenCV not installed" "text sizes fall back to an estimate and graphics use the default face zone; run: python -m venv ~/reels/.venv && ~/reels/.venv/Scripts/python.exe -m pip install fonttools brotli Pillow opencv-python-headless"; fi'),
    # ---- python ----
    ("scripts/face_box.py", 'out = subprocess.run(["swift", str(Path(__file__).with_name("face_box.swift")), *imgs]',
                            'out = subprocess.run([sys.executable, str(Path(__file__).with_name("face_box_cv.py")), *imgs]'),
    ("scripts/face_box.py", "12 frames across raw.*; macOS Vision finds the face", "12 frames across raw.*; OpenCV (in ~/reels/.venv) finds the face"),
    ("scripts/face_box.py", "Without macOS/swift it falls back", "Without OpenCV it falls back"),
    ("scripts/style_lab.py", "# macOS only; without it graphics aren't moved off the face", "# needs OpenCV in ~/reels/.venv; without it graphics use the default face zone"),
    # ---- docs ----
    ("SKILL.md", "(macOS Vision, ~30 s)", "(OpenCV from ~/reels/.venv, ~30 s)"),
    ("SKILL.md", "`render.sh` only shows a Mac notification", "`render.sh` only shows a Windows notification"),
    ("SKILL.md", "On an 8 GB Mac keep", "On an 8 GB computer keep"),
    ("references/review.md", "macOS Vision finds the face on 12 frames", "OpenCV (installed by doctor.sh in ~/reels/.venv) finds the face on 12 frames"),
    ("references/setup-interview.md", '"deliver_dir": "~/Movies/Reels"', '"deliver_dir": "~/Videos/Reels"'),
    ("references/setup-interview.md", "and a recent Mac", "and a recent computer"),
    ("references/motions.md", "slow on an 8 GB Mac", "slow on an 8 GB computer"),
]

WIN_RULES = """## This is the Windows version
Everything runs in Claude Code's shell on Windows, which is Git Bash. Rules for every command in this skill:
- `python3` on Windows is often a Microsoft Store stub that does nothing. Wherever this skill says `python3 scripts/x.py`, run `python scripts/x.py` (or `py scripts/x.py` if only the launcher exists). The `.sh` scripts find the right Python themselves, and every script switches on UTF-8 itself (brand files and captions are Cyrillic).
- `~` is the person's user folder (`C:\\Users\\<name>`). The finished reels go to `~/Videos/Reels` (Відео → Reels).
- Face finding (`face_box.py`) uses OpenCV from `~/reels/.venv` instead of macOS Vision; `doctor.sh` installs it.

"""

FIRST_RUN = """## First run on a new computer (do it yourself, never send the person to a terminal)
The person works in the Claude desktop app, Code tab. Never ask them to open PowerShell, CMD or a terminal. Windows asks «Дозволити цій програмі вносити зміни?» for some installs: tell them to click «Так». In this order, skipping what is already there:
1. Python: if `python -c "import sys"` fails (and `py -c "import sys"` too), run `winget install -e --id Python.Python.3.12 --scope user --accept-package-agreements --accept-source-agreements`.
2. Node.js: if `node -v` fails, `winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements` (the «Так» window appears).
3. ffmpeg: if `ffmpeg -version` fails, `winget install -e --id Gyan.FFmpeg --accept-package-agreements --accept-source-agreements`.
4. A new install isn't on this shell's PATH yet. Append these lines to `~/.bashrc` (once) and also `export` them in every command until the app restarts:
   `export PATH="$LOCALAPPDATA/Programs/Python/Python312:$LOCALAPPDATA/Programs/Python/Python312/Scripts:/c/Program Files/nodejs:$LOCALAPPDATA/Microsoft/WinGet/Links:$PATH"` and `export PYTHONUTF8=1`. Then re-check `python`, `node`, `ffmpeg`. If one is still missing, find its .exe under `C:\\Program Files` or `$LOCALAPPDATA` and add that folder.
   If `winget` itself is missing (old Windows 10), say so plainly and send them to the Microsoft Store page «App Installer» to update it, then continue.
5. `npx skills add heygen-com/hyperframes -y` if the HyperFrames skills are missing.
6. `bash scripts/setup_engine.sh` (animation library + sound effects).
7. Speech recognition: connect ElevenLabs Scribe (section «Connecting ElevenLabs Scribe» below). It is required: there is no local recogniser, so nothing large is downloaded. Walk them through creating the key in one short step at a time.
8. `mkdir -p ~/reels/fonts ~/reels/assets` (the reels workspace).
9. `bash scripts/doctor.sh` (it also installs font measuring and face finding into `~/reels/.venv`). If it's READY, tell them in one sentence that everything is ready, that it's worth closing and reopening the Claude app once (so the new programs are found), and that next time they open the Code tab with the folder `reels` and write «змонтуй рілс».
Explain each step in one short Ukrainian sentence: the person is a beginner.

"""

KEY_STEP = """2. Never ask them to paste it in chat. Open the masked Windows dialog, which writes it straight to `~/.config/reels/.env` and prints only its length:
   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -m scripts/ask_key.ps1)"` (a Windows sign-in style window: they paste the key into the password field and press OK). `SAVED` = done; `NOT A KEY` = they pasted the key ID, ask for the `sk_` key; `CANCELLED` = ask again.
"""

WIN_PY = "import os as _os, sys as _sys; _sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__))); import _win  # noqa: E402,F401  Windows layer (scripts/_win.py)\n"


def py_layer(p):
    t = p.read_text(encoding="utf-8")
    lines = t.splitlines(keepends=True)
    body = ast.parse(t).body
    at = body[0].end_lineno if body and isinstance(body[0], ast.Expr) and isinstance(getattr(body[0], "value", None), ast.Constant) \
        and isinstance(body[0].value.value, str) else (1 if lines and lines[0].startswith("#!") else 0)
    while at < len(lines) and lines[at].startswith("from __future__"): at += 1
    lines.insert(at, WIN_PY)
    p.write_text("".join(lines), encoding="utf-8")


def sh_layer(p):
    t = p.read_text(encoding="utf-8")
    src = 'source "$(dirname "${BASH_SOURCE[0]}")/_win.sh"\n'
    m = re.search(r"^set -[a-z]+.*\n", t, re.M)
    if m: t = t[:m.end()] + src + t[m.end():]
    else:
        nl = t.index("\n") + 1 if t.startswith("#!") else 0
        t = t[:nl] + src + t[nl:]
    p.write_text(t, encoding="utf-8")


def swap(rel, old, new):
    p = OUT / rel
    t = p.read_text(encoding="utf-8")
    if old not in t: sys.exit(f"PORT STOPPED: patch no longer matches {rel}:\n  {old[:160]!r}\nUpdate tools/port_from_mac.py for the new Mac code.")
    p.write_text(t.replace(old, new), encoding="utf-8")


def main():
    if OUT.exists(): shutil.rmtree(OUT)
    shutil.copytree(SRC, OUT, ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".DS_Store", "engine"))
    for rel in MAC_ONLY: (OUT / rel).unlink(missing_ok=True)
    for rel, old, new in PATCHES: swap(rel, old, new)
    sk = OUT / "SKILL.md"; t = sk.read_text(encoding="utf-8")
    a = t.index("## First run on a new computer"); b = t.index("## Check the tools")
    t = t[:a] + WIN_RULES + FIRST_RUN + t[b:]
    a = t.index("2. Never ask them to paste it in chat."); b = t.index("3. Test it on 20 s of audio")
    t = t[:a] + KEY_STEP + t[b:]
    sk.write_text(t, encoding="utf-8")
    for p in sorted((OUT / "scripts").glob("*.py")): py_layer(p)
    for p in sorted((OUT / "scripts").glob("*.sh")): sh_layer(p)
    for f in OVERLAY.rglob("*"):
        if f.is_file(): d = OUT / f.relative_to(OVERLAY); d.parent.mkdir(parents=True, exist_ok=True); shutil.copy(f, d)
    # nothing Mac-only may remain in the scripts
    left = [f"{p.relative_to(OUT)}: {w}" for p in (OUT / "scripts").iterdir() if p.suffix in (".py", ".sh") and not (OVERLAY / "scripts" / p.name).exists()
            for w in ("osascript", "sysctl", "swift", "/Applications/", "~/Movies", "h264_videotoolbox") if w in p.read_text(encoding="utf-8")
            and not (w == "h264_videotoolbox" and 'sys.platform == "darwin"' in p.read_text(encoding="utf-8"))]
    if left: sys.exit("PORT STOPPED: Mac-only calls left:\n  " + "\n  ".join(left))
    print(f"Windows skill built in {OUT} from {SRC}")


main()
