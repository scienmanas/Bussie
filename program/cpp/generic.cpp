#include <dbus/dbus.h>
#include <iostream>

using namespace std;

int main() {
    // Variables
    DBusError dbus_error;
    DBusConnection * dbus_conn = nullptr;
    DBusMessage * dbus_msg = nullptr;
    DBusMessage * dbus_reply = nullptr;
    const char* dbus_result = nullptr;

    // Initialise Dbus error
    ::dbus_error_init(&dbus_error);

    // Connect to Dbus
    dbus_conn = ::dbus_bus_get(DBUS_BUS_SYSTEM, &dbus_error);
    cout << "Connected to D-Bus as \"" << ::dbus_bus_get_unique_name(dbus_conn) << "\"." << endl;

    // Compose remote procedure call, call root object
    dbus_msg = ::dbus_message_new_method_call("org.freedesktop.DBus", "/", "org.freedesktop.DBus.Introspectable", "Introspect");

    // Invoke remote procedure call, block for response
    dbus_reply = ::dbus_connection_send_with_reply_and_block(dbus_conn, dbus_msg, DBUS_TIMEOUT_USE_DEFAULT, &dbus_error);

    // Parse response
    ::dbus_message_get_args(dbus_reply, &dbus_error, DBUS_TYPE_STRING, &dbus_result, DBUS_TYPE_INVALID);

    // Work with the results of the remote procedure call
    cout << "Introspection Result: \n" << dbus_result << endl;
    
    // Unreferenc everything - don't close connection as in dbus things are shared
    ::dbus_message_unref(dbus_msg);
    ::dbus_message_unref(dbus_reply);
    ::dbus_connection_unref(dbus_conn);

    return 0;
}