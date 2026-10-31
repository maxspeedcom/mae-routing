# MAE Routing for Windows - one-line installer
#
#   irm https://routing.maesuaisystem.com/install.ps1 | iex
#
# Downloads the newest MAE Routing installer, checks its SHA-256 against the website, and installs it.
# A file that PowerShell downloads carries no "downloaded from the internet" mark, so Windows does not show the
# SmartScreen "Windows protected your PC" screen. Windows still asks for administrator permission (UAC) once.
# After installing, click the MAE Routing icon next to the clock and choose "Sign in...".

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is very slow on Windows PowerShell 5.1 with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$base = if ($env:MAE_ROUTING_BASE) { $env:MAE_ROUTING_BASE } else { 'https://routing.maesuaisystem.com' }

if ($env:OS -ne 'Windows_NT' -and -not $env:MAE_ROUTING_DRYRUN) { throw 'This installer is for Windows. On Linux use: curl -fsSL https://routing.maesuaisystem.com/install.sh | sudo sh' }
if (-not $env:MAE_ROUTING_DRYRUN -and -not [Environment]::Is64BitOperatingSystem) { throw 'MAE Routing needs 64-bit Windows 10 or 11.' }

$latest = (Invoke-RestMethod -Uri "$base/api/versions" -UseBasicParsing).windows
if (-not $latest -or -not $latest.file -or -not $latest.sha256) { throw 'Could not find the newest MAE Routing version. Try again later.' }

$file = Join-Path ([IO.Path]::GetTempPath()) $latest.file
Write-Host "Downloading MAE Routing $($latest.version)..."
Invoke-WebRequest -Uri "$base/download/$($latest.file)" -OutFile $file -UseBasicParsing

$hash = (Get-FileHash -Path $file -Algorithm SHA256).Hash.ToLower()
if ($hash -ne $latest.sha256.ToLower()) {
    Remove-Item $file -Force -ErrorAction SilentlyContinue
    throw "The download is damaged (SHA-256 does not match). Please run the command again."
}
Write-Host "Checked: SHA-256 $hash"

if ($env:MAE_ROUTING_DRYRUN) { Write-Host "Dry run: would install $file"; return }

Write-Host 'Installing... Windows will ask for permission: choose Yes.'
$p = Start-Process -FilePath $file -ArgumentList '/S' -Verb RunAs -Wait -PassThru
Remove-Item $file -Force -ErrorAction SilentlyContinue
if ($p.ExitCode -ne 0) { throw "The installer stopped with code $($p.ExitCode)." }

Write-Host ''
Write-Host "MAE Routing $($latest.version) is installed."
Write-Host 'Next: click the MAE Routing icon next to the clock (bottom right) and choose "Sign in...".'
