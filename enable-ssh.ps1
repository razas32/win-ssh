# Installs and enables OpenSSH Server on Windows using the official
# Microsoft MSI from github.com/PowerShell/Win32-OpenSSH (avoids Windows Update).
# Run in an Administrator PowerShell:
#   irm <raw-url-of-this-file> | iex

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Write-Host "Run PowerShell as Administrator and try again." -ForegroundColor Red; return }

$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'ARM64' } else { 'Win64' }

Write-Host "Finding latest OpenSSH release..."
$rels  = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases' -UseBasicParsing
$asset = $rels | ForEach-Object { $_.assets } | Where-Object { $_.name -like "OpenSSH-$arch-*.msi" } | Select-Object -First 1
if (-not $asset) { Write-Host "Could not find an MSI to download." -ForegroundColor Red; return }

$msi = Join-Path $env:TEMP $asset.name
Write-Host "Downloading $($asset.name)..."
Invoke-WebRequest $asset.browser_download_url -OutFile $msi -UseBasicParsing

Write-Host "Installing..."
$p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
if ($p.ExitCode -notin 0, 3010) { Write-Host "Installer failed (exit $($p.ExitCode))." -ForegroundColor Red; return }

Write-Host "Starting SSH service..."
Set-Service sshd -StartupType Automatic
Start-Service sshd

if (-not (Get-NetFirewallRule -Name 'sshd-enable-script' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'sshd-enable-script' -DisplayName 'OpenSSH Server (port 22)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any | Out-Null
}

$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '10.*' -or $_.IPAddress -like '192.168.*' } | Select-Object -First 1).IPAddress
Write-Host ""
Write-Host "SSH is ON." -ForegroundColor Green
Write-Host "Service : $((Get-Service sshd).Status)"
Write-Host "User    : $(whoami)"
Write-Host "IP      : $ip"
Write-Host "From the Mac:  ssh $($env:USERNAME)@$ip"
