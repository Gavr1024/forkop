#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SLOTS_UC="$ROOT_DIR/forkop/files/usr/lib/config/slots.uc"
BIN="$ROOT_DIR/forkop/files/usr/bin/forkop"
FORKOP_JS="$ROOT_DIR/luci-app-forkop/htdocs/luci-static/resources/view/forkop/forkop.js"
SLOTS_JS="$ROOT_DIR/luci-app-forkop/htdocs/luci-static/resources/view/forkop/slots.js"
CONFIG="$ROOT_DIR/forkop/files/etc/config/forkop"
LIFECYCLE="$ROOT_DIR/forkop/files/usr/lib/service/lifecycle.uc"
PO_SRC="$ROOT_DIR/fe-app-forkop/locales/forkop.ru.po"
PO_PKG="$ROOT_DIR/luci-app-forkop/po/ru/forkop.po"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_text() {
  grep -Fq "$2" "$1" || fail "$1 must contain: $2"
}

require_text "$SLOTS_UC" "/etc/forkop/slots"
require_text "$SLOTS_UC" "ping"
require_text "$SLOTS_UC" "slots_auto_switch"
require_text "$BIN" "slot_status"
require_text "$BIN" "slot_save"
require_text "$BIN" "slot_apply"
require_text "$BIN" "slot_probe_if_due"
require_text "$FORKOP_JS" "view.forkop.slots"
require_text "$FORKOP_JS" "Config slots"
require_text "$SLOTS_JS" "Save current config"
require_text "$SLOTS_JS" "Enable auto-switch"
require_text "$SLOTS_JS" "confirmSlotSave"
require_text "$SLOTS_JS" "Overwrite this slot with the current Forkop config?"
require_text "$SLOTS_JS" "fkp-slots__btn"
require_text "$SLOTS_JS" "input type=\"button\""
require_text "$SLOTS_JS" "text-align: center"
require_text "$CONFIG" "slots_ping_host"
require_text "$CONFIG" "slots_ping_host_backup"
require_text "$SLOTS_UC" "collect_hosts"
require_text "$SLOTS_UC" "sync_switch_settings_to_slots"
require_text "$SLOTS_JS" "Backup host to ping"
require_text "$LIFECYCLE" "config/slots.uc"
require_text "$PO_SRC" "Слоты конфига"
require_text "$PO_PKG" "Слоты конфига"
require_text "$PO_SRC" "Включить автопереключение"
require_text "$PO_PKG" "Включить автопереключение"

python3 - "$SLOTS_JS" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
if "function escapeHtml" not in text:
    raise SystemExit("slots.js must define escapeHtml")
if ("&" + "quot;") not in text:
    raise SystemExit("escapeHtml must keep quote entities (broken JS if decoded)")
print("escapeHtml entities ok")
PY

if command -v node >/dev/null 2>&1; then
  node -e 'new Function(require("fs").readFileSync(process.argv[1], "utf8"))' "$SLOTS_JS" \
    || fail "slots.js must parse as a LuCI module"
fi

cmp -s "$PO_SRC" "$PO_PKG" || fail "Russian catalogs must stay synchronized"

printf 'slots checks passed\n'
require_text "$SLOTS_UC" "parse_ping_ms"
require_text "$SLOTS_JS" "Host is unreachable"
require_text "$SLOTS_UC" "prepare_boot_slot"
require_text "$SLOTS_UC" "try_fallback_slot"
require_text "$SLOTS_UC" "restart_after_apply"
require_text "$LIFECYCLE" "prepare-boot-slot"
require_text "$LIFECYCLE" "try-fallback-slot"
