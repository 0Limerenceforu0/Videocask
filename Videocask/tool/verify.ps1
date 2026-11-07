# 本地/CI 一致性校验：格式化、分析、测试
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "== flutter gen-l10n =="
flutter gen-l10n
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== dart format (check) =="
dart format --output=none --set-exit-if-changed lib test tool
if ($LASTEXITCODE -ne 0) {
    Write-Host "Run: dart format lib test tool" -ForegroundColor Yellow
  exit $LASTEXITCODE
}

Write-Host "== flutter analyze =="
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== flutter test =="
flutter test
exit $LASTEXITCODE
