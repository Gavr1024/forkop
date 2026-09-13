#!/usr/bin/env ucode

const XRAY_BIN = "/usr/bin/xray";
const XRAY_CONFIG = "/etc/xray/config.json";
const XRAY_SERVICE_INIT = "/etc/init.d/xray";
const XRAY_MANAGED_SERVICE_MARKER = "Forkop managed xray service";
const XRAY_SOCKS_LISTEN = "127.0.0.1";
const XRAY_SOCKS_PORT_BASE = 10808;
const XRAY_CASCADE_PORT_BASE = 10908;
const XRAY_NODE_PORT_BASE = 11008;
const XRAY_STATE_DIR = "/var/run/forkop/xray";
const XRAY_PORTS_FILE = "/var/run/forkop/xray-ports.json";
const XRAY_NODES_FILE = "/var/run/forkop/xray-nodes.json";
const XRAY_CASCADE_FILE = "/var/run/forkop/xray-cascade.json";
const XRAY_VERSION_STATE_FILE = "/etc/forkop/xray-version";
const XRAY_RELEASE_REPO = "XTLS/Xray-core";
const XRAY_REQUIRED_VERSION = "24.12.0";
const TMP_XRAY_FOLDER = "/tmp/xray";
const OUTBOUND_MARK = 134217728;
const FREEDOM_TAG = "direct";
const BLACKHOLE_TAG = "block";

function as_string(value) {
    return value == null ? "" : "" + value;
}

function inbound_tag(section_name) {
    return "socks-in-" + as_string(section_name);
}

function node_inbound_tag(section_name, index) {
    return "socks-in-" + as_string(section_name) + "-" + as_string(index);
}

function outbound_tag(section_name, index) {
    if (index == null || index == "")
        return "xray-" + as_string(section_name);
    return "xray-" + as_string(section_name) + "-" + as_string(index);
}

function balancer_tag(section_name) {
    return "balancer-" + as_string(section_name);
}

return {
    XRAY_BIN,
    XRAY_CONFIG,
    XRAY_SERVICE_INIT,
    XRAY_MANAGED_SERVICE_MARKER,
    XRAY_SOCKS_LISTEN,
    XRAY_SOCKS_PORT_BASE,
    XRAY_CASCADE_PORT_BASE,
    XRAY_NODE_PORT_BASE,
    XRAY_STATE_DIR,
    XRAY_PORTS_FILE,
    XRAY_NODES_FILE,
    XRAY_CASCADE_FILE,
    XRAY_VERSION_STATE_FILE,
    XRAY_RELEASE_REPO,
    XRAY_REQUIRED_VERSION,
    TMP_XRAY_FOLDER,
    OUTBOUND_MARK,
    FREEDOM_TAG,
    BLACKHOLE_TAG,
    inbound_tag,
    node_inbound_tag,
    outbound_tag,
    balancer_tag
};
