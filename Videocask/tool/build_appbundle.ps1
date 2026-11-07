# Google Play AAB：先递增构建号，再 flutter build appbundle --release
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "== bump version =="
dart run tool/bump_version.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== flutter build appbundle --release =="
flutter build appbundle --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$aab = Join-Path $PWD "build\app\outputs\bundle\release\app-release.aab"
if (Test-Path $aab) {
  $sizeMb = [math]::Round((Get-Item $aab).Length / 1MB, 1)
  Write-Host ""
  Write-Host "AAB: $aab ($sizeMb MB)" -ForegroundColor Green
}

exit 0
