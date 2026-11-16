# Asks for the ElevenLabs API key in a masked Windows dialog and writes it to ~/.config/reels/.env.
# The key never goes through the chat or the command line; only its length is printed.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File ask_key.ps1
$cred = Get-Credential -UserName "ElevenLabs" -Message "Встав API-ключ ElevenLabs (починається з sk_) у поле пароля і натисни OK"
if (-not $cred) { Write-Output "CANCELLED"; exit 1 }
$key = $cred.GetNetworkCredential().Password.Trim()
if (-not $key.StartsWith("sk_")) { Write-Output "NOT A KEY: it must start with sk_ (the key ID is not the key)"; exit 2 }
$dir = Join-Path $env:USERPROFILE ".config\reels"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$file = Join-Path $dir ".env"
$lines = @()
if (Test-Path $file) { $lines = @(Get-Content $file | Where-Object { $_ -notmatch '^ELEVENLABS_API_KEY=' }) }
$lines += "ELEVENLABS_API_KEY=$key"
# UTF-8 without BOM: the Python reader expects the first line to start with the variable name
[System.IO.File]::WriteAllText($file, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("SAVED: key of " + $key.Length + " characters in " + $file)
