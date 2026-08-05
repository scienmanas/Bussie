/**
 * D-Bus Service (Server) — raw libdbus, no wrappers
 *
 * Registers on the session bus as "com.bussie.HelloService"
 * Exposes object "/com/bussie/HelloObject"
 * with interface "com.bussie.HelloInterface"
 * and method "Hello" that takes a string name and returns a greeting.
 *
 * Build:
 *   g++ -std=c++11 -o service service.cpp $(pkg-config --cflags --libs dbus-1)
 *
 * Run:
 *   ./service
 */

#include <dbus/dbus.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>

// ── Constants ────────────────────────────────────────────────────────
// static - only visible within this file; const - can't be modified after init
static const char *BUS_NAME   = "com.bussie.HelloService";
static const char *OBJ_PATH   = "/com/bussie/HelloObject";
static const char *IFACE      = "com.bussie.HelloInterface";
static const char *METHOD     = "Hello";

// ── Introspection XML ────────────────────────────────────────────────
// Returned in response to org.freedesktop.DBus.Introspectable.Introspect.
// pydbus (used by program/python/code/caller.py) calls Introspect first
// to discover what methods this object exposes — without this handler
// the Python caller would fail at `bus.get(...)` with "no such interface".
// `busctl introspect com.bussie.HelloService /com/bussie/HelloObject`
// also relies on this.
// We are using C++ raw string literal so we don't use any escape sequence
// Each interface can have multiple methods.
// This XML is just a static string, decoupled from the dispatch logic below —
// adding a <method> here without a matching dbus_message_is_method_call()
// check won't crash the service; calls to it are just silently dropped and
// the caller times out. Also, org.freedesktop.DBus.Introspectable is a
// spec-owned standard interface (conventionally only has "Introspect") —
// add new custom methods under com.bussie.HelloInterface instead.
static const char *INTROSPECT_XML = R"(
<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <interface name="org.freedesktop.DBus.Introspectable">
    <method name="Introspect">
      <arg name="data" direction="out" type="s"/>
    </method>
  </interface>
  <interface name="com.bussie.HelloInterface">
    <method name="Hello">
      <arg name="name"     direction="in"  type="s"/>
      <arg name="greeting" direction="out" type="s"/>
    </method>
  </interface>
</node>)";

// ── Handle Introspect ────────────────────────────────────────────────
// Replies with the XML above so pydbus / busctl / qdbusviewer can discover
// what methods we expose.
static void handle_introspect(DBusConnection *conn, DBusMessage *msg) {
    DBusMessage *reply = dbus_message_new_method_return(msg);
    const char *xml = INTROSPECT_XML;
    dbus_message_append_args(reply,
        DBUS_TYPE_STRING, &xml,
        DBUS_TYPE_INVALID);
    // 3rd arg is an optional out-param for the assigned message serial. Pass a
    // dbus_uint32_t* to get it back (useful for matching a method CALL to its
    // future reply). This is a reply, not a call, so we never need the serial —
    // nullptr says "don't return it". Note: send() only queues the message.
    dbus_connection_send(conn, reply, nullptr);
    // Force the pending outgoing data to go now by flush
    dbus_connection_flush(conn);
    dbus_message_unref(reply);
}

// ── Handle the "Hello" method call ───────────────────────────────────
// Reads a string arg (caller's name), returns "Hello, <name>!"
static void handle_hello(DBusConnection *conn, DBusMessage *msg) {
    DBusError err;
    dbus_error_init(&err);

    // 1. Extract the input argument — a single string,  if mismatch send error reply
    const char *name = nullptr;
    if (!dbus_message_get_args(msg, &err, DBUS_TYPE_STRING, &name, DBUS_TYPE_INVALID)) {
        fprintf(stderr, "[service] Failed to parse args: %s\n", err.message);
        dbus_error_free(&err);

        // Send back an error reply so the caller doesn't hang
        DBusMessage *err_reply = dbus_message_new_error(
            msg, DBUS_ERROR_INVALID_ARGS, "Expected a single string argument");
        dbus_connection_send(conn, err_reply, nullptr);
        dbus_message_unref(err_reply);
        return;
    }

    printf("[service] Hello() called with name = \"%s\"\n", name);

    // 2. Build the greeting string
    char greeting[256];
    snprintf(greeting, sizeof(greeting), "Hello, %s! Welcome to Bussie.", name);
    // dbus_message_append_args reads STRING args as `const char **`, so it needs
    // the address of an actual char* variable — &greeting would be char(*)[256],
    // the wrong indirection, so we go through this pointer variable instead.
    const char *greeting_ptr = greeting; // Copies address

    // 3. Create a METHOD_RETURN reply and append the greeting
    DBusMessage *reply = dbus_message_new_method_return(msg);
    dbus_message_append_args(reply,
        DBUS_TYPE_STRING, &greeting_ptr,
        DBUS_TYPE_INVALID);

    // 4. Send the reply back over the connection
    // 3rd arg is an out-param for the sent message's serial number; nullptr
    // since this is a reply and we don't need to track it further.
    // send() does NOT take ownership of `reply`; it adds its OWN reference so
    // the message survives in the outgoing queue until the bytes hit the socket.
    // After this returns the refcount is 2 (ours + the connection's).
    // The only failure send() reports is out-of-memory (returns FALSE): in that
    // case it neither queued the message nor took a reference, so the refcount is
    // still just 1 and our unref below frees it correctly — the refs stay balanced
    // in every path, we only log here. (A dead client is undetectable at this
    // point since the socket write happens asynchronously in flush(); the caller
    // catches that via its own reply timeout.)
    if (!dbus_connection_send(conn, reply, nullptr)) {
        fprintf(stderr, "[service] Out of memory queuing reply; dropping it\n");
    }
    // Force the pending outgoing data to go now by flush
    dbus_connection_flush(conn);

    // DBusMessages are reference-counted: unref decrements the count and frees
    // the message when it reaches 0. `reply` came from dbus_message_new_*(), so
    // WE own one reference and must release it exactly once. This drops ours
    // (2 -> 1); the connection releases its own reference once the message has
    // finished sending, which frees the memory. Skipping this leaks one message
    // per call; unref'ing twice risks a use-after-free.
    dbus_message_unref(reply);
    printf("[service] Replied: \"%s\"\n", greeting);
}

// ── Main loop ────────────────────────────────────────────────────────
int main() {
    DBusError err;
    dbus_error_init(&err);

    // 1. Connect to the session bus
    //    The session bus is per-user; the system bus is machine-wide.
    DBusConnection *conn = dbus_bus_get(DBUS_BUS_SESSION, &err);
    if (dbus_error_is_set(&err)) {
        fprintf(stderr, "[service] Connection error: %s\n", err.message);
        dbus_error_free(&err);
        return 1;
    }
    if (!conn) {
        fprintf(stderr, "[service] Connection is NULL\n");
        return 1;
    }

    // Connections from dbus_bus_get() default to "exit on disconnect": libdbus
    // would call _exit() the moment the bus drops. We turn that OFF so WE own the
    // shutdown path — the loop below detects the disconnect itself and breaks out
    // cleanly, running the cleanup at the end of main() instead of being yanked
    // out mid-iteration. (The built-in exit fires from dbus_connection_dispatch()
    // anyway, which our pop_message()-based loop never calls, so relying on it
    // here would be fragile regardless.)
    dbus_connection_set_exit_on_disconnect(conn, FALSE);

    // 2. Request a well-known bus name so clients can find us
    //    DBUS_NAME_FLAG_REPLACE_EXISTING — take ownership even if
    //    another process already owns it (useful during dev, e.g. restarting
    //    this service without waiting for a crashed instance to release it).
    //    This only works against our own BUS_NAME above: it can't be used to
    //    hijack an unrelated service's name (e.g. a GNOME/system service)
    //    unless that owner opted in with DBUS_NAME_FLAG_ALLOW_REPLACEMENT,
    //    and dbus-daemon policy files (/etc/dbus-1/*.d/*.conf) separately
    //    gate who is allowed to own a given name at all.
    int ret = dbus_bus_request_name(conn, BUS_NAME,
        DBUS_NAME_FLAG_REPLACE_EXISTING, &err);
    if (dbus_error_is_set(&err)) {
        fprintf(stderr, "[service] Name request error: %s\n", err.message);
        dbus_error_free(&err);
        return 1;
    }
    if (ret != DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER) {
        fprintf(stderr, "[service] Could not become primary owner of %s\n", BUS_NAME);
        return 1;
    }

    printf("[service] Listening on bus name: %s\n", BUS_NAME);
    printf("[service] Object path:          %s\n", OBJ_PATH);
    printf("[service] Interface:            %s\n", IFACE);
    printf("[service] Method:               %s\n", METHOD);
    printf("[service] Waiting for calls...\n\n");

    // 3. Main message-dispatch loop
    //    This is a manual, hand-rolled event loop — the lowest-level way to run
    //    a D-Bus service, which is the whole point of using raw libdbus here.
    //    Higher-level options (dbus_connection_read_write_dispatch, or wiring the
    //    connection into GLib's GMainLoop via dbus_connection_setup_with_g_main)
    //    would poll and route messages for us; we do it by hand to keep the
    //    mechanics visible. Two distinct layers run each iteration:
    //      - read_write() = TRANSPORT layer: moves raw bytes between the OS
    //        socket and libdbus's in-memory queues. Does not interpret messages.
    //      - pop_message() = APPLICATION layer: pulls one parsed DBusMessage out
    //        of the incoming queue (or nullptr if empty). Never blocks.
    while (true) {
        // dbus_connection_read_write() does the socket I/O: it reads incoming
        // bytes into the connection's incoming queue and writes out any pending
        // outgoing bytes. The 1000 is a timeout in MILLISECONDS, so it blocks for
        // up to 1 second waiting for data, but returns EARLY the moment something
        // arrives (it won't wait the full second unnecessarily). A finite timeout
        // (vs. -1 = block forever) means the loop wakes periodically even when
        // idle — the window a real service would use to check a shutdown flag,
        // handle Ctrl-C, or do other periodic work.
        //
        // It returns FALSE once the connection has disconnected. We MUST act on
        // that: with the socket gone read_write() no longer blocks, so the 1s
        // timeout stops throttling and the loop would busy-spin at 100% CPU
        // (read_write → FALSE instantly, pop_message → nullptr, continue, repeat).
        // A shared bus connection can't be reconnected, so we break out for a
        // clean shutdown and let a service manager (systemd, etc.) restart us on
        // a fresh connection.
        if (!dbus_connection_read_write(conn, 1000)) {
            fprintf(stderr, "[service] Bus connection lost; shutting down\n");
            break;
        }

        // Pop the next fully-parsed message from the incoming queue. This is the
        // application layer and never blocks: if read_write() collected nothing,
        // the queue is empty and this returns nullptr.
        DBusMessage *msg = dbus_connection_pop_message(conn);
        if (!msg) {
            continue;  // nothing arrived this cycle → loop and wait again
        }

        // Dispatch the message. We care about two method calls:
        //   1. org.freedesktop.DBus.Introspectable.Introspect — so that
        //      introspection-based clients (pydbus, busctl, qdbusviewer)
        //      can discover our methods.
        //   2. com.bussie.HelloInterface.Hello — the actual greeting.
        const char *path = dbus_message_get_path(msg);
        if (path && strcmp(path, OBJ_PATH) == 0) {
            if (dbus_message_is_method_call(msg,
                    "org.freedesktop.DBus.Introspectable", "Introspect")) {
                handle_introspect(conn, msg);
            } else if (dbus_message_is_method_call(msg, IFACE, METHOD)) {
                handle_hello(conn, msg);
            }
        }
        // Other messages (signal deliveries, property gets, etc.)
        // fall through and are silently dropped.

        dbus_message_unref(msg);
    }

    // Cleanup — now reachable: the loop breaks out when the bus connection is
    // lost. dbus_bus_get() returns a SHARED connection, so we unref (not close)
    // it: this drops our reference and lets libdbus finalize it once no one else
    // holds it. Returning non-zero signals the abnormal exit to a service manager.
    dbus_connection_unref(conn);
    return 1;
}
