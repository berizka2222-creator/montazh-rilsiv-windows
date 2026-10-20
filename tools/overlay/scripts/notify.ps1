# A Windows tray notification when a reel render is done. Argument: the reel name.
param([string]$Reel = "")
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$n = New-Object System.Windows.Forms.NotifyIcon
$n.Icon = [System.Drawing.SystemIcons]::Information
$n.Visible = $true
$n.ShowBalloonTip(10000, "Рілс відрендерено", $Reel, [System.Windows.Forms.ToolTipIcon]::Info)
Start-Sleep -Seconds 11
$n.Dispose()
