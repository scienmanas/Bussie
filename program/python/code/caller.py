# D-Bus caller — Python, using pydbus.
#
# Connects to the session bus, looks up com.bussie.HelloService, and
# calls its Hello(name) method. Identical interface to program/cpp/
# service.cpp and caller.cpp, so this caller can drive either the
# Python service (program/python/code/service.py) or the C++ service
# (program/cpp/build/service) — picking which one is running is the
# whole point of D-Bus's language-agnostic IPC.
#
# Run:
#     python3 caller.py            # uses "World"
#     python3 caller.py Manas      # uses "Manas"

import sys
from pydbus import SessionBus

# Must match whatever service is currently running.
BUS_NAME    = "com.bussie.HelloService"
OBJECT_PATH = "/com/bussie/HelloObject"
INTERFACE   = "com.bussie.HelloInterface"   # see note below — usually not needed

# pydbus needs the service to respond to
#   org.freedesktop.DBus.Introspectable.Introspect
# on this object path so it can build the Python proxy. Both the
# Python service (via its <node>…</node> XML) and the C++ service
# (via its handle_introspect() function) ship that handler.
bus  = SessionBus()
hello = bus.get(BUS_NAME, OBJECT_PATH)

# Why isn't `INTERFACE` passed anywhere here?
#
# The interface IS mandatory in the D-Bus wire protocol — every method
# call message has destination + path + interface + member fields. But
# pydbus hides it: when bus.get(...) runs, pydbus first calls
# org.freedesktop.DBus.Introspectable.Introspect() on this object,
# reads the XML, and flattens every method from every interface onto
# one Python proxy. So `hello.Hello(name)` works because pydbus looks
# up "Hello" in that flattened map and fills in
# `interface = com.bussie.HelloInterface` on the wire for you.
#
# Lower-level clients (busctl, raw libdbus in program/cpp/caller.cpp)
# don't introspect — they require you to spell the interface out, e.g.
#   busctl --user call com.bussie.HelloService /com/bussie/HelloObject \
#          com.bussie.HelloInterface Hello s "Manas"
#
# You only need the explicit form below if two interfaces on the same
# object expose methods with identical names and pydbus can't tell
# which one you mean — index the proxy by interface to disambiguate.
# For Bussie, "Hello" is unique to com.bussie.HelloInterface, so the
# short form is fine and the explicit form is equivalent.

name = sys.argv[1] if len(sys.argv) > 1 else "World"

# Short form — pydbus auto-resolves the interface from introspection.
print(hello.Hello(name))

# Explicit form — equivalent, useful when method names collide across
# interfaces on the same object (e.g., NetworkManager devices).
# print(hello[INTERFACE].Hello(name))
