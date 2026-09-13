#!/usr/bin/env ucode

let fs = require("fs");
let uci_core = require("core.uci");
let connections = require("config.connections");
let xray_constants = require("xray.constants");

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
    let status = int(system(command));
    return status > 255 ? int(status / 256) : status;
}

function command_success(command) {
    return command_status("(" + command + ") >/dev/null 2>&1") == 0;
}

function command_success_from_args(args) {
    return command_success(command_from_args(args));
}

function command_output(command) {
    let pipe = fs.popen(command, "r");
    if (!pipe)
        return "";
    let data = pipe.read("all");
    pipe.close();
    return data == null ? "" : as_string(data);
}

function command_output_from_args(args) {
    return command_output(command_from_args(args));
}

function file_exists(path) {
    return fs.stat(path) != null;
}

function file_executable(path) {
    let st = fs.stat(path);
    return st != null && st.type == "file";
}

function write_file(path, value) {
    return fs.writefile(path, as_string(value));
}

function read_file(path) {
    let data = fs.readfile(path);
    return data == null ? "" : as_string(data);
}

function remove_file(path) {
    fs.unlink(path);
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

function write_json(value) {
    print(sprintf("%J", value), "\n");
}

function log_message(message, level) {
    level = as_string(level || "info");
    message = as_string(message);
    command_success_from_args([ "logger", "-t", "forkop", "[" + level + "] " + message ]);
    if (level == "fatal" || level == "error")
        warn(message, "\n");
}

function parse_xray_version(text) {
    let newline = index(as_string(text), "\n");
    let line = trim(newline >= 0 ? substr(text, 0, newline) : text);
    let fields = split(line, /[ \t]+/);
    if (length(fields) >= 2 && lc(fields[0]) == "xray")
        return as_string(fields[1]);
    return length(fields) > 0 ? as_string(fields[length(fields) - 1]) : "";
}

function strip_leading_v(value) {
    value = as_string(value);
    return substr(value, 0, 1) == "v" || substr(value, 0, 1) == "V" ? substr(value, 1) : value;
}

function xray_installed() {
    return file_executable(xray_constants.XRAY_BIN);
}

function xray_version_output() {
    if (!xray_installed())
        return "";
    return command_output_from_args([ xray_constants.XRAY_BIN, "version" ]);
}

function xray_version() {
    let stored = trim(read_file(xray_constants.XRAY_VERSION_STATE_FILE));
    if (stored != "")
        return stored;
    return parse_xray_version(xray_version_output());
}

function write_version_state(version) {
    version = trim(version);
    if (version == "")
        return false;
    let parent = "/etc/forkop";
    if (fs.stat(parent) == null)
        fs.mkdir(parent, 0755);
    return write_file(xray_constants.XRAY_VERSION_STATE_FILE, version + "\n");
}

function read_json_object(path) {
    let data = read_file(path);
    if (data == "")
        return {};
    try {
        let value = json(data);
        return type(value) == "object" ? value : {};
    }
    catch (e) {
        return {};
    }
}

function read_ports() {
    return read_json_object(xray_constants.XRAY_PORTS_FILE);
}

function read_nodes() {
    return read_json_object(xray_constants.XRAY_NODES_FILE);
}

function write_empty_ports() {
    let path = xray_constants.XRAY_PORTS_FILE;
    let slash = rindex(path, "/");
    let parent = slash > 0 ? substr(path, 0, slash) : "";
    if (parent != "" && parent != "." && !ensure_dir(parent))
        return false;
    write_file(xray_constants.XRAY_CASCADE_FILE, "{}\n");
    write_file(xray_constants.XRAY_NODES_FILE, "{}\n");
    return write_file(path, "{}\n");
}

function xray_section_count() {
    return length(keys(read_ports()));
}

function uci_xray_section_count() {
    if (!uci_core.available())
        return 0;
    let count = 0;
    for (let section in uci_core.section_objects("forkop", "section")) {
        section = object_or_empty(section);
        let enabled = section.enabled == null ? "1" : as_string(section.enabled);
        if (enabled == "0")
            continue;
        if (!connections.is_connections_action(as_string(section.action || "")))
            continue;
        if (connections.proxy_core(section) == "xray")
            count++;
    }
    return count;
}

function xray_needed() {
    return xray_section_count() > 0 || uci_xray_section_count() > 0;
}

function as_port(value) {
    if (type(value) == "int" || type(value) == "double") {
        let port = int(value);
        return port > 0 ? port : 0;
    }
    let text = trim(as_string(value));
    if (match(text, /^[0-9]+$/) == null)
        return 0;
    let port = int(text);
    return port > 0 ? port : 0;
}

function collect_listen_ports() {
    let seen = {};
    let result = [];
    let ports = read_ports();
    for (let name in keys(ports)) {
        let port = as_port(ports[name]);
        if (port <= 0)
            continue;
        let key = as_string(port);
        if (seen[key])
            continue;
        seen[key] = true;
        push(result, port);
    }

    let nodes = read_nodes();
    for (let name in keys(nodes)) {
        for (let node in array_or_empty(nodes[name])) {
            let port = as_port(object_or_empty(node).port);
            if (port <= 0)
                continue;
            let key = as_string(port);
            if (seen[key])
                continue;
            seen[key] = true;
            push(result, port);
        }
    }

    return result;
}

function listen_table() {
    let data = command_output_from_args([ "netstat", "-ln" ]);
    if (trim(data) == "")
        data = command_output("ss -lntu 2>/dev/null");
    return as_string(data);
}

function port_is_listening(table, port) {
    port = as_string(port);
    if (port == "" || table == "")
        return false;
    return index(table, ":" + port + " ") >= 0 ||
        index(table, ":" + port + "\n") >= 0 ||
        index(table, ":" + port) >= 0;
}

function configured_ports_listening() {
    let ports = collect_listen_ports();
    if (length(ports) == 0)
        return false;
    let table = listen_table();
    if (trim(table) == "")
        return false;
    for (let port in ports) {
        if (!port_is_listening(table, port))
            return false;
    }
    return true;
}

function procd_instance_running() {
    if (service_exists() && command_success_from_args([ xray_constants.XRAY_SERVICE_INIT, "running" ]))
        return true;
    let ubus = command_output("ubus call service list '{\"name\":\"xray\"}' 2>/dev/null");
    if (match(ubus, /"running"\s*:\s*true/) != null)
        return true;
    if (match(ubus, /"pid"\s*:\s*[1-9]/) != null)
        return true;
    return false;
}

function process_detected() {
    if (!xray_installed())
        return false;

    if (command_success_from_args([ "pidof", "xray" ]) ||
        command_success_from_args([ "pidof", "Xray" ]))
        return true;

    if (command_success_from_args([ "pgrep", "-x", "xray" ]) ||
        command_success_from_args([ "pgrep", "-x", "Xray" ]) ||
        command_success_from_args([ "pgrep", "-f", "^/usr/bin/xray[[:space:]]" ]))
        return true;

    let exes = command_output("ls -l /proc/[0-9]*/exe 2>/dev/null");
    if (index(exes, xray_constants.XRAY_BIN) >= 0)
        return true;

    return procd_instance_running();
}

function process_running() {
    if (!xray_installed())
        return false;
    return process_detected() || configured_ports_listening();
}

function service_exists() {
    return file_exists(xray_constants.XRAY_SERVICE_INIT);
}

function service_enabled() {
    return service_exists() && command_success_from_args([ xray_constants.XRAY_SERVICE_INIT, "enabled" ]);
}

function ports_listening() {
    if (!xray_installed())
        return false;
    if (!xray_needed())
        return false;
    return configured_ports_listening();
}

function check_config(path) {
    path = as_string(path || xray_constants.XRAY_CONFIG);
    if (!xray_installed())
        return { status: 1, reason: "xray is not installed" };
    if (!file_exists(path))
        return { status: 1, reason: "xray config is missing" };
    let output = "/tmp/xray-check." + as_string(clock()[0]);
    let status = command_status(
        command_from_args([ xray_constants.XRAY_BIN, "run", "-test", "-c", path ]) +
        " >" + shell_quote(output) + " 2>&1"
    );
    let reason = trim(read_file(output));
    remove_file(output);
    if (status != 0 && reason == "")
        reason = "exit status " + status;
    return { status, reason };
}

function init_config() {
    if (uci_xray_section_count() == 0) {
        write_empty_ports();
        return;
    }

    let LIB_DIR = getenv("FORKOP_LIB") || "/usr/lib/forkop";
    let generator = LIB_DIR + "/xray/generator.uc";
    if (!file_exists(generator)) {
        log_message("Xray generator is missing. Aborted.", "fatal");
        exit(1);
    }

    let log_path = "/tmp/forkop-xray-generate." + as_string(clock()[0]);
    let status = command_status(
        command_from_args([
            "ucode", "-L", LIB_DIR, generator,
            "generate-config",
            xray_constants.XRAY_CONFIG,
            xray_constants.XRAY_PORTS_FILE
        ]) + " >" + shell_quote(log_path) + " 2>&1"
    );
    let output = trim(read_file(log_path));
    remove_file(log_path);
    if (status != 0) {
        log_message(
            "Failed to generate xray configuration" + (output != "" ? ": " + output : "") + ". Aborted.",
            "fatal"
        );
        exit(1);
    }

    if (!xray_needed())
        return;

    if (!xray_installed()) {
        log_message("Xray sections are enabled but /usr/bin/xray is not installed. Install Xray from Components. Aborted.", "fatal");
        exit(1);
    }

    let check = check_config(xray_constants.XRAY_CONFIG);
    if (check.status != 0) {
        log_message("Generated xray configuration is invalid: " + check.reason + ". Aborted.", "fatal");
        exit(1);
    }
}

function start_runtime() {
    if (!xray_needed())
        return 0;
    if (!xray_installed()) {
        log_message("Xray is required by enabled sections but is not installed", "fatal");
        return 1;
    }
    if (!service_exists()) {
        log_message("Xray service script is missing; install Xray from Components", "fatal");
        return 1;
    }
    let log_path = "/tmp/forkop-xray-start." + as_string(clock()[0]);
    let status = command_status(
        command_from_args([ xray_constants.XRAY_SERVICE_INIT, "start" ]) +
        " >" + shell_quote(log_path) + " 2>&1"
    );
    let output = trim(read_file(log_path));
    remove_file(log_path);
    if (status != 0) {
        log_message(
            "Failed to start xray" + (output != "" ? ": " + output : "") + ". Aborted.",
            "fatal"
        );
        return 1;
    }

    let tries = 0;
    while (tries < 8) {
        if (process_detected() || configured_ports_listening())
            return 0;
        command_status("sleep 1");
        tries++;
    }

    log_message(
        "Xray start returned success but the process is not running. Check /etc/xray/config.json and logread -e xray.",
        "fatal"
    );
    return 1;
}

function stop_runtime() {
    if (service_exists())
        command_success_from_args([ xray_constants.XRAY_SERVICE_INIT, "stop" ]);
    command_success("killall xray >/dev/null 2>&1");
    return 0;
}

function reload_runtime() {
    if (!xray_needed()) {
        stop_runtime();
        return 0;
    }
    if (process_running()) {
        if (command_success_from_args([ xray_constants.XRAY_SERVICE_INIT, "reload" ]))
            return 0;
        command_success_from_args([ xray_constants.XRAY_SERVICE_INIT, "restart" ]);
        return 0;
    }
    return start_runtime();
}

function status_json() {
    let installed = xray_installed() ? 1 : 0;
    let version = installed ? (xray_version() || "unknown") : "not installed";
    write_json({
        installed,
        version,
        configured: xray_needed() ? 1 : 0,
        section_count: xray_section_count(),
        service_exist: service_exists() ? 1 : 0,
        autostart_disabled: service_enabled() ? 0 : 1,
        process_running: process_running() ? 1 : 0,
        ports_listening: ports_listening() ? 1 : 0,
        config_path: xray_constants.XRAY_CONFIG,
        ready: installed && (!xray_needed() || (process_running() && ports_listening())) ? 1 : 0,
        status_message: installed ? version : "not installed"
    });
    return 0;
}

function check_json() {
    let installed = xray_installed() ? 1 : 0;
    let version = installed ? strip_leading_v(xray_version()) : "";
    let version_ok = 0;
    if (installed && version != "") {
        let LIB_DIR = getenv("FORKOP_LIB") || "/usr/lib/forkop";
        version_ok = command_success(command_from_args([
            "ucode", "-L", LIB_DIR, LIB_DIR + "/core/helpers.uc",
            "version-at-least", version, xray_constants.XRAY_REQUIRED_VERSION
        ])) ? 1 : 0;
    }
    write_json({
        xray_installed: installed,
        xray_version_ok: version_ok,
        xray_service_exist: service_exists() ? 1 : 0,
        xray_autostart_disabled: service_enabled() ? 0 : 1,
        xray_process_running: process_running() ? 1 : 0,
        xray_ports_listening: ports_listening() ? 1 : 0,
        xray_sections_configured: xray_needed() ? 1 : 0
    });
    return 0;
}

function show_config() {
    print(read_file(xray_constants.XRAY_CONFIG));
    return 0;
}

function show_version() {
    print(xray_version(), "\n");
    return 0;
}

let mode = ARGV[0] || "";

if (mode == "init-config")
    init_config();
else if (mode == "start-runtime")
    exit(start_runtime());
else if (mode == "stop-runtime")
    exit(stop_runtime());
else if (mode == "reload-runtime")
    exit(reload_runtime());
else if (mode == "status")
    exit(status_json());
else if (mode == "running")
    exit(process_running() ? 0 : 1);
else if (mode == "check")
    exit(check_json());
else if (mode == "installed")
    exit(xray_installed() ? 0 : 1);
else if (mode == "version")
    exit(show_version());
else if (mode == "version-from-output") {
    print(parse_xray_version(fs.readfile("/dev/stdin") || ""), "\n");
}
else if (mode == "write-version-state")
    exit(write_version_state(ARGV[1] || "") ? 0 : 1);
else if (mode == "read-version-state")
    print(trim(read_file(xray_constants.XRAY_VERSION_STATE_FILE)), "\n");
else if (mode == "show-config")
    exit(show_config());
else if (mode == "ports")
    write_json(read_ports());
else if (mode == "needed")
    exit(xray_needed() ? 0 : 1);
else {
    warn("Usage: xray/runtime.uc <init-config|start-runtime|stop-runtime|status|running|check|...> ...\n");
    exit(1);
}
