/**
 * D-Bus Caller (Client) — raw libdbus, no wrappers
 *
 * Connects to the session bus, sends a method call to
 * "com.bussie.HelloService" → "/com/bussie/HelloObject"
 * → interface "com.bussie.HelloInterface" → method "Hello"
 * with a name argument, and prints the reply.
 *
 * Build:
 *   g++ -o caller caller.cpp $(pkg-config --cflags --libs dbus-1)
 *
 * Run:
 *   ./caller [YourName]
 */

#include <dbus/dbus.h>
#include <cstdio>
#include <cstdlib>

// ── Must match the service's constants ───────────────────────────────
static const char *BUS_NAME = "com.bussie.HelloService";
static const char *OBJ_PATH = "/com/bussie/HelloObject";
static const char *IFACE    = "com.bussie.HelloInterface";
static const char *METHOD   = "Hello";

int main(int argc, char *argv[]) {
    // Use first CLI arg as name, default to "World"
    const char *name = (argc > 1) ? argv[1] : "World";

    DBusError err;
    dbus_error_init(&err);

    // 1. Connect to the session bus
    DBusConnection *conn = dbus_bus_get(DBUS_BUS_SESSION, &err);
    if (dbus_error_is_set(&err)) {
        fprintf(stderr, "[caller] Connection error: %s\n", err.message);
        dbus_error_free(&err);
        return 1;
    }
    if (!conn) {
        fprintf(stderr, "[caller] Connection is NULL\n");
        return 1;
    }

    printf("[caller] Connected to session bus\n");

    // 2. Build a METHOD_CALL message
    //    destination  = bus name the service registered
    //    path         = object path on that service
    //    interface    = grouping of methods (like a namespace)
    //    method       = the actual method name
    DBusMessage *msg = dbus_message_new_method_call(
        BUS_NAME,   // destination
        OBJ_PATH,   // object path
        IFACE,      // interface
        METHOD      // method
    );
    if (!msg) {
        fprintf(stderr, "[caller] Failed to create message\n");
        return 1;
    }

    // 3. Append arguments to the message
    //    D-Bus is strictly typed — we must tell it DBUS_TYPE_STRING
    //    and pass a pointer to the const char*.
    //    Type invalid marks no more arguments are there after this
    dbus_message_append_args(msg,
        DBUS_TYPE_STRING, &name,
        DBUS_TYPE_INVALID);

    printf("[caller] Calling %s.%s(\"%s\") on %s ...\n", IFACE, METHOD, name, OBJ_PATH);

    // 4. Send the message and block waiting for a reply
    //    Timeout: 5000ms (5 seconds).  If the service isn't running
    //    or takes too long, we'll get a timeout error.
    DBusPendingCall *pending = nullptr;
    if (!dbus_connection_send_with_reply(conn, msg, &pending, 5000)) {
        fprintf(stderr, "[caller] Out of memory\n");
        return 1;
    }
    if (!pending) {
        fprintf(stderr, "[caller] Pending call is NULL (disconnected?)\n");
        return 1;
    }

    // Flush the outgoing queue so the message actually goes on the wire
    dbus_connection_flush(conn);
    dbus_message_unref(msg);  // we're done with the request message

    // Block this thread until the reply arrives (or timeout)
    dbus_pending_call_block(pending);

    // 5. Steal the reply message from the pending call
    DBusMessage *reply = dbus_pending_call_steal_reply(pending);
    dbus_pending_call_unref(pending);

    // We handle if the reply is bad even after waiting for reply from dbus
    if (!reply) {
        fprintf(stderr, "[caller] No reply received\n");
        return 1;
    }

    // 6. Check reply type — could be METHOD_RETURN or ERROR
    if (dbus_message_get_type(reply) == DBUS_MESSAGE_TYPE_ERROR) {
        const char *err_msg = nullptr;
        dbus_message_get_args(reply, &err, DBUS_TYPE_STRING, &err_msg, DBUS_TYPE_INVALID);
        fprintf(stderr, "[caller] Error from service: %s\n",
            err_msg ? err_msg : dbus_message_get_error_name(reply));
        dbus_message_unref(reply);
        return 1;
    }

    // 7. Extract the return value — a single string, error can be different data type receiverd
    const char *greeting = nullptr;
    if (!dbus_message_get_args(reply, &err, DBUS_TYPE_STRING, &greeting, DBUS_TYPE_INVALID)) {
        fprintf(stderr, "[caller] Failed to parse reply: %s\n", err.message);
        dbus_error_free(&err);
        dbus_message_unref(reply);
        return 1;
    }

    printf("[caller] Got reply: \"%s\"\n", greeting);

    // 8. Cleanup
    dbus_message_unref(reply);
    dbus_connection_unref(conn);

    return 0;
}
