# D-Bus Hello Service (Raw C++)

A minimal D-Bus service and caller written in C++ using the raw `libdbus` C API — no wrappers, no frameworks, just direct D-Bus protocol interaction for maximum understanding.

## What is D-Bus?

D-Bus (Desktop Bus) is an IPC (Inter-Process Communication) system that lets processes talk to each other. It uses a **bus** architecture — processes connect to a central daemon, register names, and exchange typed messages.

Key concepts used in this project:

| Concept           | Description                                                                      |
| ----------------- | -------------------------------------------------------------------------------- |
| **Session Bus**   | Per-user bus (vs system bus which is machine-wide)                               |
| **Bus Name**      | A unique address a service registers (e.g. `com.bussie.HelloService`)            |
| **Object Path**   | A resource on the service, like a REST endpoint (e.g. `/com/bussie/HelloObject`) |
| **Interface**     | Groups related methods under a namespace (e.g. `com.bussie.HelloInterface`)      |
| **Method Call**   | A message requesting work — includes args and expects a reply                    |
| **Method Return** | The reply message containing return values                                       |

## Architecture

```
┌─────────────────┐         D-Bus Session Bus         ┌─────────────────┐
│                 │  ──── METHOD_CALL("Hello") ────▶  │                 │
│     caller      │         name = "Manas"            │     service     │
│   (caller.cpp)  │  ◀── METHOD_RETURN ─────────────  │  (service.cpp)  │
│                 │   "Hello, Manas! Welcome to.."    │                 │
└─────────────────┘                                   └─────────────────┘
```

**Service** registers `com.bussie.HelloService` on the session bus, listens for `Hello` method calls, and replies with a greeting.

**Caller** sends a `Hello` method call with a name argument and prints the reply.

## Project Structure

```
cpp/
├── service.cpp    # D-Bus service — registers name, handles Hello() calls
├── caller.cpp     # D-Bus client — sends Hello() call, prints reply
├── build.sh       # Install deps + compile (Linux)
├── build/         # Compiled binaries (created by build.sh)
│   ├── service
│   └── caller
└── README.md
```

## Build

### Quick (Linux)

```bash
chmod +x build.sh
./build.sh
```

The script auto-detects your distro (Debian/Fedora/Arch/openSUSE), installs `libdbus-1-dev`, `g++`, and `pkg-config` if missing, then compiles both binaries into `build/`.

### Manual

```bash
# Install deps (Debian/Ubuntu)
sudo apt install g++ pkg-config libdbus-1-dev

# Compile
g++ -Wall -Wextra -o service service.cpp $(pkg-config --cflags --libs dbus-1)
g++ -Wall -Wextra -o caller caller.cpp $(pkg-config --cflags --libs dbus-1)
```

## Usage

**Terminal 1** — start the service:

```bash
./build/service
```

```
[service] Listening on bus name: com.bussie.HelloService
[service] Object path:          /com/bussie/HelloObject
[service] Interface:            com.bussie.HelloInterface
[service] Method:               Hello
[service] Waiting for calls...
```

**Terminal 2** — call it:

```bash
./build/caller Manas
```

```
[caller] Connected to session bus
[caller] Calling com.bussie.HelloInterface.Hello("Manas") on /com/bussie/HelloObject ...
[caller] Got reply: "Hello, Manas! Welcome to Bussie."
```

Back in Terminal 1 you'll see:

```
[service] Hello() called with name = "Manas"
[service] Replied: "Hello, Manas! Welcome to Bussie."
```

## Code Walkthrough

### Service (`service.cpp`)

1. **Connect** to session bus → `dbus_bus_get(DBUS_BUS_SESSION)`
2. **Claim name** → `dbus_bus_request_name("com.bussie.HelloService")`
3. **Loop** → `dbus_connection_read_write()` blocks for data, `dbus_connection_pop_message()` dequeues
4. **Dispatch** → check if message matches our interface + method + path
5. **Reply** → extract string arg, build greeting, send `METHOD_RETURN`

### Caller (`caller.cpp`)

1. **Connect** to session bus
2. **Build message** → `dbus_message_new_method_call(dest, path, iface, method)`
3. **Append args** → `dbus_message_append_args(DBUS_TYPE_STRING, ...)`
4. **Send + wait** → `dbus_connection_send_with_reply()` + `dbus_pending_call_block()`
5. **Read reply** → extract return string, print it

## Testing with dbus-send

You can also call the service without the caller binary:

```bash
dbus-send --session --print-reply \
  --dest=com.bussie.HelloService \
  /com/bussie/HelloObject \
  com.bussie.HelloInterface.Hello \
  string:"Manas"
```

## Requirements

- Linux (D-Bus session bus must be running)
- g++ (C++11 or later)
- libdbus-1-dev
- pkg-config
