# D-Bus service — Python, using pydbus.
#
# Publishes com.bussie.HelloService on the SESSION bus with a single
# method Hello(name: s) -> greeting: s. Identifiers match the C++
# service in program/cpp/service.cpp so either implementation can be
# swapped in behind the same caller (Python or C++).
#
# Run:
#     python3 service.py
# Then in another terminal:
#     python3 caller.py Manas
#     # or
#     ../cpp/build/caller Manas

from gi.repository import GLib
from pydbus import SessionBus

# D-Bus introspection XML. pydbus uses this both to publish the
# interface and to answer Introspect calls from any caller (including
# `busctl introspect` and pydbus on the other side).
HELLO_IFACE = """
<node>
    <interface name="com.bussie.HelloInterface">
        <method name="Hello">
            <arg name="name"     type="s" direction="in"/>
            <arg name="greeting" type="s" direction="out"/>
        </method>
    </interface>
</node>
"""

# Class can have any name, but the public methods must match the XML above. 
class HelloService:
    """
    Backing object for /com/bussie/HelloObject. Each public method
    here must appear in HELLO_IFACE — pydbus reads the XML to figure
    out which methods to expose on the bus.
    """
    def Hello(self, name: str) -> str:
        print(f"[python-service] Hello() called with name = {name!r}")
        return f"Hello, {name}! (from Python D-Bus)"


BUS_NAME    = "com.bussie.HelloService"
OBJECT_PATH = "/com/bussie/HelloObject"

bus = SessionBus()
bus.publish(BUS_NAME, (OBJECT_PATH, HelloService(), HELLO_IFACE))

print(f"[python-service] running as {BUS_NAME} on session bus")
print(f"[python-service] object = {OBJECT_PATH}")
print(f"[python-service] interface = com.bussie.HelloInterface, method = Hello")
print(f"[python-service] waiting for callers (Ctrl-C to stop)…")

GLib.MainLoop().run()
