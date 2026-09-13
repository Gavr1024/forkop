#!/usr/bin/env ucode

let fs = require("fs");
let uci_core = require("core.uci");
let connections = require("config.connections");
let parser = require("subscription.parser");
let runtime_subscription = require("singbox.subscription");
let runtime_url = require("core.url");
let xray_constants = require("xray.constants");
let xray_outbound = require("xray.outbound");

function as_string(value) {
    return value == null ? "" : "" + value;
}

function trim(value) {
    return replace(as_string(value), /^[ \t\r\n]+|[ \t\r\n]+$/g, "");
}

function object_or_empty(value) {
    return type(value) == "object" ? value : {};
}

function array_or_empty(value) {
    return type(value) == "array" ? value : [];
}

function option(section, key, fallback) {
    let value = section[key];
    if (value == null || value == "")
        return fallback;
    return as_string(value);
}

function bool_option(section, key, fallback) {
    let value = section[key];
    if (value == null)
        return fallback ? true : false;
    value = as_string(value);
    return value == "1" || value == "true" || value == "yes" || value == "on";
}

function generate_fail(reason) {
    warn(as_string(reason), "\n");
    exit(1);
}

function ensure_dir(path) {
    path = as_string(path);
    if (path == "" || path == "/")
        return true;
    if (fs.stat(path) != null)
        return true;
    let slash = rindex(path, "/");
    let parent = slash <= 0 ? "" : substr(path, 0, slash);
    if (parent != "" && !ensure_dir(parent))
        return false;
    return fs.mkdir(path, 0755) || fs.stat(path) != null;
}

function write_json_file(path, value) {
    let tmp = as_string(path) + ".tmp";
    if (!fs.writefile(tmp, sprintf("%J\n", value)))
        return false;
    return fs.rename(tmp, path);
}

function parse_json_text(value) {
    try {
        return json(as_string(value));
    }
    catch (e) {
        return null;
    }
}

function unique_tag(base, taken) {
    base = as_string(base);
    if (base == "")
        base = "proxy";
    if (!taken[base])
        return base;
    for (let i = 1; i < 100000; i++) {
        let candidate = base + "-" + i;
        if (!taken[candidate])
            return candidate;
    }
    return base + "-overflow";
}

function is_leaf_ir(outbound) {
    outbound = object_or_empty(outbound);
    let kind = as_string(outbound.type || "");
    if (kind == "selector" || kind == "urltest" || kind == "dns" || kind == "block" || kind == "direct")
        return false;
    return xray_outbound.supported_ir(outbound);
}

function freedom_outbound() {
    return {
        protocol: "freedom",
        tag: xray_constants.FREEDOM_TAG,
        streamSettings: { sockopt: xray_outbound.sockopt() }
    };
}

function blackhole_outbound() {
    return {
        protocol: "blackhole",
        tag: xray_constants.BLACKHOLE_TAG
    };
}

function socks_inbound(tag, port) {
    return {
        tag: as_string(tag),
        listen: xray_constants.XRAY_SOCKS_LISTEN,
        port: int(port, 10),
        protocol: "socks",
        settings: {
            udp: true,
            auth: "noauth",
            ip: xray_constants.XRAY_SOCKS_LISTEN
        },
        sniffing: {
            enabled: true,
            destOverride: [ "http", "tls", "quic" ],
            routeOnly: true
        }
    };
}

function prepare_share_link(link) {
    link = trim(link);
    if (link == "")
        return "";
    if (lc(substr(link, 0, 8)) == "vmess://")
        return link;
    let decoded = trim(runtime_url.decode(link));
    return decoded != "" ? decoded : link;
}

function share_link_scheme(link) {
    let marker = index(as_string(link), "://");
    return marker > 0 ? lc(substr(link, 0, marker)) : "unknown";
}

function add_converted(config, taken, ir, tag_base, display_names, display_name) {
    let tag = unique_tag(tag_base, taken);
    let converted = xray_outbound.convert_ir(ir, tag);
    if (converted == null)
        return "";
    taken[tag] = true;
    push(config.outbounds, converted);
    if (type(display_names) == "object") {
        let name = trim(as_string(display_name || ""));
        if (name == "")
            name = trim(as_string(ir.tag || ir.remark || ""));
        display_names[tag] = name != "" ? name : tag;
    }
    return tag;
}

function add_manual_links(config, taken, section, tags, display_names) {
    let section_name = as_string(section[".name"]);
    let links = connections.connection_urls(section);
    for (let i = 0; i < length(links); i++) {
        let raw = prepare_share_link(links[i]);
        let ir = parser.parse_share_link(raw);
        if (type(ir) != "object")
            ir = parser.parse_share_link(trim(as_string(links[i])));
        if (type(ir) != "object") {
            warn("xray: skipped invalid share-link (", share_link_scheme(raw), ") in section '", section_name, "'\n");
            continue;
        }
        let tag_base = as_string(ir.tag || (section_name + "-" + (i + 1)));
        let tag = add_converted(config, taken, ir, tag_base, display_names, ir.tag || ir.remark);
        if (tag != "")
            push(tags, tag);
        else
            warn("xray: share-link (", as_string(ir.type || share_link_scheme(raw)), ") in section '", section_name, "' could not be converted to Xray 26 outbound\n");
    }
}

function add_json_outbounds(config, taken, section, tags, display_names) {
    let section_name = as_string(section[".name"]);
    let items = connections.outbound_jsons(section);
    for (let i = 0; i < length(items); i++) {
        let parsed = parse_json_text(items[i]);
        if (type(parsed) != "object") {
            generate_fail("xray JSON outbound is invalid in section " + section_name);
        }
        let tag_base = as_string(parsed.tag || (section_name + "-json-" + (i + 1)));
        let tag = add_converted(config, taken, parsed, tag_base, display_names, parsed.tag);
        if (tag != "")
            push(tags, tag);
        else
            warn("xray: JSON outbound in section '", section_name, "' is not supported\n");
    }
}

function add_subscriptions(config, taken, section, tags, display_names) {
    let section_name = as_string(section[".name"]);
    let urls = connections.subscription_urls(section);
    for (let i = 0; i < length(urls); i++) {
        let source_section = runtime_subscription.source_id(section_name, i + 1);
        if (!runtime_subscription.source_cache_is_current(
            source_section,
            urls[i],
            connections.subscription_user_agent(section, urls[i]),
            connections.subscription_hwid(section, urls[i])
        ))
            continue;

        let outbounds = runtime_subscription.read_source_outbounds(source_section);
        let node_prefix = trim(as_string(connections.subscription_node_prefix(section, urls[i])));
        for (let outbound in outbounds) {
            if (!is_leaf_ir(outbound))
                continue;
            let display = as_string(outbound.remark || outbound.tag || "server");
            if (node_prefix != "")
                display = node_prefix + " " + display;
            let tag = add_converted(config, taken, outbound, display, display_names, display);
            if (tag != "")
                push(tags, tag);
        }
    }
}

function section_uses_urltest(section) {
    return length(connections.urltests(section)) > 0;
}

function urltest_probe_url(section) {
    for (let urltest_id in connections.urltests(section))
        return connections.urltest_testing_url(section, urltest_id);
    return "https://www.gstatic.com/generate_204";
}

function urltest_interval(section) {
    for (let urltest_id in connections.urltests(section))
        return connections.urltest_check_interval(section, urltest_id);
    return "3m";
}

function add_interfaces(config, taken, section, tags, display_names) {
    let section_name = as_string(section[".name"]);
    let items = connections.interfaces(section);
    for (let i = 0; i < length(items); i++) {
        let iface = trim(as_string(items[i]));
        if (iface == "")
            continue;
        let tag_base = section_name + "-iface-" + (i + 1);
        let tag = unique_tag(tag_base, taken);
        let converted = xray_outbound.convert_interface(iface, tag);
        if (converted == null)
            continue;
        taken[tag] = true;
        push(config.outbounds, converted);
        push(tags, tag);
        if (type(display_names) == "object")
            display_names[tag] = iface;
    }
}

function detour_target_name(section) {
    if (!bool_option(section, "outbound_detour_enabled", false))
        return "";
    return trim(option(section, "outbound_detour_section", ""));
}

function section_index_by_name(sections, name) {
    name = as_string(name);
    for (let i = 0; i < length(sections); i++) {
        if (as_string(sections[i][".name"]) == name)
            return i;
    }
    return -1;
}

function outbound_by_tag(config, tag) {
    tag = as_string(tag);
    for (let outbound in array_or_empty(config.outbounds)) {
        if (type(outbound) == "object" && as_string(outbound.tag || "") == tag)
            return outbound;
    }
    return null;
}

function is_chainable_leaf(outbound) {
    outbound = object_or_empty(outbound);
    let proto = lc(as_string(outbound.protocol || ""));
    if (proto == "" || proto == "freedom" || proto == "blackhole" || proto == "dns")
        return false;
    return true;
}

function detour_leaf_tags(config, tags) {
    let result = [];
    for (let tag in array_or_empty(tags)) {
        if (is_chainable_leaf(outbound_by_tag(config, tag)))
            push(result, as_string(tag));
    }
    return result;
}

function apply_detour_to_leaf_tags(config, tags, via_tag) {
    via_tag = as_string(via_tag);
    if (via_tag == "")
        return;
    for (let outbound in array_or_empty(config.outbounds)) {
        if (!is_chainable_leaf(outbound))
            continue;
        let tag = as_string(outbound.tag || "");
        for (let leaf in tags) {
            if (as_string(leaf) == tag) {
                xray_outbound.apply_dialer_proxy(outbound, via_tag);
                break;
            }
        }
    }
}

function add_via_socks(config, taken, target, port) {
    let via_tag = unique_tag("via-" + as_string(target), taken);
    let via = xray_outbound.socks_chain_outbound(via_tag, port);
    if (via == null)
        return "";
    taken[via_tag] = true;
    push(config.outbounds, via);
    return via_tag;
}

function apply_section_detour(config, taken, section, tags, xray_sections, connection_sections, cascade, deferred) {
    let target = detour_target_name(section);
    if (target == "")
        return;
    if (target == as_string(section[".name"]))
        generate_fail("xray cascade for '" + target + "' cannot point to itself");

    let leaf_tags = detour_leaf_tags(config, tags);
    if (length(leaf_tags) == 0)
        return;

    let xray_index = section_index_by_name(xray_sections, target);
    if (xray_index >= 0) {
        push(deferred, {
            tags: leaf_tags,
            target: target,
            xray_index: xray_index
        });
        return;
    }

    let conn_index = section_index_by_name(connection_sections, target);
    if (conn_index < 0)
        generate_fail("xray cascade target '" + target + "' was not found");
    let port = xray_constants.XRAY_CASCADE_PORT_BASE + conn_index;
    cascade[target] = port;
    let via_tag = add_via_socks(config, taken, target, port);
    if (via_tag == "")
        generate_fail("xray cascade target '" + target + "' has no listen port");
    apply_detour_to_leaf_tags(config, leaf_tags, via_tag);
}

function target_inbound_rule(config, inbound) {
    inbound = as_string(inbound);
    for (let rule in array_or_empty(object_or_empty(config.routing).rules)) {
        if (type(rule) != "object")
            continue;
        for (let tag in array_or_empty(rule.inboundTag)) {
            if (as_string(tag) == inbound)
                return rule;
        }
    }
    return null;
}

function resolve_deferred_xray_detours(config, taken, deferred) {
    for (let item in array_or_empty(deferred)) {
        item = object_or_empty(item);
        let target = as_string(item.target || "");
        let rule = target_inbound_rule(config, xray_constants.inbound_tag(target));
        let via_tag = "";
        if (type(rule) == "object" && as_string(rule.outboundTag || "") != "")
            via_tag = as_string(rule.outboundTag);
        else {
            let port = xray_constants.XRAY_SOCKS_PORT_BASE + int(item.xray_index || 0);
            via_tag = add_via_socks(config, taken, target, port);
        }
        if (via_tag == "")
            generate_fail("xray cascade target '" + target + "' has no usable outbound");
        apply_detour_to_leaf_tags(config, array_or_empty(item.tags), via_tag);
    }
}

function add_section(config, taken, section, ports, index, xray_sections, connection_sections, cascade, deferred, nodes_map, node_seq) {
    let section_name = as_string(section[".name"]);
    let tags = [];
    let display_names = {};

    add_manual_links(config, taken, section, tags, display_names);
    add_subscriptions(config, taken, section, tags, display_names);
    add_json_outbounds(config, taken, section, tags, display_names);
    add_interfaces(config, taken, section, tags, display_names);
    apply_section_detour(config, taken, section, tags, xray_sections, connection_sections, cascade, deferred);

    if (length(tags) == 0)
        generate_fail("xray section '" + section_name + "' has no usable outbounds");

    let port = xray_constants.XRAY_SOCKS_PORT_BASE + index;
    push(config.inbounds, socks_inbound(xray_constants.inbound_tag(section_name), port));
    ports[section_name] = port;

    let inbound = xray_constants.inbound_tag(section_name);
    if (section_uses_urltest(section) && length(tags) > 1) {
        let balancer = xray_constants.balancer_tag(section_name);
        push(config.routing.balancers, {
            tag: balancer,
            selector: tags,
            fallbackTag: tags[0],
            strategy: { type: "leastPing" }
        });
        push(config.routing.rules, {
            type: "field",
            inboundTag: [ inbound ],
            balancerTag: balancer
        });
        if (type(config.observatory) != "object")
            config.observatory = { subjectSelector: [], probeUrl: urltest_probe_url(section), probeInterval: urltest_interval(section) };
        for (let tag in tags)
            push(config.observatory.subjectSelector, tag);
    }
    else {
        push(config.routing.rules, {
            type: "field",
            inboundTag: [ inbound ],
            outboundTag: tags[0]
        });
    }

    let section_nodes = [];
    if (type(node_seq) != "object")
        node_seq = { next: xray_constants.XRAY_NODE_PORT_BASE };
    for (let i = 0; i < length(tags); i++) {
        let tag = as_string(tags[i]);
        let node_port = int(node_seq.next || xray_constants.XRAY_NODE_PORT_BASE);
        if (node_port < xray_constants.XRAY_NODE_PORT_BASE)
            node_port = xray_constants.XRAY_NODE_PORT_BASE;
        node_seq.next = node_port + 1;
        let node_inbound = xray_constants.node_inbound_tag(section_name, i + 1);
        push(config.inbounds, socks_inbound(node_inbound, node_port));
        push(config.routing.rules, {
            type: "field",
            inboundTag: [ node_inbound ],
            outboundTag: tag
        });
        let kind = "proxy";
        let outbound = outbound_by_tag(config, tag);
        let iface_name = "";
        if (lc(as_string(object_or_empty(outbound).protocol || "")) == "freedom") {
            kind = "iface";
            iface_name = trim(as_string(object_or_empty(object_or_empty(outbound.streamSettings).sockopt).interface || ""));
        }
        let node_name = trim(as_string(display_names[tag] || ""));
        if (node_name == "")
            node_name = iface_name != "" ? iface_name : tag;
        push(section_nodes, {
            tag: tag,
            port: node_port,
            name: node_name,
            kind: kind,
            protocol: as_string(object_or_empty(outbound).protocol || "")
        });
    }
    nodes_map[section_name] = section_nodes;
}

function enabled_xray_sections() {
    let result = [];
    if (!uci_core.available())
        return result;
    for (let section in uci_core.section_objects("forkop", "section")) {
        section = object_or_empty(section);
        let enabled = section.enabled == null ? "1" : as_string(section.enabled);
        if (enabled == "0")
            continue;
        if (!connections.is_connections_action(option(section, "action", "")))
            continue;
        if (connections.proxy_core(section) != "xray")
            continue;
        push(result, section);
    }
    return result;
}

function enabled_connection_sections() {
    let result = [];
    if (!uci_core.available())
        return result;
    for (let section in uci_core.section_objects("forkop", "section")) {
        section = object_or_empty(section);
        let enabled = section.enabled == null ? "1" : as_string(section.enabled);
        if (enabled == "0")
            continue;
        if (!connections.is_connections_action(option(section, "action", "")))
            continue;
        push(result, section);
    }
    return result;
}

function empty_config() {
    return {
        log: { loglevel: "warning" },
        inbounds: [],
        outbounds: [ freedom_outbound(), blackhole_outbound() ],
        routing: {
            domainStrategy: "AsIs",
            rules: [],
            balancers: []
        }
    };
}

function generate_config(output_path, ports_path) {
    output_path = as_string(output_path || xray_constants.XRAY_CONFIG);
    ports_path = as_string(ports_path || xray_constants.XRAY_PORTS_FILE);

    let sections = enabled_xray_sections();
    let connection_sections = enabled_connection_sections();
    let config = empty_config();
    let ports = {};
    let nodes_map = {};
    let node_seq = { next: xray_constants.XRAY_NODE_PORT_BASE };
    let cascade = {};
    let deferred = [];
    let taken = {};
    taken[xray_constants.FREEDOM_TAG] = true;
    taken[xray_constants.BLACKHOLE_TAG] = true;

    for (let i = 0; i < length(sections); i++)
        add_section(config, taken, sections[i], ports, i, sections, connection_sections, cascade, deferred, nodes_map, node_seq);
    resolve_deferred_xray_detours(config, taken, deferred);

    if (type(config.observatory) == "object" && length(array_or_empty(config.observatory.subjectSelector)) == 0)
        delete config.observatory;
    if (length(array_or_empty(config.routing.balancers)) == 0)
        delete config.routing.balancers;

    let parent = "";
    let slash = rindex(output_path, "/");
    if (slash > 0)
        parent = substr(output_path, 0, slash);
    if (parent != "" && parent != "." && !ensure_dir(parent))
        generate_fail("failed to create xray config directory");
    if (!write_json_file(output_path, config))
        generate_fail("failed to write xray config");

    slash = rindex(ports_path, "/");
    parent = slash > 0 ? substr(ports_path, 0, slash) : "";
    if (parent != "" && parent != "." && !ensure_dir(parent))
        generate_fail("failed to create xray ports directory");
    if (!write_json_file(ports_path, ports))
        generate_fail("failed to write xray ports map");

    let cascade_path = xray_constants.XRAY_CASCADE_FILE;
    slash = rindex(cascade_path, "/");
    parent = slash > 0 ? substr(cascade_path, 0, slash) : "";
    if (parent != "" && parent != "." && !ensure_dir(parent))
        generate_fail("failed to create xray cascade directory");
    if (!write_json_file(cascade_path, cascade))
        generate_fail("failed to write xray cascade map");

    let nodes_path = xray_constants.XRAY_NODES_FILE;
    slash = rindex(nodes_path, "/");
    parent = slash > 0 ? substr(nodes_path, 0, slash) : "";
    if (parent != "" && parent != "." && !ensure_dir(parent))
        generate_fail("failed to create xray nodes directory");
    if (!write_json_file(nodes_path, nodes_map))
        generate_fail("failed to write xray nodes map");

    print(sprintf("%J", { sections: length(sections), ports: ports, cascade: cascade, nodes: nodes_map }), "\n");
}

let mode = ARGV[0] || "";
if (mode == "generate-config")
    generate_config(ARGV[1] || "", ARGV[2] || "");
else if (mode == "enabled-sections")
    print(sprintf("%J", enabled_xray_sections()), "\n");
else {
    warn("Usage: xray/generator.uc <generate-config|enabled-sections> ...\n");
    exit(1);
}
