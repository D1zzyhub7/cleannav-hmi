#!/usr/bin/env python3
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]).resolve()
manifest = root / "android/app/src/main/AndroidManifest.xml"
info = root / "ios/Runner/Info.plist"
podfile = root / "ios/Podfile"

permissions = """    <uses-permission android:name=\"android.permission.BLUETOOTH\" android:maxSdkVersion=\"30\" />
    <uses-permission android:name=\"android.permission.BLUETOOTH_ADMIN\" android:maxSdkVersion=\"30\" />
    <uses-permission android:name=\"android.permission.ACCESS_FINE_LOCATION\" android:maxSdkVersion=\"30\" />
    <uses-permission android:name=\"android.permission.BLUETOOTH_SCAN\" android:usesPermissionFlags=\"neverForLocation\" />
    <uses-permission android:name=\"android.permission.BLUETOOTH_CONNECT\" />
    <uses-permission android:name=\"android.permission.INTERNET\" />
"""

if manifest.exists():
    text = manifest.read_text(encoding="utf-8")
    if "android.permission.BLUETOOTH_SCAN" not in text:
        start = text.find("<manifest")
        end = text.find(">", start) + 1
        if start < 0 or end <= 0:
            raise RuntimeError("AndroidManifest.xml 中未找到 manifest 根元素")
        text = text[:end] + "\n" + permissions + text[end:]
        manifest.write_text(text, encoding="utf-8")

if info.exists():
    text = info.read_text(encoding="utf-8")
    if "NSBluetoothAlwaysUsageDescription" not in text:
        values = """\n\t<key>NSBluetoothAlwaysUsageDescription</key>
\t<string>用于连接和控制 CleanNav 清扫车设备</string>
\t<key>NSBluetoothPeripheralUsageDescription</key>
\t<string>用于与 CleanNav 清扫车交换任务和状态</string>"""
        text = text.replace("</dict>", values + "\n</dict>")
        info.write_text(text, encoding="utf-8")

if podfile.exists():
    text = podfile.read_text(encoding="utf-8")
    if re.search(r"^\s*#?\s*platform\s+:ios", text, flags=re.MULTILINE):
        text = re.sub(r"^\s*#?\s*platform\s+:ios.*$", "platform :ios, '13.0'", text, flags=re.MULTILINE)
    else:
        text = "platform :ios, '13.0'\n" + text
    podfile.write_text(text, encoding="utf-8")
