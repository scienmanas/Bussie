// bussie-service: a deliberately-insecure D-Bus service for the Bussie
// attack demo. Owns org.bussie.Pwn on the SYSTEM bus, runs as root, and
// exposes a single Delete(path) method that executes `rm -rf -- <path>`
// without any caller validation. The whole point is to show what one
// permissive XML policy line lets a user-level process do.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <dbus/dbus.h>

static const char* BUS_NAME    = "org.bussie.Pwn";
static const char* OBJECT_PATH = "/org/bussie/Pwn";
static const char* IFACE       = "org.bussie.Pwn";

static const char* INTROSPECT_XML = R"(
<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <interface name="org.freedesktop.DBus.Introspectable">
    <method name="Introspect">
      <arg name="data" direction="out" type="s"/>
    </method>
  </interface>
  <interface name="org.bussie.Pwn">
    <method name="Delete">
      <arg name="path" direction="in" type="s"/>
      <arg name="result" direction="out" type="s"/>
    </method>
  </interface>
</node>)";

static std::string shell_quote(const std::string& s) {
    std::string out = "'";
    for (char c : s) {
        if (c == '\'') out += "'\\''";
        else out += c;
    }
    out += "'";
    return out;
}

static void reply_string(DBusConnection* conn, DBusMessage* msg, const std::string& s) {
    DBusMessage* reply = dbus_message_new_method_return(msg);
    const char* cstr = s.c_str();
    dbus_message_append_args(reply, DBUS_TYPE_STRING, &cstr, DBUS_TYPE_INVALID);
    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
}

static DBusHandlerResult handle_message(DBusConnection* conn, DBusMessage* msg, void* /*user*/) {
    if (dbus_message_is_method_call(msg, "org.freedesktop.DBus.Introspectable", "Introspect")) {
        reply_string(conn, msg, INTROSPECT_XML);
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    if (dbus_message_is_method_call(msg, IFACE, "Delete")) {
        const char* path = nullptr;
        DBusError err; dbus_error_init(&err);
        if (!dbus_message_get_args(msg, &err, DBUS_TYPE_STRING, &path, DBUS_TYPE_INVALID)) {
            DBusMessage* ereply = dbus_message_new_error(msg, DBUS_ERROR_INVALID_ARGS, err.message);
            dbus_connection_send(conn, ereply, NULL);
            dbus_message_unref(ereply);
            dbus_error_free(&err);
            // Every D-Bus method call requires exactly one reply (return or
            // error); we already sent the error above, so HANDLED tells
            // libdbus not to forward this message to any other handler and
            // not to leave the caller waiting until it times out.
            return DBUS_HANDLER_RESULT_HANDLED;
        }
        fprintf(stderr, "[bussie-service] Delete(%s)\n", path);
        std::string cmd = "rm -rf -- " + shell_quote(path);
        int rc = std::system(cmd.c_str());
        std::string result = (rc == 0) ? std::string("ok: ") + path
                                       : std::string("rm exited with ") + std::to_string(rc);
        reply_string(conn, msg, result);
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    // Message didn't match Introspect or Delete. NOT_YET_HANDLED tells
    // libdbus this handler doesn't recognize it; since no other handler is
    // registered on this object path, libdbus's core dispatch then sends
    // back a standard org.freedesktop.DBus.Error.UnknownMethod error itself,
    // so the caller still gets a reply instead of hanging until timeout.
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

int main() {
    DBusError err; dbus_error_init(&err);
    DBusConnection* conn = dbus_bus_get(DBUS_BUS_SYSTEM, &err);
    if (!conn || dbus_error_is_set(&err)) {
        fprintf(stderr, "Failed to connect to system bus: %s\n", err.message);
        dbus_error_free(&err);
        return 1;
    }

    int ret = dbus_bus_request_name(conn, BUS_NAME, DBUS_NAME_FLAG_DO_NOT_QUEUE, &err);
    if (dbus_error_is_set(&err)) {
        fprintf(stderr, "Failed to request name %s: %s\n", BUS_NAME, err.message);
        dbus_error_free(&err);
        return 1;
    }
    if (ret != DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER) {
        fprintf(stderr, "Could not become primary owner of %s (ret=%d)\n", BUS_NAME, ret);
        return 1;
    }

    // vt is a table of callback function pointers libdbus invokes for
    // messages addressed to OBJECT_PATH. memset zeroes it first so
    // unregister_function (no cleanup needed here) and any reserved fields
    // stay NULL; only message_function is wired up, to handle_message.
    DBusObjectPathVTable vt;
    memset(&vt, 0, sizeof(vt));
    vt.message_function = handle_message;
    if (!dbus_connection_register_object_path(conn, OBJECT_PATH, &vt, NULL)) {
        fprintf(stderr, "Failed to register object path %s\n", OBJECT_PATH);
        return 1;
    }

    fprintf(stderr, "[bussie-service] ready: owning %s at %s\n", BUS_NAME, OBJECT_PATH);
    // Main loop: block until there's bus activity, then read/write/dispatch
    // one message (routing into handle_message). Runs forever until the
    // connection drops, which is what keeps this process alive as a daemon.
    // -1 is block undeifinitely until there is something to do - instead of looping and polling.
    while (dbus_connection_read_write_dispatch(conn, -1)) {}
    return 0;
}
