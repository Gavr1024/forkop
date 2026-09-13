#!/usr/bin/env ucode

let fs = require("fs");
let uci_core = require("core.uci");
let connections = require("config.connections");
let singbox_rulesets = require("singbox.rulesets");

const CONFIG_NAME = getenv("FORKOP_CONFIG_NAME") || "forkop";
const LIST_CACHE_DIR = getenv("FORKOP_LIST_CACHE_DIR") || "/etc/forkop/list-cache";
const LIST_CACHE_MANIFEST = getenv("FORKOP_LIST_CACHE_MANIFEST") || LIST_CACHE_DIR + "/manifest.json";
const LIST_CACHE_FORMAT = getenv("FORKOP_LIST_CACHE_FORMAT") || "1";
const SERVICE_INIT = getenv("FORKOP_SERVICE_INIT") || "/etc/init.d/forkop";
const SB_SERVICE_MIXED_INBOUND_ADDRESS = getenv("SB_SERVICE_MIXED_INBOUND_ADDRESS") || "127.0.0.1";
const SB_SERVICE_MIXED_INBOUND_PORT = int(getenv("SB_SERVICE_MIXED_INBOUND_PORT") || "4534");
const DOWNLOAD_WAIT_SECONDS = int(getenv("FORKOP_LIST_CACHE_WAIT_SECONDS") || "45");

function as_string(value) {
    return value == null ? "" : "" + value;
}

function trim_string(value) {
    let text = as_string(value);
    let start_match = match(text, /^[ \t\r\n]*/);
    let start = start_match ? length(start_match[0]) : 0;
    let end = length(text);

    while (end > start && match(substr(text, end - 1, 1), /[ \t\r\n]/))
        end--;

    return substr(text, start, end - start);
}

function object_or_empty(value) {
    return type(value) == "object" ? value : {};
}

function array_or_empty(value) {
    return type(value) == "array" ? value : [];
}

function option(section, name, fallback) {
    section = object_or_empty(section);
    let value = section[name];
    if (value == null)
        return fallback;
    return as_string(value);
}

function bool_option(section, name, fallback) {
    let value = object_or_empty(section)[name];
    if (value == null)
        return fallback ? true : false;
    return value === true || value == 1 || value == "1" || value == "true" || value == "yes" || value == "on";
}

function shell_quote(value) {
    return "'" + replace(as_string(value), /'/g, "'\\''") + "'";
}

function command_from_args(args) {
    let parts = [];
    for (let arg in args)
        push(parts, shell_quote(arg));
    return join(" ", parts);
}

function command_status(command) {
    return system(command);
}

function command_success(command) {
    return command_status(command + " >/dev/null 2>&1") == 0;
}

function command_success_from_args(args) {
    return command_success(command_from_args(args));
}

function json_decode_text(text) {
    try {
        return json(as_string(text));
    }
    catch (e) {
        return null;
    }
}

function read_json_file(path) {
    let data = fs.readfile(path);
    return data == null ? null : json_decode_text(data);
}

function write_text_file(path, text) {
    let result = fs.writefile(path, text);
    if (result == null)
        return false;
    if (type(result) == "boolean" && !result)
        return false;
    return true;
}

function write_json_file(path, value) {
    return write_text_file(path, sprintf("%J", value) + "\n");
}

function ensure_dir(path) {
    path = as_string(path);
    if (path == "")
        return false;
    if (fs.stat(path) != null)
        return true;
    return command_success_from_args([ "mkdir", "-p", path ]);
}

function file_stat(path) {
    return fs.stat(as_string(path));
}

function file_exists(path) {
    return file_stat(path) != null;
}

function file_size(path) {
    let st = file_stat(path);
    if (st == null)
        return 0;
    let size = st.size;
    if (size == null)
        size = st.length;
    return int(size || 0);
}

function file_mtime(path) {
    let st = file_stat(path);
    if (st == null)
        return 0;
    return int(st.mtime || 0);
}

function now_seconds() {
    return int(clock()[0]);
}

function log_message(message, level) {
    warn(sprintf("[%s] list-cache: %s\n", as_string(level || "info"), as_string(message)));
}

function settings_section() {
    return object_or_empty(uci_core.get_all(CONFIG_NAME, "settings"));
}

function persist_enabled(settings) {
    if (type(settings) != "object")
        settings = settings_section();
    return bool_option(settings, "persist_lists_locally", false);
}

function cache_dir() {
    return LIST_CACHE_DIR;
}

function manifest_path() {
    return LIST_CACHE_MANIFEST;
}

function extension_for_url(url) {
    let ext = singbox_rulesets.file_extension(url);
    if (ext == "json")
        return "json";
    return "srs";
}

function format_for_extension(ext) {
    return as_string(ext) == "json" ? "source" : "binary";
}

function cache_basename(url) {
    return singbox_rulesets.hash12(url) + "." + extension_for_url(url);
}

function cache_path_for_url(url) {
    return LIST_CACHE_DIR + "/" + cache_basename(url);
}

function usable_local_path(url, settings) {
    if (!persist_enabled(settings))
        return "";
    url = trim_string(url);
    if (url == "")
        return "";
    let path = cache_path_for_url(url);
    return file_size(path) > 0 ? path : "";
}

function local_entry(url, settings) {
    let path = usable_local_path(url, settings);
    if (path == "")
        return null;
    let ext = extension_for_url(url);
    return {
        path,
        format: format_for_extension(ext)
    };
}

function community_item(name) {
    name = trim_string(name);
    if (name == "")
        return null;
    if (singbox_rulesets.is_community(name) != true)
        return null;
    let url = singbox_rulesets.community_url(name);
    return {
        id: cache_basename(url),
        name,
        kind: "community",
        url,
        path: cache_path_for_url(url)
    };
}

function remote_item(reference, kind) {
    reference = trim_string(reference);
    if (reference == "")
        return null;
    if (substr(reference, 0, 7) != "http://" && substr(reference, 0, 8) != "https://")
        return null;
    return {
        id: cache_basename(reference),
        name: reference,
        kind: kind || "rule_set",
        url: reference,
        path: cache_path_for_url(reference)
    };
}

function collect_selected_lists(sections) {
    let items = [];
    let seen = {};

    function add_item(item) {
        if (type(item) != "object")
            return;
        let id = as_string(item.id);
        if (id == "" || seen[id])
            return;
        seen[id] = true;
        push(items, item);
    }

    for (let section in array_or_empty(sections)) {
        section = object_or_empty(section);
        if (!bool_option(section, "enabled", true))
            continue;

        for (let name in connections.community_lists(section))
            add_item(community_item(name));
        for (let reference in connections.rule_sets(section))
            add_item(remote_item(reference, "rule_set"));
        for (let reference in connections.rule_sets_with_subnets(section))
            add_item(remote_item(reference, "rule_set_with_subnets"));
        for (let reference in split(as_string(option(section, "domain_ip_lists", "")), /[ \t\r\n]+/))
            add_item(remote_item(reference, "domain_ip_list"));
        for (let reference in split(as_string(option(section, "remote_domain_lists", "")), /[ \t\r\n]+/))
            add_item(remote_item(reference, "remote_domain_list"));
        for (let reference in split(as_string(option(section, "remote_subnet_lists", "")), /[ \t\r\n]+/))
            add_item(remote_item(reference, "remote_subnet_list"));
    }

    return items;
}

function collect_selected_lists_from_uci() {
    return collect_selected_lists(uci_core.section_objects(CONFIG_NAME, "section"));
}

function hex_port(port) {
    return sprintf("%04X", int(port));
}

function tcp_table_has_listen(path, port) {
    let data = fs.readfile(path);
    if (data == null)
        return false;

    let needle = ":" + hex_port(port);
    for (let line in split(as_string(data), "\n")) {
        if (index(line, needle) < 0)
            continue;
        if (match(line, /[ \t]0A[ \t]/) != null)
            return true;
    }
    return false;
}

function download_port_ready(port) {
    port = int(port || SB_SERVICE_MIXED_INBOUND_PORT);
    if (tcp_table_has_listen("/proc/net/tcp", port))
        return true;
    if (tcp_table_has_listen("/proc/net/tcp6", port))
        return true;
    return false;
}

function service_is_running() {
    return command_success_from_args([ SERVICE_INIT, "running" ]);
}

function lists_proxy_address(settings) {
    if (type(settings) != "object")
        settings = settings_section();
    if (!bool_option(settings, "download_lists_via_proxy", false))
        return "";
    if (trim_string(option(settings, "download_lists_via_proxy_section", "")) == "")
        return "";
    return SB_SERVICE_MIXED_INBOUND_ADDRESS + ":" + SB_SERVICE_MIXED_INBOUND_PORT;
}

function curl_fetch(url, output_path, proxy_address, timeout_seconds) {
    let args = [
        "curl", "-sS", "-L", "--fail", "--retry", "2",
        "--max-time", "" + int(timeout_seconds || 45),
        "-A", "forkop-list-cache/1.0.5",
        "-o", output_path,
        "--url", as_string(url)
    ];
    if (as_string(proxy_address) != "") {
        push(args, "-x");
        push(args, "http://" + as_string(proxy_address));
    }
    return system(command_from_args(args)) == 0 && file_size(output_path) > 0;
}

function proxy_fetch_ready(proxy_address) {
    if (as_string(proxy_address) == "")
        return true;
    let tmp = "/tmp/forkop-list-cache-probe";
    try { fs.unlink(tmp); } catch (e) { }
    let ok = curl_fetch("https://github.com", tmp, proxy_address, 8);
    try { fs.unlink(tmp); } catch (e2) { }
    return ok;
}

function ensure_download_section_up(settings) {
    if (type(settings) != "object")
        settings = settings_section();
    if (!bool_option(settings, "download_lists_via_proxy", false))
        return true;

    let section_name = trim_string(option(settings, "download_lists_via_proxy_section", ""));
    if (section_name == "") {
        log_message("download via section is enabled, but no section is selected", "error");
        return false;
    }

    if (!download_port_ready(SB_SERVICE_MIXED_INBOUND_PORT)) {
        if (!service_is_running()) {
            log_message("starting Forkop so lists can be downloaded through section '" + section_name + "'", "info");
            command_success_from_args([ SERVICE_INIT, "start" ]);
        }
        else {
            log_message("waiting for section '" + section_name + "' mixed inbound on port " + SB_SERVICE_MIXED_INBOUND_PORT, "info");
        }
    }

    let proxy_address = lists_proxy_address(settings);
    let attempt = 0;
    while (attempt < DOWNLOAD_WAIT_SECONDS) {
        if (download_port_ready(SB_SERVICE_MIXED_INBOUND_PORT) && proxy_fetch_ready(proxy_address)) {
            log_message("download section '" + section_name + "' can fetch through the proxy", "info");
            return true;
        }
        command_success_from_args([ "sleep", "1" ]);
        attempt++;
    }

    log_message("download section '" + section_name + "' port is up, but proxy fetch is not ready yet", "warn");
    return download_port_ready(SB_SERVICE_MIXED_INBOUND_PORT);
}

function download_to_file(url, filepath, proxy_address) {
    let tmp = filepath + ".tmp";
    try { fs.unlink(tmp); } catch (e) { }

    let attempt = 1;
    while (attempt <= 3) {
        if (as_string(proxy_address) != "") {
            log_message("fetch " + as_string(url) + " via section proxy", "info");
            if (curl_fetch(url, tmp, proxy_address, 45) && fs.rename(tmp, filepath))
                return true;
        }

        log_message("fetch " + as_string(url) + " directly", "info");
        if (curl_fetch(url, tmp, "", 45) && fs.rename(tmp, filepath))
            return true;

        log_message("attempt " + attempt + "/3 to cache " + as_string(url) + " failed", "warn");
        try { fs.unlink(tmp); } catch (e3) { }
        command_success_from_args([ "sleep", "2" ]);
        attempt++;
    }

    return false;
}

function empty_manifest() {
    return {
        version: int(LIST_CACHE_FORMAT),
        enabled: persist_enabled() ? true : false,
        updated_at: 0,
        items: []
    };
}

function read_manifest() {
    let data = object_or_empty(read_json_file(LIST_CACHE_MANIFEST));
    if (type(data.items) != "array")
        data = empty_manifest();
    data.enabled = persist_enabled() ? true : false;
    return data;
}

function write_manifest(items) {
    if (!ensure_dir(LIST_CACHE_DIR))
        return false;

    let manifest = {
        version: int(LIST_CACHE_FORMAT),
        enabled: persist_enabled() ? true : false,
        updated_at: now_seconds(),
        items: array_or_empty(items)
    };
    return write_json_file(LIST_CACHE_MANIFEST, manifest);
}

function item_status(item) {
    item = object_or_empty(item);
    let size = file_size(item.path);
    if (size > 0)
        return "cached";
    return persist_enabled() ? "missing" : "disabled";
}

function decorate_item(item) {
    item = object_or_empty(item);
    let size = file_size(item.path);
    let mtime = file_mtime(item.path);
    return {
        id: as_string(item.id),
        name: as_string(item.name),
        kind: as_string(item.kind),
        url: as_string(item.url),
        path: as_string(item.path),
        size,
        mtime,
        status: item_status(item)
    };
}

function status_object() {
    let settings = settings_section();
    let selected = collect_selected_lists_from_uci();
    let items = [];
    for (let item in selected)
        push(items, decorate_item(item));

    return {
        version: int(LIST_CACHE_FORMAT),
        enabled: persist_enabled(settings) ? true : false,
        dir: LIST_CACHE_DIR,
        download_via_section: bool_option(settings, "download_lists_via_proxy", false),
        download_section: option(settings, "download_lists_via_proxy_section", ""),
        updated_at: int(object_or_empty(read_manifest()).updated_at || 0),
        count: length(items),
        cached: length(filter(items, function(item) { return item.status == "cached"; })),
        items
    };
}

function filter(values, predicate) {
    let result = [];
    for (let value in array_or_empty(values))
        if (predicate(value))
            push(result, value);
    return result;
}

function prune_unselected(selected) {
    let keep = {
        "manifest.json": true
    };
    for (let item in array_or_empty(selected))
        keep[cache_basename(item.url)] = true;

    let names = fs.lsdir(LIST_CACHE_DIR);
    if (type(names) != "array")
        return;

    for (let name in names) {
        name = as_string(name);
        if (name == "." || name == ".." || keep[name])
            continue;
        if (match(name, /\.tmp$/) != null || match(name, /\.(srs|json)$/) != null) {
            try { fs.unlink(LIST_CACHE_DIR + "/" + name); } catch (e) { }
        }
    }
}

function persist_selected_lists(settings, proxy_address) {
    if (type(settings) != "object")
        settings = settings_section();
    if (!persist_enabled(settings))
        return true;

    if (!ensure_dir(LIST_CACHE_DIR)) {
        log_message("unable to create " + LIST_CACHE_DIR, "error");
        return false;
    }

    if (!ensure_download_section_up(settings))
        return false;

    if (as_string(proxy_address) == "")
        proxy_address = lists_proxy_address(settings);

    let selected = collect_selected_lists_from_uci();
    if (length(selected) == 0) {
        write_manifest([]);
        prune_unselected([]);
        log_message("no selected lists to cache", "info");
        return true;
    }

    let ok = true;
    let stored = [];
    let changed = false;

    for (let item in selected) {
        let previous_size = file_size(item.path);
        if (download_to_file(item.url, item.path, proxy_address)) {
            let decorated = decorate_item(item);
            if (decorated.size != previous_size)
                changed = true;
            push(stored, decorated);
            log_message("cached " + item.name + " -> " + item.path, "info");
        }
        else if (previous_size > 0) {
            push(stored, decorate_item(item));
            log_message("keeping previous local copy of " + item.name, "warn");
        }
        else {
            ok = false;
            push(stored, decorate_item(item));
            log_message("failed to cache " + item.name, "error");
        }
    }

    write_manifest(stored);
    prune_unselected(selected);
    return { ok, changed, items: stored };
}

function print_status_json() {
    print(sprintf("%J", status_object()), "\n");
}

function module_exports() {
    return {
        persist_enabled,
        cache_dir,
        cache_path_for_url,
        usable_local_path,
        local_entry,
        collect_selected_lists,
        collect_selected_lists_from_uci,
        ensure_download_section_up,
        persist_selected_lists,
        status_object,
        print_status_json
    };
}

if ((sourcepath(1) != null && sourcepath(1) != "") || ARGV[0] == null)
    return module_exports();

let mode = ARGV[0] || "";

if (mode == "status-json")
    print_status_json();
else if (mode == "persist") {
    let result = persist_selected_lists();
    if (type(result) == "object")
        exit(result.ok ? 0 : 1);
    exit(result ? 0 : 1);
}
else if (mode == "cache-path")
    print(cache_path_for_url(ARGV[1] || ""), "\n");
else if (mode == "ensure-download-section")
    exit(ensure_download_section_up() ? 0 : 1);
else {
    warn("Usage: routing/list_cache.uc <status-json|persist|cache-path|ensure-download-section> ...\n");
    exit(1);
}
