#!/bin/bash
# Save an API key without it ever showing in the chat: a masked Windows dialog writes it straight into
# ~/.config/reels/.env and prints only its length.
#   set_key.sh PIXABAY_API_KEY | PEXELS_API_KEY | GIPHY_API_KEY | ELEVENLABS_API_KEY
set -euo pipefail
NAME="${1:?key name, e.g. PIXABAY_API_KEY}"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -m "$(dirname "${BASH_SOURCE[0]}")/set_key.ps1")" "$NAME"
