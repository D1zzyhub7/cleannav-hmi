#!/usr/bin/env bash
set -euo pipefail

command -v flutter >/dev/null 2>&1 || {
  echo "未找到 Flutter，请先安装 Flutter 3.27 或更高版本。"
  exit 1
}

project_root="$(cd "$(dirname "$0")/.." && pwd)"
temp_root="$(mktemp -d)"
trap 'rm -rf "$temp_root"' EXIT

flutter create --project-name cleannav_mobile --platforms=android,ios "$temp_root/scaffold"

for platform in android ios; do
  if [[ ! -d "$project_root/$platform" ]]; then
    cp -R "$temp_root/scaffold/$platform" "$project_root/$platform"
  fi
done

python3 "$project_root/scripts/configure_platforms.py" "$project_root"
cd "$project_root"
flutter pub get
flutter analyze
flutter test

echo "CleanNav 手机 APP 环境准备完成。"
echo "运行：flutter run"
