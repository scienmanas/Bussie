# Bussie

This project has three parts

1. A testing set of program to understand D-Bus (python).
2. A testing set of program to understand D-Bus (C++).
3. A chrome extenstion and a dbus service running with root priviledges to mitigate D-Bus based attacks.

## OS Requirements

D-Bus (Desktop Bus) in a IPC (Inter process communication) system for Linux based system. We are not doing here extra work to run it on other os as the purpose of this repo is to highlight how browser extension or other programs can communicate to IPCs which obviously may be different for different os, but serve the same purpose to make messaging possible between services on the systems.

## D-Bus addressing: bus name, object path, interface

Every D-Bus method call has to specify **three** identifiers, not one. People hitting D-Bus for the first time always ask why — surely the bus name alone is enough to find the service? It isn't, and the reason is the same reason a postal address has three lines:

| Level | D-Bus                 | Question it answers                  | Postal analogy                |
| ----- | --------------------- | ------------------------------------ | ----------------------------- |
| 1     | **Bus name**    | *Which process do I talk to?*      | Street address                |
| 2     | **Object path** | *Which thing inside that process?* | Apartment number              |
| 3     | **Interface**   | *Which API on that thing?*         | Which form you're filling out |

You need all three because **none of them is unique on its own** — each level is many-to-many with the next.

### One process can host many objects

`gnome-shell` owns the bus name `org.gnome.Shell`, but inside that one process there are many separate "things" — the extensions manager, screenshot service, search provider, individual notifications. Each gets its own object path:

```
/org/gnome/Shell                          ← the shell itself
/org/gnome/Shell/Extensions               ← extension manager
/org/gnome/Shell/Screenshot               ← screenshot service
/org/gnome/Shell/Notifications/42         ← notification #42
```

Without object paths, you'd only be able to address the whole process as one black box.

### One object can implement many interfaces

This is the part that usually clicks last. A single Wi-Fi device in NetworkManager lives at **one object path**:

```
/org/freedesktop/NetworkManager/Devices/3
```

…but that one path implements **four interfaces simultaneously**:

- `org.freedesktop.NetworkManager.Device` — generic device methods (`Disconnect`)
- `org.freedesktop.NetworkManager.Device.Wireless` — Wi-Fi-specific (`RequestScan`, `GetAccessPoints`)
- `org.freedesktop.DBus.Properties` — generic property get/set
- `org.freedesktop.DBus.Introspectable` — `Introspect()`

When you call a method you have to say *which* interface's method you mean — otherwise the service has no idea whether `Disconnect` is the generic one or some Wi-Fi-specific override.

So essentially, interfaces are many, make note of it.

### One interface can be implemented by many objects

Every device on NetworkManager — wifi, ethernet, modem, VPN — implements `org.freedesktop.NetworkManager.Device`. So interface alone doesn't tell you *which* device you mean.

### In Bussie

Both `program/python/code/service.py` and `program/cpp/service.cpp` use the same three identifiers:

```
bus name:    com.bussie.HelloService     ← which process
object path: /com/bussie/HelloObject     ← which thing in it
interface:   com.bussie.HelloInterface   ← which API on that thing
             └── method Hello(name: s) → greeting: s
```

That same object *also* implements a second interface, `org.freedesktop.DBus.Introspectable`, with method `Introspect()`. Same bus name, same object path, different interface — which is why every introspection-based client (`pydbus`, `busctl`, `qdbusviewer`) can ask "what methods do you expose?" without colliding with the actual `Hello` method:

```bash
# Same object, two interfaces:
busctl --user call com.bussie.HelloService /com/bussie/HelloObject \
       org.freedesktop.DBus.Introspectable Introspect          # returns XML
busctl --user call com.bussie.HelloService /com/bussie/HelloObject \
       com.bussie.HelloInterface           Hello s "Manas"     # returns greeting
```

### The HTTP analogy

If you're more comfortable with HTTP: `https://gmail.com/inbox/42` is `host (≈ bus name) + path (≈ object path)`, and the `Content-Type` / API version headers play the role of the interface — saying "speak to this endpoint in this dialect." D-Bus just makes that third axis explicit instead of hiding it in a header.

## D-Bus: Session Bus vs System Bus

D-Bus actually runs **two separate buses** on a Linux desktop. They share the same protocol but serve very different scopes.

### Session Bus

- **One per logged-in user session.** Started by your desktop session (`systemd --user` or `dbus-daemon --session`).
- **Carries user-app traffic** — notifications, media keys (MPRIS), secrets (gnome-keyring), search providers, browser ↔ desktop integration, IDE plugins, etc.
- **Socket** lives under `/run/user/<uid>/bus` and is exposed via `$DBUS_SESSION_BUS_ADDRESS`.
- **Auth:** only processes running as _your_ UID can connect. No PolicyKit; isolation is weaker — any of your processes can call any service you own. This means only user logged in for whome sesssion bys started can use that, only exception is root user, who has super priviledges.
- **Typical names:** `org.freedesktop.Notifications`, `org.mpris.MediaPlayer2.*`, `org.gnome.*`, `org.kde.*`.

### System Bus

- **One per machine.** Started at boot by `dbus.service` / `dbus-broker`. Lives for the life of the system.
- **Carries privileged services** — NetworkManager, UPower, BlueZ, systemd, logind, PolicyKit, udisks2, ModemManager.
- **Socket** at `/var/run/dbus/system_bus_socket` (or `$DBUS_SYSTEM_BUS_ADDRESS`).
- **Auth:** any local user can _connect_, but each service ships an XML policy in `/etc/dbus-1/system.d/` (or `/usr/share/dbus-1/system.d/`) that restricts who can own a name, send to a destination, or call a method. Privileged actions usually defer to **PolicyKit** for an additional yes/no decision.
- **Typical names:** `org.freedesktop.NetworkManager`, `org.freedesktop.systemd1`, `org.freedesktop.login1`, `org.bluez`.

### Quick comparison

|                  | Session Bus                          | System Bus                      |
| ---------------- | ------------------------------------ | ------------------------------- |
| Scope            | One per user login                   | One per machine                 |
| Lifetime         | Tied to user session                 | Tied to host (boot → shutdown) |
| Started by       | `systemd --user` / session manager | `dbus.service` at boot        |
| Who can connect  | Your UID only                        | Any local user                  |
| Access control   | Implicit (same UID)                  | XML policy + PolicyKit          |
| Typical services | Notifications, MPRIS, secrets, IDE   | NetworkManager, systemd, BlueZ  |

### Why this matters for security

- **Session bus** is the soft target: a compromised browser extension, sandboxed app, or any code running as you can pivot via session services without prompting.
- **System bus** is harder, but historically rich in CVEs (e.g., _PwnKit_ in polkit, NetworkManager bugs) — these are classic local-privilege-escalation primitives.

### Inspecting each bus

```bash
busctl --user   list      # services on the session bus
busctl --system list      # services on the system bus
dbus-monitor --session    # live trace, session
dbus-monitor --system     # live trace, system
```

GUI tools: **bustle** (live message timeline) and **qdbusviewer** (tree browser — closest spiritual successor to the old d-feet). Both have a Session/System toggle.

```bash
sudo apt install bustle qttools5-dev-tools
```

> d-feet was the classic GTK D-Bus browser, but it was archived upstream in 2022 and removed from Debian/Ubuntu/Kali repos in 2023, so `apt install d-feet` no longer works. Use `bustle` + `qdbusviewer` instead — together they cover everything d-feet did.

## How Chrome talks to D-Bus: the GNOME bridge pattern

Chrome extensions live in a sandbox. They cannot speak D-Bus, open Unix sockets, or touch the filesystem directly — the only escape hatch from extension JS to the operating system is **native messaging**: Chrome spawns a registered native binary as a child process and pipes framed JSON over stdin/stdout. So any "browser → D-Bus" flow needs **three** pieces, not two:

```
┌─────────────────────────────┐
│ 1. Browser extension        │  JavaScript in Chrome's sandbox.
│    (installed from the      │  Calls chrome.runtime.sendNativeMessage(...)
│     Chrome Web Store)       │  — its only way out.
└──────────────┬──────────────┘
               │ framed JSON over stdin/stdout
               ▼
┌─────────────────────────────┐
│ 2. Native messaging host    │  A regular binary on disk, runs as YOU.
│    (installed via apt or    │  Knows how to speak D-Bus. Reads JSON
│     by your installer)      │  from Chrome, makes the D-Bus call,
│                             │  writes JSON back.
└──────────────┬──────────────┘
               │ D-Bus method call
               ▼
┌─────────────────────────────┐
│ 3. D-Bus service            │  The actual privileged-ish thing.
│    (session or system bus)  │  Does the work.
└─────────────────────────────┘
```

The classic real-world example is **GNOME Shell extension installation**. When you click *Install* on `extensions.gnome.org`, this is what runs end-to-end:

```
extensions.gnome.org page  ──postMessage──▶  "GNOME Shell integration"
                                              browser extension
                                              (chrome-extension://gphhap…)
                                                        │
                                  chrome.runtime.sendNativeMessage
                                  ("org.gnome.browser_connector", {...})
                                                        ▼
                                  /usr/bin/gnome-browser-connector
                                  (Python, from `apt install gnome-browser-connector`)
                                                        │
                                  D-Bus on the SESSION bus
                                                        ▼
                                  org.gnome.Shell.Extensions.InstallRemoteExtension(uuid)
                                  (handled by gnome-shell — your top bar)
                                                        │
                                  download zip → ~/.local/share/gnome-shell/extensions/<uuid>/
                                  prompt user → load JS into gnome-shell
```

The pieces on disk:

| Piece                | Path                                                                        | Where it comes from                    |
| -------------------- | --------------------------------------------------------------------------- | -------------------------------------- |
| Browser extension    | (in your Chrome profile)                                                    | Chrome Web Store                       |
| Native host manifest | `/etc/opt/chrome/native-messaging-hosts/org.gnome.browser_connector.json` | apt package`gnome-browser-connector` |
| Native host binary   | `/usr/bin/gnome-browser-connector`                                        | apt package`gnome-browser-connector` |
| D-Bus service        | `org.gnome.Shell.Extensions` (session bus, owned by `gnome-shell`)      | already running                        |

The manifest's `allowed_origins` whitelists exactly one extension ID, so only the official GNOME Shell integration extension can drive the bridge. The manifest's `path` tells Chrome which binary to spawn. That's the whole handshake.

### How Bussie's attack mirrors this exactly

Part 3 of this project recreates the same three-piece architecture, but swaps in our own pieces and aims at the **system bus** for maximum blast radius:

| GNOME's piece                                      | Bussie's equivalent                                                                  |
| -------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Browser ext "GNOME Shell integration"              | `attack/extension/` — our malicious Chrome extension (TypeScript)                 |
| `gnome-browser-connector` (apt-installed bridge) | `attack/bridge/` — C++ native-messaging host we ship                              |
| `gnome-shell` (session-bus service)              | `attack/service/` — C++ D-Bus service running **as root** on the system bus |

The only real differences are:

- our service runs as root, gated by an XML policy in `/usr/share/dbus-1/system.d/`;
- our policy is **deliberately permissive** (`<policy context="default">` allows any UID to call any method), which is the bug class the demo exists to illustrate;
- our service's method blindly executes `rm -rf -- <path>` instead of carefully installing a GNOME extension.

Remove the permissive policy block (or scope it to a specific UID/group) and the attack stops at the bus with `AccessDenied`. That single config line is the mitigation.

### "But why D-Bus at all? Couldn't the native host just do the work?"

Fair question, and it cuts to what D-Bus is actually *for*. **Native messaging is just a transport out of the browser sandbox; D-Bus is how you talk to an already-running process.** They sit at different layers, and almost every realistic flow needs both.

Take GNOME Shell extension install. A native host could absolutely `cp` an extension zip into `~/.local/share/gnome-shell/extensions/<uuid>/` — it runs as you and has filesystem access. But that's *not* installing anything as far as GNOME is concerned, because:

1. **The shell is already running.** Files on disk mean nothing until something tells the live `gnome-shell` process to load them. "Install" really means *"tell the running shell to register, enable, and activate this now"* — and you can only do that by calling a method on the running process. That's D-Bus.
2. **The consent dialog belongs to the shell.** The *"Do you want to install Caffeine?"* prompt is drawn by `gnome-shell` inside its own compositor, where no process outside the compositor can reach. Calling `InstallRemoteExtension` is how you ask the shell to draw it.
3. **Single source of truth.** The GNOME Extensions app, the `gnome-extensions` CLI, GNOME Tweaks, and the browser all install/enable extensions — and they all go through the *same* D-Bus interface. If install logic lived in each tool's native-messaging shim, their views of "what's installed" would diverge instantly.
4. **Crossing privilege boundaries.** A native host runs as your UID. It can't write to `/usr/share/gnome-shell/extensions/`, can't trigger a PolicyKit prompt, can't escalate on its own. A bus service can — that's the whole point of having one.
5. **Live interaction, not just install.** Enable, disable, open prefs, fetch error messages, reload after a crash — these are real-time conversations with a running process, not file-on-disk operations. D-Bus is shaped exactly for that; native messaging isn't.

The same logic explains why **Bussie's attack** routes through D-Bus instead of just having the bridge call `rm -rf` directly. The bridge runs as your UID, so a direct call would be bounded by your permissions — destructive but not catastrophic. Routing through a **system-bus service running as root** is what crosses the second boundary. Two transports, two boundaries: native messaging gets you out of the browser, D-Bus gets you out of your own UID.

## System dependencies (one script for the whole repo)

Every part of the project — Python (Part 1), C++ (Part 2), the attack demo (Part 3), and the D-Bus GUI inspectors — shares one apt-based dependency list. Run the top-level installer once:

```bash
bash dependencies.install.sh
```

The script is idempotent: it checks what's already installed and only `apt-get install`s what's missing. It re-execs under `sudo` automatically. It also installs `uv` (the Python package manager used by Part 1) for the invoking user if it's not already on PATH.

What it covers:

| Group           | Packages                                                                                                                             | Used for                                                             |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------- |
| Core            | `build-essential pkg-config git curl`                                                                                              | compiler, library probing, repo ops                                  |
| Part 1 (Python) | `python3-dev libcairo2-dev libgirepository-2.0-dev libgirepository1.0-dev gobject-introspection gir1.2-glib-2.0 meson ninja-build` | building`PyGObject` (a transitive dep of `pydbus`)               |
| Part 2 (C++)    | `libdbus-1-dev`                                                                                                                    | headers for the raw`libdbus-1` C API                               |
| Part 3 (attack) | `nlohmann-json3-dev nodejs npm`                                                                                                    | bridge JSON parsing + Chrome extension build                         |
| Bus viewers     | `bustle qttools5-dev-tools`                                                                                                        | message timeline (`bustle`) + Qt service browser (`qdbusviewer`) |

The standard CLI inspectors (`busctl`, `dbus-monitor`, `gdbus`) ship in the base `dbus` and `libglib2.0-bin` packages and are already present on any modern desktop, so they're not re-installed.

> **Distro support.** apt only (Debian / Ubuntu / Kali). For Fedora/Arch/openSUSE, install the equivalents manually — the script will print the full package list and exit.

The unified bus identifiers used by both Part 1 and Part 2:

|             |                                   |
| ----------- | --------------------------------- |
| Bus         | session                           |
| Bus name    | `com.bussie.HelloService`       |
| Object path | `/com/bussie/HelloObject`       |
| Interface   | `com.bussie.HelloInterface`     |
| Method      | `Hello(name: s) → greeting: s` |

Because the identifiers match, **a Python caller can drive the C++ service and a C++ caller can drive the Python service** — D-Bus is language-agnostic IPC.

## Run the Project (First Part) — Python

Code lives in `program/python/code/`. The Python tooling (uv-managed venv, `pydbus`, `PyGObject`) is bootstrapped by `install.dependencies.sh`.

```bash
bash program/python/install.dependencies.sh
```

That script installs the apt packages above, installs `uv` if missing, and creates `program/python/.venv` with `pydbus` and `PyGObject` from `pyproject.toml`.

Run the service:

```bash
source program/python/.venv/bin/activate
python3 program/python/code/service.py
```

In another terminal, run the caller:

```bash
source program/python/.venv/bin/activate
python3 program/python/code/caller.py        # default name "World"
python3 program/python/code/caller.py Manas  # custom name
```

Expected output:

```
Hello, Manas! (from Python D-Bus)
```

## Run the Project (Second Part) — C++

Code lives in `program/cpp/`. The build helper at `program/cpp/build.sh` installs apt deps if missing and compiles both binaries into `program/cpp/build/`.

```bash
bash program/cpp/build.sh
```

Sanity check the headers were found:

```bash
ls /usr/include/dbus-1.0/dbus/   # should list dbus.h, dbus-errors.h, …
```

Run the service:

```bash
./program/cpp/build/service
```

In another terminal, run the caller:

```bash
./program/cpp/build/caller        # default name "World"
./program/cpp/build/caller Manas  # custom name
```

Expected output:

```
[caller] Got reply: "Hello, Manas! Welcome to Bussie."
```

### Cross-language demo (this is the point of D-Bus)

With one service running, you can call it from the other language. Try every combination:

```bash
# Terminal A: start the C++ service
./program/cpp/build/service

# Terminal B: drive it with the Python caller
source program/python/.venv/bin/activate
python3 program/python/code/caller.py Manas
# → Hello, Manas! Welcome to Bussie.
```

```bash
# Terminal A: start the Python service
source program/python/.venv/bin/activate
python3 program/python/code/service.py

# Terminal B: drive it with the C++ caller
./program/cpp/build/caller Manas
# → [caller] Got reply: "Hello, Manas! (from Python D-Bus)"
```

This works because both services answer `org.freedesktop.DBus.Introspectable.Introspect` with matching XML, so any client (`pydbus`, `busctl`, `bustle`, `qdbusviewer`, raw `libdbus`) sees the same interface regardless of who's behind it.

You can also inspect either service from the command line:

```bash
busctl --user list | grep bussie
busctl --user introspect com.bussie.HelloService /com/bussie/HelloObject
busctl --user call com.bussie.HelloService /com/bussie/HelloObject \
    com.bussie.HelloInterface Hello s "Manas"
```

## Run the Project (Third Part)

The attack demo (Chrome extension → native-messaging bridge → root-owned system-bus D-Bus service) lives entirely under `attack/`. See `attack/README.md` for the full runbook.

> **VM only.** The service runs `rm -rf` as root on any path a local user supplies. Snapshot first.

```bash
curl -sSf https://raw.githubusercontent.com/scienmanas/Bussie/main/attack/install.sh | sudo bash
```

Or from a local checkout:

```bash
sudo bash attack/install.sh
```

The installer builds the C++ service and bridge, installs the D-Bus policy and systemd unit, registers the Chrome native-messaging-host manifest, and builds the unpacked extension at `attack/extension/build/`. Load that folder via `chrome://extensions` → *Load unpacked*.

**Hacking on the code?** Use `attack/dev.install.sh` instead — same end state, but it skips the git-clone step, does incremental C++ + webpack rebuilds, runs npm as your real user (so `node_modules/` and `build/` stay user-owned), and restarts the daemon to pick up your freshly compiled binary. Re-run after every edit to iterate.

**Only touching the extension?** `attack/extension/build.sh` builds just the extension (`npm ci`/`install` + `npm run build`) — no root, no D-Bus policy, no systemd unit. Pass `--clean` to wipe `node_modules/`/`build/` first. It prints the expected extension ID (`bmcdglmldgcgdlodlkdimbpofnpcmijn`) so you can confirm `chrome://extensions` loaded it correctly.

Then in the extension popup, type a path and click *Destroy*:

- Stage 1: a sandbox path like `/tmp/bussie-demo-victim` — folder vanishes.
- Stage 2 (snapshot first!): `/` — system dies.
- Mitigation: delete the `<policy context="default">` block in `/usr/share/dbus-1/system.d/org.bussie.Pwn.conf`, `systemctl reload dbus`, attack stops at the bus.
- Teardown: `sudo bash attack/uninstall.sh` cleans up everything the installer dropped (the Chrome extension itself stays — browsers won't let us remove it).

## Extra info: PolicyKit, PackageKit, and how privileged GUIs are actually built

Earlier sections mention **PolicyKit (polkit)** and **PackageKit** in passing as "the right way to do privileged D-Bus." This section explains what they actually are and how they fit together — useful context for understanding why the Bussie attack is the misconfiguration it is, not just the absence of one.

### What PolicyKit (polkit) is

polkit is Linux's framework for letting **unprivileged processes ask the system to do privileged things** — without giving the process root, and without making the user type `sudo`. The *"Authentication required"* dialog you see when GNOME Software installs a package, or when `systemctl restart foo` from a desktop session pops a password prompt — that's polkit.

It splits a privileged action into three actors:

| Actor               | Role                                                                                                            |
| ------------------- | --------------------------------------------------------------------------------------------------------------- |
| **Subject**   | The unprivileged process that wants to do something (e.g. GNOME Software)                                       |
| **Mechanism** | The privileged daemon that*can* do it — usually a D-Bus system-bus service running as root (e.g. PackageKit) |
| **polkitd**   | The arbiter — reads policy files, decides yes / no / "ask the user first"                                      |

The privileged mechanism never trusts the caller's UID directly. It calls `CheckAuthorization(action_id, subject)` on polkitd and acts only on the answer.

### Policy values

Each polkit action declares what kind of authorization it needs:

| Value                                    | Meaning                                          |
| ---------------------------------------- | ------------------------------------------------ |
| `yes`                                  | Always allow, no prompt                          |
| `no`                                   | Always reject                                    |
| `auth_self`                            | Prompt for*the calling user's* password        |
| `auth_admin`                           | Prompt for an*admin* password (root or sudoer) |
| `auth_self_keep` / `auth_admin_keep` | Same, but cache the "yes" for ~5 minutes         |
| `auth_admin_one_shot`                  | Admin password, never cached                     |

GNOME extension install uses something like `auth_admin_keep`: admin password the first time, no re-prompt for the next few minutes.

### How polkit shows a dialog when polkitd has no display

This is the genuinely clever part. `polkitd` runs as root, has no Wayland/X11 connection, and can't draw a single pixel. Yet `auth_admin_keep` reliably produces a GUI password dialog. How?

**polkit is split into two processes:**

| Process                               | UID      | Where it lives              | Talks to display?                                |
| ------------------------------------- | -------- | --------------------------- | ------------------------------------------------ |
| `polkitd`                           | root     | system daemon               | No — system bus only                            |
| **polkit authentication agent** | your UID | inside your desktop session | Yes — uses your`WAYLAND_DISPLAY` / X11 socket |

The agent is a separate binary — `polkit-gnome-authentication-agent-1`, `polkit-kde-authentication-agent-1`, `lxqt-policykit-agent`, or one baked into GNOME Shell. Your session manager starts it as a child of your login session, exactly like Files or Settings. It speaks GTK or Qt against whatever display socket your session already has — Wayland or X11, doesn't matter.

The handshake at session start:

```
agent (your UID) ──D-Bus──▶ polkitd (root)
    RegisterAuthenticationAgent(session, locale, object_path)
```

polkitd records: *"for session c2, route auth prompts to this object path on the agent's connection."*

The auth flow when something privileged is requested:

```
PackageKit (root) ──▶ polkitd: "is UID 1000 allowed to install packages?"
                          │
                          │ looks up rule → auth_admin_keep → "ask"
                          │
                          ▼ D-Bus call BACK out to the registered agent
                       BeginAuthentication(action_id, message, cookie, identities)
                          │
                       agent (your UID, your session)
                          │  draws a GTK dialog on Wayland/X11
                          │  user types password
                          │  agent verifies via PAM
                          ▼ D-Bus reply
                       AuthenticationAgentResponse2(cookie, identity)
                          │
                       polkitd → PackageKit: "yes, proceed"
                          │
                       PackageKit runs apt install as root
```

The architectural trick: **polkitd never touches the display, the agent never touches root.** They're connected by D-Bus method calls in *both* directions — the privileged daemon calls *back into* an unprivileged session process to ask the human. That kind of cross-privilege RPC over a single bus is something only D-Bus's per-message UID accounting (via `SO_PEERCRED` plus the agent's prior `Register` handshake) makes safe to do.

This is also why polkit works equally well on Wayland and X11 — polkit itself knows nothing about either. The agent inherits whatever display protocol the session is using; polkit just talks D-Bus to it.

### What PackageKit is

PackageKit is the canonical real-world example of the architecture Bussie's `org.bussie.Pwn` mimics — except PackageKit does it correctly.

**It's a D-Bus system service that abstracts package management.**

- Owns `org.freedesktop.PackageKit` on the **system bus**.
- Runs as **root** (because installing packages needs root).
- Has internal backends for `apt`, `dnf`, `zypper`, `pacman`, etc. The D-Bus interface is identical across distros.

It exists for three reasons:

| Problem                          | Without PackageKit                       | With PackageKit                             |
| -------------------------------- | ---------------------------------------- | ------------------------------------------- |
| GUI needs to install a package   | `pkexec apt install`, parse stderr     | One D-Bus method call                       |
| Same GUI on Debian and Fedora    | Two code paths                           | One bus interface, backend handles the rest |
| GUI needs root but can't be root | Shell out to`sudo`, no GUI integration | polkit handles auth, agent pops the dialog  |

GNOME Software and KDE Discover work across distros because they speak PackageKit, not apt/dnf directly. The frontend stays at user UID and never sees root; PackageKit is the privileged mechanism. Everything below is wired together:

```
GNOME Software (your UID, GUI)
   │  D-Bus call: org.freedesktop.PackageKit.InstallPackages(["firefox"])
   ▼
PackageKit (root, system bus)
   │  CheckAuthorization("org.freedesktop.packagekit.package-install")
   ▼
polkitd (root)
   │  rule says auth_admin_keep
   ▼
polkit agent (your UID, your session)
   │  pops dialog, user types password, verifies via PAM
   ▼ all answers travel back up
PackageKit forks: /usr/bin/apt-get install firefox
```

Every layer has exactly the privilege it needs. The GUI never gets root. polkit never sees the display. apt never sees the GUI. Each privilege boundary is crossed by a single, well-defined D-Bus call.

### The Bussie contrast

The structure of `org.bussie.Pwn` is identical to PackageKit on paper — system bus, root service, user-UID caller — but Bussie deliberately omits the polkit step:

```
caller ──▶ org.bussie.Pwn.Delete ──▶ rm -rf as root
```

No `CheckAuthorization()` in the service code. No `.policy` file declared. No agent prompt. The `<allow send_destination="org.bussie.Pwn"/>` line in `org.bussie.Pwn.conf` lets the message reach the service, and the service trusts the caller unconditionally. That's the misconfiguration the demo illustrates: **D-Bus + system service + root *minus* polkit gating = local root for free.**

A correct version would either reject the call without polkit auth, or register an action like `org.bussie.pwn.delete-path` set to `auth_admin` — and the same click would produce a password dialog instead of a destroyed system.

This is the punchline of the whole project: D-Bus, polkit, and PackageKit aren't separate things to learn — they're three layers of the same answer to *"how does a user-UID GUI ask the system to do something only root can do, safely?"* Bussie shows what happens when you build the bottom layer (D-Bus service) without the middle one (polkit).

## Extra info: how this would look in production (Chrome Web Store)

The Bussie installer hardcodes `EXTENSION_ID="bmcdglmldgcgdlodlkdimbpofnpcmijn"` (see `attack/install.sh:18`) and pins it into `extension/manifest.json` via the `"key"` field. That's a **dev workaround** for the fact that there's no Chrome Web Store listing. In a real shipped product, the flow is genuinely different — and cryptographically stronger.

### Step 1 — The Chrome Web Store assigns the ID, not you

On the first upload to the Chrome Web Store Developer Dashboard:

1. Zip up `manifest.json` + sources. **Omit the `"key"` field** — you don't need it in prod.
2. Upload the `.zip`.
3. The store backend generates a fresh RSA keypair *for this listing*:
   - The **public key** is SHA-256 hashed → first 16 bytes → each hex nibble (0–15) mapped to letters `a–p` → that's the **extension ID** (e.g. `nkbihfbeogaeaoehlefnkodbefgpgknn` for MetaMask). This is why every extension ID is exactly 32 lowercase letters in the range a–p.
   - The **private key** is held server-side by Google. You never see it.
4. The dashboard shows you the assigned ID. **From this moment, the ID is permanent for the lifetime of the listing** — Chrome will only load `.crx` files signed by the matching private key under that ID.

### Step 2 — Bake the assigned ID into your native-messaging manifest

The system-side installer (`.deb` / `.pkg` / Homebrew formula / `.msi` / etc.) hard-codes the store-assigned ID into `allowed_origins`:

```json
{
  "name": "com.yourapp.bridge",
  "path": "/usr/local/bin/yourapp-bridge",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://nkbihfbeogaeaoehlefnkodbefgpgknn/"
  ]
}
```

This is structurally what `attack/install.sh` does for Bussie — except in prod the ID would be the store's, not one derived from a self-generated `"key"`.

### Step 3 — Two independent install channels

The Chrome Web Store **does not distribute native-messaging hosts** — Chrome refuses to let extensions drop binaries onto the OS, that's the whole point of the sandbox. So every real extension+bridge product ships through *two* separate channels:

| Piece       | Distribution                              | Where it lands                                                             |
| ----------- | ----------------------------------------- | -------------------------------------------------------------------------- |
| Extension   | Chrome Web Store (one-click install)      | Chrome's sandboxed extension storage                                       |
| Native host | apt / yum / Homebrew /`.exe` / `.msi` | `/usr/local/bin/…`, `/etc/opt/chrome/native-messaging-hosts/…`, etc. |

The user installs both, in either order. This is why *GNOME Shell integration* tells you *"you also need `apt install gnome-browser-connector`"* — that second command installs the NM host. The browser side and the system side are decoupled by design.

### Step 4 — Runtime handshake (same shape as dev)

```
extension (ID: nkbihfbeogaeaoehlefnkodbefgpgknn)
   │  sendNativeMessage("com.yourapp.bridge", {...})
   ▼
Chrome
   │  1. Reads /etc/opt/chrome/native-messaging-hosts/com.yourapp.bridge.json
   │  2. Checks calling extension's ID against allowed_origins
   │       MATCH → spawn /usr/local/bin/yourapp-bridge as a child process
   │       MISS  → "Specified native messaging host not found"
   ▼
yourapp-bridge reads framed JSON from stdin, replies on stdout
```

The ID match is the **only** auth the bridge does. No tokens, no secrets — Chrome is the trusted middleman because Chrome alone knows which extension is *really* speaking (it manages that process and chose to spawn this child).

### Why prod is cryptographically stronger than unpacked dev

This is the key reason the `"key"` field is a *workaround*, not a deployment strategy:

|                           | Unpacked dev (`"key"` field)                                                | Web Store published                                                                 |
| ------------------------- | ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Who holds the keypair     | The developer (anyone who can read source)                                    | Google (private key never leaves Google)                                            |
| Can someone forge the ID? | **Yes** — copy `"key"`, build a different extension, get the same ID | **No** — Chrome only loads `.crx` files signed by the matching private key |
| Code provenance           | Your local disk; anything can be there                                        | Chrome auto-downloads signed CRX from the store; tamper-evident                     |
| Update path               | Manual reload                                                                 | Auto-update, signature-verified                                                     |

In prod, `allowed_origins` is **cryptographically meaningful**: any binary on disk claiming to be the published extension gets a different ID unless it's the genuinely-signed CRX from the publisher's keypair. The native host can trust the ID.

In unpacked mode, the same allowlist is only **organizationally meaningful** — anyone with the source can rebuild and claim the same ID. Which is exactly why Bussie ships the `"key"` field in plain sight: the demo isn't pretending to be secure, it's just keeping the ID stable across machines so the installer works one-shot.

### The dev–prod parity trick

Some real extensions deliberately *do* commit a `"key"` field to their source — to make unpacked dev builds get the same ID as the published version. The flow is:

1. Publish to the store → get assigned ID `X` and public key `K`.
2. Extract `K` from any installed copy of the published extension (or from the dashboard).
3. Paste `K` as the `"key"` field in your dev `manifest.json`.
4. From then on, `npm run build` produces an unpacked extension with ID `X`, matching prod.

This keeps OAuth redirect URIs, `allowed_origins` allowlists, server-side allowlists, and any other ID-tied config identical in dev and prod. Bussie does step 3 with a self-generated `K` because there's no step 1 — same mechanism, no Web Store involved.

### Real-world example: GNOME Shell integration

| Piece                                          | Source                                  | Identifier                                                                  |
| ---------------------------------------------- | --------------------------------------- | --------------------------------------------------------------------------- |
| Browser extension*"GNOME Shell integration"* | Chrome Web Store                        | `gphhapmejobijbbhgpjhcjognlahblep`                                        |
| Native host`gnome-browser-connector`         | `apt install gnome-browser-connector` | `/usr/bin/gnome-browser-connector`                                        |
| NM host manifest                               | shipped by the apt package              | `/etc/opt/chrome/native-messaging-hosts/org.gnome.browser_connector.json` |
| `allowed_origins`                            | hardcoded by maintainers                | `["chrome-extension://gphhapmejobijbbhgpjhcjognlahblep/", …]`            |

The user clicks *Install* on the Web Store and runs `apt install gnome-browser-connector`. Those two actions are all there is. Everything else (manifest path, ID matching, binary discovery) was prepared by the developers *against the Web-Store-assigned ID*, months in advance — that hardcoded ID is the contract between the published extension and the system-side host.

The `EXTENSION_ID` constant at `attack/install.sh:18` is the demo equivalent of *"the Web Store would have given us this value, and we're pretending it did."*

## Project Tree

```
Bussie/
├── README.md                                    # this file — concepts + per-part run instructions
├── LICENSE
├── dependencies.install.sh                      # top-level apt installer (Parts 1 + 2 + 3 + viewers)
├── viewer.dependencies.sh                       # standalone installer for just the GUI inspectors
│
├── program/                                     # Parts 1 & 2 — learn D-Bus
│   ├── python/                                  # Part 1: pydbus on the session bus
│   │   ├── code/
│   │   │   ├── service.py                       # publishes com.bussie.HelloService
│   │   │   └── caller.py                        # calls Hello() on whoever owns the name
│   │   ├── install.dependencies.sh              # bootstraps apt deps + uv venv
│   │   ├── public.dependencies.sh               # end-user subset (no build headers)
│   │   ├── pyproject.toml                       # uv-managed deps: pydbus, PyGObject
│   │   └── .python-version
│   │
│   └── cpp/                                     # Part 2: raw libdbus-1, no wrappers
│       ├── service.cpp                          # owns com.bussie.HelloService (same as Python)
│       ├── caller.cpp                           # calls Hello() — works against either service
│       ├── generic.cpp                          # extra reference code
│       ├── build.sh                             # compiles both binaries into build/
│       └── README.md
│
└── attack/                                      # Part 3 — the demo (VM ONLY, destructive)
    ├── install.sh                               # curl-pipeable bootstrap (clones repo, full clean build)
    ├── dev.install.sh                           # local-checkout dev loop (incremental, user-owned npm)
    ├── uninstall.sh                             # clean teardown (mirrors install.sh)
    ├── README.md                                # short runbook + mitigation
    │
    ├── service/                                 # ROOT-owned system-bus D-Bus service
    │   ├── src/service.cpp                      # owns org.bussie.Pwn, method Delete(s)
    │   ├── config/
    │   │   ├── org.bussie.Pwn.conf              # XML policy — DELIBERATELY PERMISSIVE
    │   │   └── bussie.service                   # systemd unit, User=root
    │   └── Makefile
    │
    ├── bridge/                                  # Chrome native-messaging host (the trampoline)
    │   ├── src/bridge.cpp                       # reads NM frames from stdin, calls org.bussie.Pwn.Delete
    │   ├── manifests/
    │   │   └── com.bussie.bridge.json.in        # NM manifest template; __EXTENSION_ID__ filled in at install
    │   └── Makefile
    │
    └── extension/                               # malicious Chrome extension (MV3 + TypeScript)
        ├── build.sh                             # standalone build (npm ci/install + npm run build), no root needed
        ├── manifest.json                        # includes "key" field for deterministic extension ID
        ├── package.json                         # webpack build scripts
        ├── tsconfig.json
        ├── webpack.config.js                    # auto-discovers entries from src/, copies public/ to build/
        ├── public/
        │   └── popup.html                       # red warning banner + path input + "Destroy" button
        └── src/
            ├── popup.ts                         # reads input, posts {path} to background
            └── background.ts                    # service worker; forwards to bridge via sendNativeMessage
```

The three parts share the same bus identifiers (`com.bussie.HelloService` for the learning parts, `org.bussie.Pwn` for the attack), so any client — Python, C++, `busctl`, `bustle`, `qdbusviewer` — can drive any compatible service interchangeably.

## Contribution

This is repository is not open for any sort of contribution.

## LICENSE

This project is published under MIT LICENSE. The Author doesn't hold any liability to the damage caused to any person using any part of this code or application or extension.
