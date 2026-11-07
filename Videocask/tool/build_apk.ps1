# Android Release 打包：先递增构建号，再 flutter build apk --release
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "== bump version =="
dart run tool/bump_version.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== flutter build apk --release =="
flutter build apk --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$apk = Join-Path $PWD "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apk) {
  $sizeMb = [math]::Round((Get-Item $apk).Length / 1MB, 1)
  Write-Host ""
  Write-Host "APK: $apk ($sizeMb MB)" -ForegroundColor Green
}

exit 0
