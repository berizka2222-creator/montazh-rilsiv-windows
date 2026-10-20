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
