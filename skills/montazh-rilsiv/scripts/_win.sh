# Windows (Git Bash) helpers, sourced by every .sh script in this skill.
# python3: Windows ships a Microsoft Store stub under that name, so use the first Python that really runs.
for _c in python py python3; do
  if command -v "$_c" >/dev/null 2>&1 && "$_c" -c "import sys" >/dev/null 2>&1; then PY="$_c"; break; fi
done
python3() { command "${PY:-python}" "$@"; }   # `command`: never this function itself
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8   # brand files, transcripts and captions are Cyrillic
# a path Windows programs (Python, ffmpeg, Chrome) can open: /c/Users/x -> C:/Users/x
wp() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
# low priority when nice exists (it keeps the PC usable during a render); otherwise run as is
if command -v nice >/dev/null 2>&1; then NICE=(nice -n 15); else NICE=(); fi
# total memory in GB (sysctl is macOS only)
mem_gb() { powershell.exe -NoProfile -Command "[math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)" 2>/dev/null | tr -d '\r' || echo 16; }
# a Windows notification (render done); the reel name is the only argument
notify_win() { powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wp "$(dirname "${BASH_SOURCE[0]}")/notify.ps1")" "$1" >/dev/null 2>&1 & }
# HyperFrames downloads its own headless Chrome and unzips it with Windows' tar.exe, which can't open a path with
# Cyrillic letters (C:\Users\Інна\.cache\...); an installed chrome.exe doesn't work either (it hangs on --version).
# For such a user folder the headless Chrome goes once into C:\Users\Public\montazh-rilsiv (plain letters, any user can write).
HF_PUB="/c/Users/Public/montazh-rilsiv"
hf_browser() { find "$HF_PUB/.cache" -name chrome-headless-shell.exe 2>/dev/null | head -1; }
if [ -z "${HYPERFRAMES_BROWSER_PATH:-}" ] && printf %s "${USERPROFILE:-}$HOME" | LC_ALL=C grep -q '[^ -~]'; then
  if [ -z "$(hf_browser)" ]; then
    echo "one-time: installing the render browser into C:\\Users\\Public\\montazh-rilsiv (your user folder has non-Latin letters)" >&2
    mkdir -p "$HF_PUB" && (cd "$HF_PUB" && HOME="$HF_PUB" USERPROFILE="$(wp "$HF_PUB")" npx -y hyperframes@0.8.145 browser ensure >&2) || true
  fi
  [ -n "$(hf_browser)" ] && export HYPERFRAMES_BROWSER_PATH="$(wp "$(hf_browser)")"
fi
