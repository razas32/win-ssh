# Remote-access + Wake-on-LAN bootstrap for Windows.
# Installs OpenSSH Server + Tailscale, enables Wake-on-LAN (incl. from full
# shutdown), and disables Fast Startup so S5 wake works.
#
# NOTE: Wake-from-full-shutdown ALSO requires BIOS settings that software
# cannot change. Before/after running this, in the BIOS set:
#   - "Wake on LAN" / "Power On By PCI-E" -> Enabled
#   - "ErP / EuP Ready" -> Disabled
#
# Run in an Administrator PowerShell:
#   irm https://raw.githubusercontent.com/razas32/win-ssh/main/enable-ssh.ps1 | iex

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Write-Host "Run PowerShell as Administrator and try again." -ForegroundColor Red; return }

# ---------------------------------------------------------------- OpenSSH ----
Step "Installing OpenSSH Server"
$arch  = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'ARM64' } else { 'Win64' }
if (-not (Test-Path "$env:ProgramFiles\OpenSSH\sshd.exe") -and -not (Get-Service sshd -EA SilentlyContinue)) {
    $rels  = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases' -UseBasicParsing
    $asset = $rels | ForEach-Object { $_.assets } | Where-Object { $_.name -like "OpenSSH-$arch-*.msi" } | Select-Object -First 1
    $msi   = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest $asset.browser_download_url -OutFile $msi -UseBasicParsing
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
    if ($p.ExitCode -notin 0, 3010) { Write-Host "OpenSSH installer failed (exit $($p.ExitCode))." -ForegroundColor Red; return }
}
Set-Service sshd -StartupType Automatic
Start-Service sshd
if (-not (Get-NetFirewallRule -Name 'sshd-bootstrap' -EA SilentlyContinue)) {
    New-NetFirewallRule -Name 'sshd-bootstrap' -DisplayName 'OpenSSH Server (port 22)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any | Out-Null
}
Write-Host "   sshd: $((Get-Service sshd).Status)"

# -------------------------------------------------------------- Tailscale ----
Step "Installing Tailscale"
if (-not (Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe")) {
    $ts = Join-Path $env:TEMP 'tailscale-setup.msi'
    Invoke-WebRequest 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi' -OutFile $ts -UseBasicParsing
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$ts`" /qn /norestart" -Wait -PassThru
    if ($p.ExitCode -notin 0, 3010) { Write-Host "Tailscale installer failed (exit $($p.ExitCode))." -ForegroundColor Red }
}
$tsExe = "$env:ProgramFiles\Tailscale\tailscale.exe"
Write-Host "   Tailscale installed. Sign-in link below (open it and approve on your account):" -ForegroundColor Yellow
& $tsExe up --unattended --accept-dns=false 2>&1 | Where-Object { $_ -match 'http' }

# ------------------------------------------------------------ Wake-on-LAN ----
Step "Enabling Wake-on-LAN (software side)"
# Disable Fast Startup (hybrid shutdown blocks wake from S5)
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -Type DWord -Force

$wired = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' -and $_.PhysicalMediaType -match '802.3' } |
         Select-Object -First 1
if (-not $wired) { $wired = Get-NetAdapter -Physical | Where-Object { $_.InterfaceDescription -notmatch 'Wi-?Fi|Wireless|Bluetooth|Tailscale' } | Select-Object -First 1 }

if ($wired) {
    try {
        Enable-NetAdapterPowerManagement -Name $wired.Name -WakeOnMagicPacket -EA Stop
    } catch {
        # Fallback: flip the wake flags via powercfg / driver registry
        powercfg /deviceenablewake "$($wired.InterfaceDescription)" 2>$null
    }
    # Allow the device to wake the machine
    powercfg /deviceenablewake "$($wired.InterfaceDescription)" 2>$null
    $mac = $wired.MacAddress
    $pm  = Get-NetAdapterPowerManagement -Name $wired.Name -EA SilentlyContinue
    Write-Host "   Wired NIC   : $($wired.InterfaceDescription)"
    Write-Host "   WakeOnMagic : $($pm.WakeOnMagicPacket)"
} else {
    Write-Host "   No wired adapter found - plug in Ethernet for reliable wake-on-LAN." -ForegroundColor Yellow
    $mac = (Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Select-Object -First 1).MacAddress
}

# --------------------------------------------------------------- Summary -----
$tsIp = (& $tsExe ip -4 2>$null | Select-Object -First 1)
Write-Host "`n========================================" -ForegroundColor Green
Write-Host " SETUP COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host " Hostname      : $env:COMPUTERNAME"
Write-Host " User          : $(whoami)"
Write-Host " Tailscale IP  : $(if ($tsIp) { $tsIp } else { '(finish sign-in above)' })"
Write-Host " Wake MAC      : $mac"
Write-Host ""
Write-Host " STILL TO DO BY HAND:" -ForegroundColor Yellow
Write-Host "  1. Finish the Tailscale sign-in link above."
Write-Host "  2. In BIOS: 'Wake on LAN'/'Power On By PCI-E' = Enabled, 'ErP/EuP' = Disabled."
Write-Host "  3. Keep it on Ethernet + plugged into power."
Write-Host "  Wake it later from the ASUS Router app (Wake on LAN) using the MAC above."
