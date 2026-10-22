# Asks for an API key (Pixabay, GIPHY, Pexels, ElevenLabs) in a masked Windows dialog and writes it to ~/.config/reels/.env.
# The key never goes through the chat or the command line; only its length is printed.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File set_key.ps1 PIXABAY_API_KEY
param([Parameter(Mandatory = $true)][string]$Name)
$hint = switch ($Name) {
  "PIXABAY_API_KEY" { "Встав ключ Pixabay (pixabay.com/api/docs, рядок key) у поле пароля і натисни OK" }
  "GIPHY_API_KEY"   { "Встав ключ GIPHY (developers.giphy.com, API Key) у поле пароля і натисни OK" }
  "PEXELS_API_KEY"  { "Встав ключ Pexels у поле пароля і натисни OK" }
  "ELEVENLABS_API_KEY" { "Встав API-ключ ElevenLabs (починається з sk_) у поле пароля і натисни OK" }
  default { "Встав ключ $Name у поле пароля і натисни OK" }
}
$cred = Get-Credential -UserName $Name -Message $hint
if (-not $cred) { Write-Output "cancelled"; exit 1 }
$key = ($cred.GetNetworkCredential().Password -replace '\s', '')
if (-not $key) { Write-Output "empty key"; exit 1 }
$dir = Join-Path $env:USERPROFILE ".config\reels"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$file = Join-Path $dir ".env"
$lines = @()
if (Test-Path $file) { $lines = @(Get-Content $file | Where-Object { $_ -notmatch "^$Name=" }) }
$lines += "$Name=$key"
# UTF-8 without BOM: the Python reader expects the first line to start with the variable name
[System.IO.File]::WriteAllText($file, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("$Name saved (" + $key.Length + " characters)")
