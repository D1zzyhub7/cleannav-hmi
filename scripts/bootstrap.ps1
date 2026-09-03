$ErrorActionPreference = "Stop"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "未找到 Flutter，请先安装 Flutter 3.27 或更高版本，并将 flutter/bin 加入 PATH。"
}

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("cleannav_flutter_" + [guid]::NewGuid().ToString("N"))
$Scaffold = Join-Path $TempRoot "scaffold"

try {
  New-Item -ItemType Directory -Path $TempRoot | Out-Null
  flutter create --project-name cleannav_mobile --platforms=android,ios $Scaffold

  foreach ($Platform in @("android", "ios")) {
    $Destination = Join-Path $ProjectRoot $Platform
    if (-not (Test-Path $Destination)) {
      Copy-Item -Recurse (Join-Path $Scaffold $Platform) $Destination
    }
  }

  python (Join-Path $ProjectRoot "scripts/configure_platforms.py") $ProjectRoot
  Set-Location $ProjectRoot
  flutter pub get
  flutter analyze
  flutter test

  Write-Host "CleanNav 手机 APP 环境准备完成。" -ForegroundColor Green
  Write-Host "连接 Android 手机后运行：flutter run"
}
finally {
  if (Test-Path $TempRoot) {
    Remove-Item -Recurse -Force $TempRoot
  }
}
