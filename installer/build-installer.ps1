# Builds the Aimify desktop app and its Windows installer, signed when the
# code-signing certificate is available.
#
#   powershell -ExecutionPolicy Bypass -File installer\build-installer.ps1
#
# Signing uses a .pfx and its password, by default from D:\Aimify\signing
# (kept outside the repository; never commit them). Override with
# AIMIFY_PFX and AIMIFY_PFX_PASSWORD. Without them the installer is built
# unsigned. Pass -SkipBuild to reuse the last Flutter build.
param(
  [switch]$SkipBuild,
  [string]$ApiUrl = "https://www.aimify.app"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$iscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
$signtool = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
  Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
$pfx = if ($env:AIMIFY_PFX) { $env:AIMIFY_PFX } else { "D:\Aimify\signing\aimify-codesign.pfx" }
$password = if ($env:AIMIFY_PFX_PASSWORD) { $env:AIMIFY_PFX_PASSWORD }
  elseif (Test-Path "D:\Aimify\signing\pfx-password.txt") { (Get-Content "D:\Aimify\signing\pfx-password.txt" -Raw).Trim() }
$sign = (Test-Path $pfx) -and $password -and $signtool
$timestamp = "http://timestamp.digicert.com"

if (-not $SkipBuild) {
  flutter build windows --release "--dart-define=AIMIFY_API_URL=$ApiUrl"
  if ($LASTEXITCODE -ne 0) { throw "Flutter build failed." }
}

# The installer packages dist\aimify-production.
$dist = Join-Path $root "dist\aimify-production"
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Force $dist | Out-Null
Copy-Item -Recurse "build\windows\x64\runner\Release\*" $dist

$signArgs = @("sign", "/f", $pfx, "/p", $password, "/fd", "sha256", "/tr", $timestamp, "/td", "sha256", "/d", "Aimify")
if ($sign) {
  & $signtool @signArgs (Join-Path $dist "aimify_desktop.exe")
  if ($LASTEXITCODE -ne 0) { throw "Signing the app failed." }
} else {
  Write-Warning "No certificate found: building an unsigned installer."
}

# Inno Setup signs the setup .exe and the uninstaller through the "aimify"
# sign tool defined here ($f is the file it passes, $q a quote mark: real
# quotes would be split apart on the way to ISCC).
$isccArgs = @()
if ($sign) {
  $command = "`$q$signtool`$q sign /f `$q$pfx`$q /p $password /fd sha256 /tr $timestamp /td sha256 /d `$qAimify`$q `$f"
  $isccArgs += "/DSign", "/Saimify=$command"
}
& $iscc @isccArgs "installer\aimify.iss"
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed." }

$setup = Get-ChildItem (Join-Path $root "dist\Aimify-Setup-*.exe") | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "Installer: $($setup.FullName) ($([math]::Round($setup.Length / 1MB, 1)) MB)"
if ($sign) {
  Get-AuthenticodeSignature $setup.FullName | Format-List Status, StatusMessage, @{ n = "Signer"; e = { $_.SignerCertificate.Subject } }
}
