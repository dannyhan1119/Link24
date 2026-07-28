#!/usr/bin/env bash

set -euo pipefail

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
ADB="${ADB:-$ANDROID_SDK_ROOT/platform-tools/adb}"
PACKAGE_NAME="com.link24.oasismigration"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_APK="$PROJECT_ROOT/build/android/Link24-debug.apk"

fail() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
用法：
  ./tools/android_device.sh devices
  ./tools/android_device.sh pair IP:配对端口 [配对码]
  ./tools/android_device.sh connect IP[:调试端口]
  ./tools/android_device.sh usb-to-wifi [USB设备序列号] [端口]
  ./tools/android_device.sh disconnect [IP:端口]
  ./tools/android_device.sh install [设备序列号] [APK路径]
  ./tools/android_device.sh run [设备序列号]
  ./tools/android_device.sh logs [设备序列号]

Android 11 及以上推荐在“开发者选项 > 无线调试”中使用 pair + connect。
旧式方式需要先用 USB 连接，再执行 usb-to-wifi。
EOF
}

[[ -x "$ADB" ]] || fail "找不到 adb：$ADB"

device_serial() {
  local requested="${1:-}"
  if [[ -n "$requested" ]]; then
    printf '%s\n' "$requested"
    return
  fi

  local devices
  devices="$("$ADB" devices | awk 'NR > 1 && $2 == "device" {print $1}')"
  local count
  count="$(printf '%s\n' "$devices" | awk 'NF {count++} END {print count+0}')"

  [[ "$count" -gt 0 ]] || fail "没有已连接设备，请先执行 devices、pair 或 connect"
  [[ "$count" -eq 1 ]] || fail "检测到多个设备，请明确传入设备序列号"
  printf '%s\n' "$devices"
}

action="${1:-help}"
shift || true

case "$action" in
  devices)
    "$ADB" devices -l
    ;;

  pair)
    endpoint="${1:-}"
    code="${2:-}"
    [[ "$endpoint" == *:* ]] || fail "请传入手机显示的 IP:配对端口"
    if [[ -n "$code" ]]; then
      "$ADB" pair "$endpoint" "$code"
    else
      "$ADB" pair "$endpoint"
    fi
    ;;

  connect)
    endpoint="${1:-}"
    [[ -n "$endpoint" ]] || fail "请传入手机 IP 或 IP:调试端口"
    [[ "$endpoint" == *:* ]] || endpoint="$endpoint:5555"
    "$ADB" connect "$endpoint"
    ;;

  usb-to-wifi)
    serial="$(device_serial "${1:-}")"
    port="${2:-5555}"
    phone_ip="$("$ADB" -s "$serial" shell ip route | awk '
      {
        for (i = 1; i <= NF; i++) {
          if ($i == "src" && (i + 1) <= NF) {
            print $(i + 1)
            exit
          }
        }
      }
    ' | tr -d '\r')"
    [[ -n "$phone_ip" ]] || fail "无法读取手机 WLAN IP，请确认手机已连接 Wi-Fi"
    "$ADB" -s "$serial" tcpip "$port"
    printf '等待手机切换到 TCP 调试模式...\n'
    sleep 1
    "$ADB" connect "$phone_ip:$port"
    printf '无线设备序列号：%s:%s\n' "$phone_ip" "$port"
    ;;

  disconnect)
    if [[ -n "${1:-}" ]]; then
      "$ADB" disconnect "$1"
    else
      "$ADB" disconnect
    fi
    ;;

  install)
    serial="$(device_serial "${1:-}")"
    apk="${2:-$DEFAULT_APK}"
    [[ -f "$apk" ]] || fail "找不到 APK：$apk；请先执行 ./tools/export_android_debug.sh"
    "$ADB" -s "$serial" install -r -d "$apk"
    ;;

  run)
    serial="$(device_serial "${1:-}")"
    "$ADB" -s "$serial" shell am force-stop "$PACKAGE_NAME"
    "$ADB" -s "$serial" shell monkey -p "$PACKAGE_NAME" -c android.intent.category.LAUNCHER 1
    ;;

  logs)
    serial="$(device_serial "${1:-}")"
    printf '正在显示 %s 的 Godot 日志；按 Ctrl-C 结束。\n' "$serial"
    "$ADB" -s "$serial" logcat -v color Godot:V godot:V DEBUG:V AndroidRuntime:E '*:S'
    ;;

  help|-h|--help)
    usage
    ;;

  *)
    usage >&2
    fail "未知命令：$action"
    ;;
esac
