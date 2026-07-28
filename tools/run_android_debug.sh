#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
ADB="${ADB:-$ANDROID_SDK_ROOT/platform-tools/adb}"
APK="$PROJECT_ROOT/build/android/Link24-debug.apk"
PACKAGE_NAME="com.link24.oasismigration"

"$PROJECT_ROOT/tools/export_android_debug.sh" "$APK"

serial="${1:-}"
if [[ -z "$serial" ]]; then
  devices="$("$ADB" devices | awk 'NR > 1 && $2 == "device" {print $1}')"
  count="$(printf '%s\n' "$devices" | awk 'NF {count++} END {print count+0}')"
  [[ "$count" -gt 0 ]] || {
    printf '错误：没有可用设备。请先用 android_device.sh pair/connect 连接手机。\n' >&2
    exit 1
  }
  [[ "$count" -eq 1 ]] || {
    printf '错误：检测到多个设备，请把目标序列号作为参数传入。\n' >&2
    "$ADB" devices -l >&2
    exit 1
  }
  serial="$devices"
fi

printf '\n正在安装到 %s...\n' "$serial"
"$ADB" -s "$serial" install -r -d "$APK"
"$ADB" -s "$serial" shell am force-stop "$PACKAGE_NAME"
"$ADB" -s "$serial" shell monkey -p "$PACKAGE_NAME" -c android.intent.category.LAUNCHER 1

printf '\n应用已启动。查看实时日志：\n'
printf '  ./tools/android_device.sh logs %s\n' "$serial"
