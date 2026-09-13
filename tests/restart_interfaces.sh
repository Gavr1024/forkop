#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS_JS="$ROOT_DIR/luci-app-forkop/htdocs/luci-static/resources/view/forkop/settings.js"
LIFECYCLE="$ROOT_DIR/forkop/files/usr/lib/service/lifecycle.uc"
CONFIG="$ROOT_DIR/forkop/files/etc/config/forkop"
PO_SRC="$ROOT_DIR/fe-app-forkop/locales/forkop.ru.po"
PO_PKG="$ROOT_DIR/luci-app-forkop/po/ru/forkop.po"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_text() {
  grep -Fq "$2" "$1" || fail "$1 must contain: $2"
}

require_text "$SETTINGS_JS" "restart_interfaces_after_start"
require_text "$SETTINGS_JS" "restart_interfaces_delay"
require_text "$SETTINGS_JS" "widgets.NetworkSelect"
require_text "$SETTINGS_JS" '"Restart interfaces after start"'
require_text "$SETTINGS_JS" '"Interfaces to restart"'
require_text "$SETTINGS_JS" '"Restart delay"'
require_text "$LIFECYCLE" "function schedule_interface_restarts"
require_text "$LIFECYCLE" "/sbin/ifup"
require_text "$LIFECYCLE" "restart_interfaces_after_start"
require_text "$CONFIG" "restart_interfaces_after_start"
require_text "$CONFIG" "restart_interfaces_delay"
require_text "$PO_SRC" "Перезапускать интерфейсы после старта"
require_text "$PO_PKG" "Перезапускать интерфейсы после старта"
require_text "$PO_SRC" "Задержка перезапуска"
require_text "$PO_PKG" "Задержка перезапуска"

if awk '
  $0 ~ /^function start_impl\(/ { in_fn = 1 }
  in_fn && $0 ~ /^function / && $0 !~ /^function start_impl\(/ { in_fn = 0 }
  in_fn && $0 ~ /schedule_interface_restarts\(\)/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$LIFECYCLE"; then
  :
else
  fail "start_impl must schedule interface restarts after a successful start"
fi

printf 'restart interfaces checks passed\n'
