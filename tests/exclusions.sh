#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATOR="$ROOT_DIR/forkop/files/usr/lib/singbox/generator.uc"
NFT="$ROOT_DIR/forkop/files/usr/lib/nft/apply.uc"
SETTINGS_JS="$ROOT_DIR/luci-app-forkop/htdocs/luci-static/resources/view/forkop/settings.js"
DEVICES_JS="$ROOT_DIR/luci-app-forkop/htdocs/luci-static/resources/view/forkop/local_devices.js"
SECTION_JS="$ROOT_DIR/luci-app-forkop/htdocs/luci-static/resources/view/forkop/section.js"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_text() {
  grep -Fq "$2" "$1" || fail "$1 must contain: $2"
}

require_text "$GENERATOR" "forkop-exclusions-fix-4"
require_text "$GENERATOR" "function expanded_ips_for_source_value"
require_text "$GENERATOR" "function ips_from_dhcp_lease_name"
require_text "$GENERATOR" "BOOTSTRAP_DNS_SERVER_TAG"
require_text "$GENERATOR" "disable_cache: true"

if ! awk '
  $0 ~ /function add_global_routing_exclusions\(/ { in_fn = 1 }
  in_fn && $0 ~ /^function / && $0 !~ /function add_global_routing_exclusions\(/ { in_fn = 0 }
  in_fn && /DNSMASQ_DNS_SERVER_TAG/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$GENERATOR"; then
  :
else
  fail "excluded devices must not resolve DNS via dnsmasq/FakeIP"
fi

awk '
  $0 ~ /function add_global_routing_exclusions\(/ { in_fn = 1 }
  in_fn && $0 ~ /^function / && $0 !~ /function add_global_routing_exclusions\(/ { in_fn = 0 }
  in_fn && /BOOTSTRAP_DNS_SERVER_TAG/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$GENERATOR" || fail "excluded device DNS must go to bootstrap (real) DNS"

require_text "$NFT" "function apply_expanded_source_values"
require_text "$NFT" "function apply_ips_from_lease_name"
require_text "$NFT" "EXCLUDED_SOURCE_SET"
require_text "$SETTINGS_JS" "resolveLocalDeviceListValues"
require_text "$DEVICES_JS" "function resolveLocalDeviceListValues"
require_text "$SECTION_JS" "resolveLocalDeviceListValues"

printf 'exclusion checks passed\n'
