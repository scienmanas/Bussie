// bussie-bridge: Chrome native-messaging host. Reads one framed JSON
// message from stdin ({"path": "<string>"}), calls
// org.bussie.Pwn.Delete(path) on the SYSTEM bus, and writes the result
// back as one framed JSON message on stdout.
//
// Chrome native messaging frame format: <uint32 native-endian length>
// followed by exactly that many UTF-8 JSON bytes. We emit the same.

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <unistd.h>
#include <string>
#include <vector>
#include <nlohmann/json.hpp>
#include <dbus/dbus.h>

using json = nlohmann::json;

static bool read_all(int fd, void* buf, size_t n) {
    char* p = static_cast<char*>(buf);
    while (n > 0) {
        ssize_t r = read(fd, p, n);
        if (r <= 0) return false;
        p += r;
        n -= static_cast<size_t>(r);
    }
    return true;
}

static bool write_all(int fd, const void* buf, size_t n) {
    const char* p = static_cast<const char*>(buf);
    while (n > 0) {
        ssize_t r = write(fd, p, n);
        if (r <= 0) return false;
        p += r;
        n -= static_cast<size_t>(r);
    }
    return true;
}

static void send_response(const json& j) {
    std::string s = j.dump();
    uint32_t len = static_cast<uint32_t>(s.size());
    write_all(STDOUT_FILENO, &len, sizeof(len));
    write_all(STDOUT_FILENO, s.data(), s.size());
}

static json call_delete(const std::string& path) {
    json out;
    DBusError err; dbus_error_init(&err);

    DBusConnection* conn = dbus_bus_get(DBUS_BUS_SYSTEM, &err);
    if (!conn || dbus_error_is_set(&err)) {
        out["ok"]     = false;
        out["result"] = std::string("bus connect failed: ") + (err.message ? err.message : "");
        dbus_error_free(&err);
        return out;
    }

    DBusMessage* msg = dbus_message_new_method_call(
        "org.bussie.Pwn",   // destination
        "/org/bussie/Pwn",  // object path
        "org.bussie.Pwn",   // interface
        "Delete");          // method
    if (!msg) {
        out["ok"]     = false;
        out["result"] = "method_call alloc failed";
        return out;
    }
    const char* p = path.c_str();
    dbus_message_append_args(msg, DBUS_TYPE_STRING, &p, DBUS_TYPE_INVALID);

    DBusMessage* reply = dbus_connection_send_with_reply_and_block(conn, msg, 30000, &err);
    dbus_message_unref(msg);
    if (!reply || dbus_error_is_set(&err)) {
        out["ok"]     = false;
        out["result"] = std::string("bus call failed: ") + (err.message ? err.message : "");
        dbus_error_free(&err);
        return out;
    }

    const char* reply_str = nullptr;
    if (!dbus_message_get_args(reply, &err, DBUS_TYPE_STRING, &reply_str, DBUS_TYPE_INVALID)) {
        dbus_message_unref(reply);
        out["ok"]     = false;
        out["result"] = std::string("reply parse failed: ") + (err.message ? err.message : "");
        dbus_error_free(&err);
        return out;
    }
    out["ok"]     = true;
    out["result"] = std::string(reply_str ? reply_str : "");
    dbus_message_unref(reply);
    return out;
}

int main() {
    uint32_t len = 0;
    if (!read_all(STDIN_FILENO, &len, sizeof(len))) {
        return 0;  // Chrome closed stdin without sending; quiet exit.
    }
    if (len > 1024u * 1024u) {
        send_response({{"ok", false}, {"result", "message too large"}});
        return 1;
    }

    std::vector<char> buf(len);
    if (len > 0 && !read_all(STDIN_FILENO, buf.data(), len)) {
        send_response({{"ok", false}, {"result", "short read"}});
        return 1;
    }

    json req;
    try {
        req = json::parse(std::string(buf.data(), len));
    } catch (const std::exception& e) {
        send_response({{"ok", false}, {"result", std::string("bad json: ") + e.what()}});
        return 1;
    }
    if (!req.contains("path") || !req["path"].is_string()) {
        send_response({{"ok", false}, {"result", "missing string field: path"}});
        return 1;
    }

    // get<std::string>() extracts/converts the JSON string value into a real
    // std::string (the <std::string> is a template arg, not an address-of).
    json resp = call_delete(req["path"].get<std::string>());
    send_response(resp);
    return 0;
}
