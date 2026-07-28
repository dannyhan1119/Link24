#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
OUTPUT_APK="${1:-$PROJECT_ROOT/build/android/Link24-debug.apk}"

fail() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

[[ -x "$GODOT_BIN" ]] || fail "找不到 Godot：$GODOT_BIN"
[[ -x "$JAVA_HOME/bin/java" ]] || fail "找不到 JDK：$JAVA_HOME"
[[ -x "$ANDROID_SDK_ROOT/platform-tools/adb" ]] || fail "找不到 Android SDK：$ANDROID_SDK_ROOT"

export ANDROID_HOME="$ANDROID_SDK_ROOT"
export ANDROID_SDK_ROOT
export JAVA_HOME

mkdir -p "$(dirname "$OUTPUT_APK")"

if [[ ! -f "$PROJECT_ROOT/android/build/gradlew" ]]; then
  printf '正在安装 Godot Android Gradle 构建模板...\n'
  "$GODOT_BIN" \
    --headless \
    --path "$PROJECT_ROOT" \
    --install-android-build-template \
    --quit
fi

printf '正在导出 Android 调试 APK...\n'
"$GODOT_BIN" \
  --headless \
  --path "$PROJECT_ROOT" \
  --export-debug Android "$OUTPUT_APK"

[[ -f "$OUTPUT_APK" ]] || fail "Godot 未生成 APK：$OUTPUT_APK"

printf '\nAPK 已生成：%s\n' "$OUTPUT_APK"
printf 'SHA-256：'
shasum -a 256 "$OUTPUT_APK" | awk '{print $1}'
