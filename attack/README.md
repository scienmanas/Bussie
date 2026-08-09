# Bussie Attack Demo

A three-piece demo that walks a payload from a Chrome extension, through a native-messaging bridge, into a misconfigured **system-bus** D-Bus service running as root, and out the other side as `rm -rf` on whatever path the user types.

> **VM only.** This is destructive on purpose. Run it inside a disposable VM with a snapshot. Do not install on a machine with anything you care about.

## Table of Contents

- [Pieces](#pieces)
- [Install](#install)
  - [Local-dev iteration (`dev.install.sh`)](#local-dev-iteration-devinstallsh)
  - [Extension-only builds (`extension/build.sh`)](#extension-only-builds-extensionbuildsh)
- [Load the extension](#load-the-extension)
- [Demo flow](#demo-flow)
  - [Stage 1 — safe sandbox](#stage-1--safe-sandbox)
  - [Stage 2 — full blast](#stage-2--full-blast)
  - [Mitigation](#mitigation)
- [Protection (defense in depth)](#protection-defense-in-depth)
- [Uninstall](#uninstall)
- [Direct bridge smoke-test (no Chrome)](#direct-bridge-smoke-test-no-chrome)
- [Build manually (skip install.sh)](#build-manually-skip-installsh)

## Pieces

```
extension/   Chrome MV3 extension (TypeScript + webpack)
             — popup with a path input + Destroy button.
             — build.sh builds just this folder (no root needed).
bridge/      C++ native-messaging host.
             — reads framed JSON from Chrome over stdin,
               calls org.bussie.Pwn.Delete on the system bus.
service/     C++ D-Bus service.
             — owns org.bussie.Pwn on the system bus, runs as root,
               does `rm -rf -- <path>` with no validation.
install.sh       One-shot installer (curl-pipeable, runs as root).
                 Clones the repo to /opt/bussie if not in a checkout.
dev.install.sh   Same install steps, but for local-checkout developers.
                 Skips git-clone and `make clean`; incremental rebuilds;
                 runs npm as your real user (not root).
uninstall.sh     One-shot teardown (mirrors install.sh, runs as root).
```

The deliberately-permissive line is in `service/config/org.bussie.Pwn.conf`:

```xml
<policy context="default">
  <allow send_destination="org.bussie.Pwn"/>
  <allow send_interface="org.bussie.Pwn"/>
</policy>
```

That one block is what lets any local UID (including the user-spawned bridge) call a root method. Remove it and the attack dies at the bus with `AccessDenied`.

## Install

```bash
curl -sSf https://raw.githubusercontent.com/scienmanas/Bussie/main/attack/install.sh | sudo bash
```

…or, from a local checkout:

```bash
sudo bash attack/install.sh
```

### Local-dev iteration (`dev.install.sh`)

If you cloned the repo and want to **edit the C++ / TS source, rebuild, and reinstall in a loop**, use the dev script instead:

```bash
sudo bash attack/dev.install.sh
```

Differences from `install.sh`:

- Never clones — fails fast if you're not in a checkout (so you don't accidentally pollute `/opt/bussie`).
- `make` only, no `make clean` — incremental C++ rebuilds.
- `npm install` only if `node_modules/` is missing — webpack runs incrementally too.
- Runs `npm install` and `npm run build` as your **real user** (via `$SUDO_USER`), so `node_modules/` and `extension/build/` stay user-owned and you don't have to `sudo chown` them after every run.
- `systemctl restart` (not just `enable --now`) so the freshly compiled binary actually replaces the running one.

Iteration loop:

1. Edit `service/src/service.cpp`, `bridge/src/bridge.cpp`, or any `extension/src/*.ts`.
2. `sudo bash attack/dev.install.sh`
3. For extension changes only — click the reload icon on the extension card in `chrome://extensions`.

### Extension-only builds (`extension/build.sh`)

If you're only touching the TypeScript/extension side and don't need the D-Bus policy, systemd unit, or native-messaging manifest reinstalled, skip the full (dev.)install.sh and just build the extension:

```bash
bash attack/extension/build.sh            # npm ci/install + npm run build
bash attack/extension/build.sh --clean    # wipe node_modules/build first, then build
```

No root, no D-Bus, no systemd — it's `cd attack/extension && npm ci && npm run build` with dependency/version checks and a friendlier summary. Output lands in `attack/extension/build/`, same as the installers produce; load it the same way (`chrome://extensions` → *Load unpacked*). It's a convenience wrapper, not a substitute for `install.sh`/`dev.install.sh` — the bridge, service, and NM manifest still need one of those.

The installer:

1. apt-installs `libdbus-1-dev`, `nlohmann-json3-dev`, `build-essential`, `pkg-config`, `nodejs`, `npm`.
2. Builds `bussie-service` → `/usr/local/sbin/bussie-service`.
3. Builds `bussie-bridge` → `/usr/local/bin/bussie-bridge`.
4. Drops the D-Bus policy at `/usr/share/dbus-1/system.d/org.bussie.Pwn.conf`.
5. Drops the systemd unit at `/etc/systemd/system/bussie.service` and enables it.
6. Drops the Chrome native-messaging-host manifest at `/etc/opt/chrome/native-messaging-hosts/com.bussie.bridge.json` (and the Chromium equivalent).
7. Runs `npm ci && npm run build` in `extension/` to produce `extension/build/`.

The Chrome extension uses a fixed `key` in `manifest.json`, so its ID is always `bmcdglmldgcgdlodlkdimbpofnpcmijn` — in `install.sh`/`dev.install.sh`/`build.sh` output and when loaded unpacked. That ID isn't arbitrary — Chrome derives it directly from that `key` value: the `key` field is the extension's RSA public key (DER, base64-encoded), and Chrome SHA-256-hashes it, takes the first 16 bytes, and maps each hex nibble (0–15) to a letter `a`–`p`. Same public key in, same 32-letter ID out, every time — which is exactly why baking a fixed `key` into `manifest.json` is enough to keep the ID stable across every machine/build instead of it varying based on the extension's on-disk path (which is what happens for unpacked extensions with no `key` field). That same ID is baked into the native-messaging manifest's `allowed_origins`. This is a dev-only workaround since there's no real Chrome Web Store listing — see the top-level README's ["Extra info: how this would look in production (Chrome Web Store)"](../README.md) section for how a real store submission would assign (and permanently keep) the ID instead.

## Load the extension

1. Open `chrome://extensions`.
2. Toggle **Developer mode** on.
3. **Load unpacked** → choose `attack/extension/build/` (or `/opt/bussie/attack/extension/build/` if you used curl install).
4. Confirm the loaded ID matches `bmcdglmldgcgdlodlkdimbpofnpcmijn`.

## Demo flow

### Stage 1 — safe sandbox

```bash
mkdir -p /tmp/bussie-demo-victim
touch /tmp/bussie-demo-victim/file{1,2,3}
ls /tmp/bussie-demo-victim
```

Click the extension icon → type `/tmp/bussie-demo-victim` → **Destroy**.
The folder is gone. The popup shows `{"ok":true,"result":"ok: /tmp/bussie-demo-victim"}`.

### Stage 2 — full blast

> **Snapshot the VM first.**

Click the extension icon → type `/` → **Destroy**.

The service runs `rm -rf -- /` as root. The system dies. Restore the snapshot.

### Mitigation

```bash
sudo $EDITOR /usr/share/dbus-1/system.d/org.bussie.Pwn.conf
# remove the <policy context="default"> block
sudo systemctl reload dbus
```

Re-run stage 1. The popup now shows `AccessDenied` — the call is rejected at the bus, before reaching the service. One config line is the difference between a remote shell and a locked door.

## Protection (defense in depth)

The [Mitigation](#mitigation) above closes *this* hole — the one permissive policy block — but it's a single layer. A real system-bus service needs several independent layers, so that one mistake doesn't equal root:

1. **Scope the policy, don't just delete it.** `<policy context="default">` means "any local UID may call this." A production policy either omits that block entirely (deny-by-default, keeping only the `user="root"` ownership block) or scopes it to the specific `user=`/`group=` that actually needs to call the service — not every process on the machine.

2. **Gate the privileged method behind polkit.** The bus policy only decides whether a message *reaches* the service — it isn't an authorization decision. `service.cpp` should call `CheckAuthorization()` against a declared polkit action (e.g. `org.bussie.pwn.delete-path`, set to `auth_admin`) before doing anything destructive. That's the step [PackageKit takes](../README.md#what-packagekit-is) and Bussie deliberately skips — see the top-level README's ["The Bussie contrast"](../README.md#the-bussie-contrast) for the full comparison. With polkit wired in, even a caller the bus policy allows still has to clear a live authentication prompt.

3. **Never expose "run this as root" as the primitive.** The deeper problem is that `Delete(path)` accepts *any* string and shells out to `rm -rf --no-preserve-root`. A safe service doesn't take arbitrary paths — it exposes narrow, purpose-built operations and validates/allowlists input server-side, instead of trusting the caller's string as an argument to something this destructive.

4. **Harden the systemd unit.** `bussie.service` runs as bare `User=root` with no sandboxing. Directives like `ProtectSystem=strict`, `ProtectHome=`, `NoNewPrivileges=true`, `CapabilityBoundingSet=`, and `ReadOnlyPaths=`/`InaccessiblePaths=` shrink what the process can touch even if the D-Bus/polkit layers above it are somehow bypassed.

5. **Log and audit privileged calls.** The demo service only writes to stderr. A real one should log durably (journal, syslog, or an audit subsystem) who called what, so a bypass is at least detectable after the fact instead of silent.

Each layer is a separate check an attacker has to clear. The demo only shows layer 1 falling over, because that's the one line `org.bussie.Pwn.conf` deliberately leaves open — "remove that policy block" is the *minimum* fix, not the complete one.

## Uninstall

```bash
sudo bash attack/uninstall.sh
```

Stops + disables the service, removes the binaries, the D-Bus policy, the systemd unit, and both Chrome/Chromium NM manifests, then reloads dbus.

Two things `uninstall.sh` deliberately does **not** do:

- **Remove the Chrome/Chromium extension.** Browsers refuse external removal of dev-loaded extensions. Open `chrome://extensions` and click *Remove* on the Bussie entry.
- **Delete `/opt/bussie/`** (the repo clone created by curl install). If the uninstall script lives inside that path it would be deleting itself mid-run. Once `uninstall.sh` finishes, run `sudo rm -rf /opt/bussie` to drop the clone.

## Direct bridge smoke-test (no Chrome)

```bash
mkdir -p /tmp/bussie-demo-victim && touch /tmp/bussie-demo-victim/x
printf '\x1f\x00\x00\x00{"path":"/tmp/bussie-demo-victim"}' \
    | /usr/local/bin/bussie-bridge | xxd | head
```

The first 4 bytes of the output are the response length, then the JSON. The folder should be gone.

## Build manually (skip install.sh)

```bash
sudo apt install -y build-essential pkg-config libdbus-1-dev nlohmann-json3-dev
make -C service
make -C bridge
cd extension && npm ci && npm run build
```

You still have to drop the policy, systemd unit, and NM manifest by hand if you go this route — `install.sh` exists precisely so you don't have to.
