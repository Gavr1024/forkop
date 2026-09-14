# Forkop 1.0.5 patch set

Based on upstream https://github.com/ushan0v/forkop main (1.0.5).

## What is in this tree

### sing-box 1.14
- Removed `dns.independent_cache`.
- Bypass DNS uses `evaluate` + `match_response` instead of legacy `ip_cidr`.
- Remote rule-sets use `http_clients` / `http_client.detour` instead of `download_detour`.

### Device exclusions (`forkop-exclusions-fix-4`)
- Settings list `routing_excluded_ips`: full Forkop bypass (nft early return + real DNS + safety route).
- Section list `excluded_source_ips`: invert source match for that section only.
- DNS for excluded devices goes to **bootstrap DNS**, not dnsmasq. dnsmasq is pointed at FakeIP (`127.0.0.42`), so the old path gave FakeIP and then skipped TPROXY — apps like ivi.ru failed as if they were proxied.
- Hostname/IP in the list expands to **all** v4 and v6 addresses of that device (DHCP leases + odhcpd hosts). LuCI save does the same from host hints.

### Hostname crash fix (`forkop-exclusions-fix-3`)
LuCI often stores a DHCP name (`motorola-edge-60-fusion`) instead of an IP.
Old ucode then threw `Type error: left-hand side is not a function`.

Now:
- IP/CIDR is validated locally (no `!obj.method()` / `|| fn()`).
- Hostnames are resolved from `/tmp/dhcp.leases`, `/var/dhcp.leases`, `/tmp/hosts/odhcpd`, `/etc/hosts`.
- Unresolvable names are skipped; generation does not abort.
- Marker string in generator: `forkop-exclusions-fix-4`.

### rpcd ACL
Duplicate `/var/run/forkop/*` grants as `/tmp/run/forkop/*` for rpcd-mod-file 2026.07.19.

### Local list cache
- Settings flag `persist_lists_locally` stores selected community lists and remote rule-sets in `/etc/forkop/list-cache`.
- Cached files are used as `type: local` backups when the online repository is unavailable.
- If `download_lists_via_proxy` is enabled, the selected section/mixed inbound is brought up before the download.
- Dashboard shows cached lists, sizes, mtime, and status.

### Dual-core Xray (`xray-dual-core`)
Forkop can run **sing-box and Xray at the same time** without two TPROXY/FakeIP stacks.

- Components tab: install / update / remove **Xray-core** from [XTLS/Xray-core](https://github.com/XTLS/Xray-core) (same job model as sing-box / ByeDPI). Binary lands at `/usr/bin/xray`, geo files at `/usr/share/xray` and `/etc/xray`. Autostart of the managed `/etc/init.d/xray` stays disabled — Forkop starts it.
- Section setting **Proxy core**: `sing-box` (default) or `Xray`. Only connection/proxy/outbound/vpn sections have the selector.
- Share-links (`vless://`, `vmess://`, `trojan://`, `ss://`, `socks://`, `hy2://` / `hysteria2://`) and pasted JSON are converted to **Xray 26 simplified outbounds** (`settings.address/port/id`, `encryption: "none"`, `streamSettings.method` + `network`). Classic `vnext`/`servers` JSON is flattened. Hysteria2 is emitted as `protocol: hysteria` + `method/network: hysteria` with `hysteriaSettings.auth`. `type=raw` and `xtls-rprx-vision-udp443` parse. HTTP/h2 transport maps to xhttp (HTTP transport was removed in 26.x).
- Interface bindings on an Xray section become `freedom` outbounds with `sockopt.interface` + `domainStrategy: UseIP` (plus the outbound mark). A section that only binds an interface (no share-links) is valid and starts. Cascade (`outbound_detour`) from an Xray proxy section uses `sockopt.dialerProxy`: Xray→Xray chains natively to the target outbound tag (e.g. the interface freedom); Xray→sing-box hops through a dedicated SOCKS inbound on `10908+` whose route rule is inserted **before** domain/IP matchers. Interface/freedom leaves are not given `dialerProxy` (same as sing-box).
- Lifecycle: generate xray config **before** sing-box (so the port map exists), start xray **before** sing-box, stop xray **after** sing-box. If no section uses Xray, generation is skipped so a plain sing-box start is not blocked.
- System information always shows the Xray version. Diagnostics always run the Xray checks (installed, version ≥ 24.12.0, service, autostart disabled, process, listening ports, configured sections).
- Monitoring: **Core** column on Active/Closed, plus a **Cores** tab (domain → Xray or sing-box).
- Dashboard (информационная панель): Services widget shows Xray Running/Stopped/Not installed. System info counts outbounds per core (`sing-box N · Xray M`). Core badge is on the **section title only**, not on outbound cards. Multiple share-links in an Xray section appear as a Clash selector (one SOCKS inbound per node on `11008+`), so every outbound is visible and selectable like sing-box. Process status uses pidof/procd/ubus and the sidecar listen ports — `pgrep -x xray` alone was a false negative while traffic still went through the sidecar.
- Interface cards on an Xray section show the UCI interface name (`VNI`, `awg1`), not the generator tag (`VNI-iface-1`).
- URLTest / Priority on an Xray section is a Clash `urltest` / selector over the SOCKS leaves (iface Direct is excluded from the probe set). The dashboard can select the group the same way as sing-box.
- Diagnostics: **Show Xray config** next to **Show sing-box config** (raw dump + Hide values). CLI: `forkop show_xray_config`.
- Components: Xray has the same **Install specific version** dropdown as sing-box. Version lists for sing-box and Xray are fetched from GitHub **in the browser in parallel** when the Updates tab opens, so they do not contend for the router component-action lock.

### Restart interfaces after start
Settings flag `restart_interfaces_after_start` plus a NetworkSelect list and delay (0–60 s). After a successful Forkop **start**, the selected UCI interfaces are bounced with `/sbin/ifup` in the background. Ping/DNS are not touched. Does not run on reload.

### Config slots UI
Slots tab: left-aligned LuCI layout (no duplicate heading), compact cards, own `input type="button"` controls (LuCI `.cbi-button` on `<button>` drew empty boxes), confirmation before **Save current config**.

New modules: `forkop/files/usr/lib/xray/{constants,outbound,generator,runtime}.uc`.

### Router traffic through a section (`router-traffic-section`)
Settings flag **Route the router's own traffic** plus a section selector. Off by default.

When both the flag and a section are set, Forkop intercepts **IPv4 TCP from the router itself** (apk, wget, LuCI outbound HTTP) and forces it through that section:

- sing-box `type: redirect` inbound on `127.0.0.1:1604` only. No `network` field (sing-box 1.14 `DisallowUnknownFields`). No second IPv6 inbound.
- Early route rule `inbound: redirect-in → <section>-out`, inserted after sniff/hijack-dns so domain lists cannot steal this traffic. Xray sections work because they already appear as SOCKS outbounds with that tag.
- nft `nat hook output` DNAT (`redirect to :1604`) is applied **after** sing-box is stable. Skips ICMP, DNS 53, NTP 123 (if excluded), `localv4`, and sockets with the outbound mark (proxy dials to the VPS).
- Dest-based OUTPUT TPROXY marks are skipped while this is on, so listed destinations are not blackholed into table `forkop`.
- Ping stays direct. IPv6 from the router is not intercepted.

Leftover `route_router_traffic=1` without a section (old checkbox) is treated as off and cleared by migration `router_traffic_section`.

Copy **settings.js, generator.uc, route.uc, constants.uc, nft/apply.uc, lifecycle.uc, state.uc, validator.uc** together and **restart Forkop**, not only Save. Copying nft/lifecycle without generator DNATs to a closed port.

## Build

On a Linux host with OpenWrt SDK dependencies (see `build.sh`):

```bash
./build.sh 1.0.5 ./dist
```

Produces:
- `forkop_1.0.5.ipk`
- `luci-app-forkop_1.0.5.ipk`
- `luci-i18n-forkop-ru_1.0.5.ipk`
- matching `.apk` for OpenWrt 25.12

Install on the router:

```sh
opkg install forkop_1.0.5.ipk
opkg install luci-app-forkop_1.0.5.ipk
opkg install luci-i18n-forkop-ru_1.0.5.ipk
/etc/init.d/rpcd restart
/etc/init.d/forkop restart
```

Hard-refresh LuCI (Ctrl+F5).

## Manual copy onto an existing 1.0.5 install

```sh
cp forkop/files/usr/lib/singbox/generator.uc /usr/lib/forkop/singbox/generator.uc
cp forkop/files/usr/lib/nft/apply.uc         /usr/lib/forkop/nft/apply.uc
cp forkop/files/usr/lib/singbox/runtime.uc   /usr/lib/forkop/singbox/runtime.uc
cp luci-app-forkop/htdocs/luci-static/resources/view/forkop/settings.js \
   /www/luci-static/resources/view/forkop/settings.js
cp luci-app-forkop/htdocs/luci-static/resources/view/forkop/section.js \
   /www/luci-static/resources/view/forkop/section.js
cp luci-app-forkop/htdocs/luci-static/resources/view/forkop/local_devices.js \
   /www/luci-static/resources/view/forkop/local_devices.js
cp luci-app-forkop/root/usr/share/rpcd/acl.d/luci-app-forkop.json \
   /usr/share/rpcd/acl.d/luci-app-forkop.json
chmod 0644 /usr/share/rpcd/acl.d/luci-app-forkop.json
/etc/init.d/rpcd restart
/etc/init.d/forkop restart
grep -n forkop-exclusions-fix-4 /usr/lib/forkop/singbox/generator.uc
```

The last grep must print a line. Empty output means the file was not replaced.

### Dual-core Xray files (share-link → Xray 26 JSON)

If Forkop is already installed, copy these and reload:

```sh
mkdir -p /usr/lib/forkop/xray
cp forkop/files/usr/lib/xray/constants.uc /usr/lib/forkop/xray/constants.uc
cp forkop/files/usr/lib/xray/outbound.uc /usr/lib/forkop/xray/outbound.uc
cp forkop/files/usr/lib/xray/generator.uc /usr/lib/forkop/xray/generator.uc
cp forkop/files/usr/lib/xray/runtime.uc /usr/lib/forkop/xray/runtime.uc
cp forkop/files/usr/lib/subscription/parser.uc /usr/lib/forkop/subscription/parser.uc
cp forkop/files/usr/lib/singbox/generator.uc /usr/lib/forkop/singbox/generator.uc
cp forkop/files/usr/lib/singbox/route.uc /usr/lib/forkop/singbox/route.uc
cp forkop/files/usr/lib/singbox/constants.uc /usr/lib/forkop/singbox/constants.uc
cp forkop/files/usr/lib/service/ui.uc /usr/lib/forkop/service/ui.uc
cp forkop/files/usr/lib/service/lifecycle.uc /usr/lib/forkop/service/lifecycle.uc
cp forkop/files/usr/lib/components/action.uc /usr/lib/forkop/components/action.uc
cp forkop/files/usr/lib/diagnostics/runtime.uc /usr/lib/forkop/diagnostics/runtime.uc
cp forkop/files/usr/lib/diagnostics/status.uc /usr/lib/forkop/diagnostics/status.uc
cp forkop/files/usr/lib/nft/apply.uc /usr/lib/forkop/nft/apply.uc
cp forkop/files/usr/lib/service/state.uc /usr/lib/forkop/service/state.uc
cp forkop/files/usr/lib/config/validator.uc /usr/lib/forkop/config/validator.uc
cp forkop/files/usr/lib/config/migration.uc /usr/lib/forkop/config/migration.uc
cp forkop/files/usr/lib/core/constants.uc /usr/lib/forkop/core/constants.uc
cp forkop/files/usr/bin/forkop /usr/bin/forkop
cp luci-app-forkop/htdocs/luci-static/resources/view/forkop/main.js \
   /www/luci-static/resources/view/forkop/main.js
cp luci-app-forkop/htdocs/luci-static/resources/view/forkop/settings.js \
   /www/luci-static/resources/view/forkop/settings.js
cp luci-app-forkop/htdocs/luci-static/resources/view/forkop/slots.js \
   /www/luci-static/resources/view/forkop/slots.js
cp luci-app-forkop/po/ru/forkop.po /usr/lib/lua/luci/i18n/forkop.ru.po 2>/dev/null || true
/etc/init.d/rpcd restart
/etc/init.d/forkop restart
```

## Config slots
- New LuCI tab saves `/etc/config/forkop` into online/offline slots.
- Auto-switch applies a slot after repeated ping success/failure.
