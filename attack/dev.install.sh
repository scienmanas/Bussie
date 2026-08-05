#!/usr/bin/env bash
# Bussie attack demo — DEVELOPER install (local checkout only).
#
# Use this when you already have the repo cloned and you're iterating
# on the code. It's a faster, repo-aware version of attack/install.sh:
#   - assumes you already have the source (errors out if not)
#   - skips `git clone` — never touches /opt/bussie
#   - skips `make clean` — relies on Makefile incremental rebuilds
#   - skips `npm ci` — runs `npm install` once, then reuses node_modules
#   - runs npm as your real user (via $SUDO_USER) so node_modules and
#     extension/build/ aren't root-owned
#   - apt-installs missing deps (dpkg -s check; no apt-get update unless
#     something's actually missing)
#   - drops the binaries / D-Bus policy / systemd unit / NM manifests
#     to the same system paths as install.sh
#   - restarts the daemon so a freshly compiled binary takes effect
#
# Iteration loop:
#   1. Edit service/src/service.cpp, bridge/src/bridge.cpp, or extension/src/*.ts
#   2. sudo bash attack/dev.install.sh
#   3. For extension changes — click the reload icon on the extension
#      card in chrome://extensions (the unpacked build folder is already
#      registered with Chrome from the first load).
#
# Run from anywhere — script resolves its own path:
#   sudo bash attack/dev.install.sh

set -euo pipefail

EXTENSION_ID="bmcdglmldgcgdlodlkdimbpofnpcmijn"

c_red()    { printf "\033[31m%s\033[0m\n" "$*"; }
c_green()  { printf "\033[32m%s\033[0m\n" "$*"; }
c_blue()   { printf "\033[34m%s\033[0m\n" "$*"; }
c_yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
step()     { c_blue "==> $*"; }

# -------- 0. require root ------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    step "Re-executing under sudo"
    exec sudo -E bash "${BASH_SOURCE[0]:-$0}" "$@"
fi

# -------- 1. locate the local checkout ----------------------------------
# readlink -f : allow to follow symlinks to get the correct path for symlinks too
SCRIPT_PATH=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
fi
if [[ -z "$SCRIPT_PATH" ]]; then
    c_red "Cannot determine script path. Run with:"
    c_red "    sudo bash attack/dev.install.sh"
    exit 1
fi
ATTACK_DIR="$(dirname "$SCRIPT_PATH")"

if [[ ! -f "$ATTACK_DIR/service/Makefile" || \
      ! -f "$ATTACK_DIR/bridge/Makefile"  || \
      ! -f "$ATTACK_DIR/extension/package.json" ]]; then
    c_red "Expected a local checkout at: $ATTACK_DIR"
    c_red "Missing one of:"
    c_red "  - service/Makefile"
    c_red "  - bridge/Makefile"
    c_red "  - extension/package.json"
    c_red ""
    c_red "If you don't have the repo cloned, use attack/install.sh instead —"
    c_red "it clones the repo to /opt/bussie/ for you. dev.install.sh is for"
    c_red "users who already have the source and just want to compile + run."
    exit 1
fi
step "Using local checkout at $ATTACK_DIR"
cd "$ATTACK_DIR"

# -------- 2. apt dependencies (only what's missing) ---------------------
DEV_PKGS=( build-essential pkg-config libdbus-1-dev nlohmann-json3-dev nodejs npm )
MISSING=()
for p in "${DEV_PKGS[@]}"; do
    if ! dpkg -s "$p" >/dev/null 2>&1; then
        MISSING+=("$p")
    fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    step "Installing missing apt packages: ${MISSING[*]}"
    apt-get update -qq
    apt-get install -y --no-install-recommends "${MISSING[@]}"
else
    step "All apt deps already installed."
fi

# -------- 3. incremental C++ builds -------------------------------------
step "Building bussie-service (incremental)"
make -C service

step "Building bussie-bridge (incremental)"
make -C bridge

# -------- 4. install binaries -------------------------------------------
# `install` does unlink+create, so a running daemon keeps its old inode
# while the new binary lands at the path — `systemctl restart` below
# then picks the new one up.
step "Installing binaries to /usr/local"
install -m 0755 -D service/bussie-service /usr/local/sbin/bussie-service
install -m 0755 -D bridge/bussie-bridge   /usr/local/bin/bussie-bridge

# -------- 5. D-Bus policy + systemd unit --------------------------------
step "Installing D-Bus policy and systemd unit"
install -m 0644 -D service/config/org.bussie.Pwn.conf \
        /usr/share/dbus-1/system.d/org.bussie.Pwn.conf
install -m 0644 -D service/config/bussie.service \
        /etc/systemd/system/bussie.service

# -------- 6. native-messaging manifests (Chrome + Chromium) -------------
step "Installing native-messaging manifest (extension ID: $EXTENSION_ID)"
NM_TMP="$(mktemp)"
sed "s/__EXTENSION_ID__/$EXTENSION_ID/g" \
    bridge/manifests/com.bussie.bridge.json.in > "$NM_TMP"
install -m 0644 -D "$NM_TMP" \
        /etc/opt/chrome/native-messaging-hosts/com.bussie.bridge.json
install -m 0644 -D "$NM_TMP" \
        /etc/chromium/native-messaging-hosts/com.bussie.bridge.json
rm -f "$NM_TMP"

# -------- 7. (re)start the service --------------------------------------
step "Reloading systemd; restarting bussie.service to pick up new binary"
systemctl daemon-reload
systemctl enable bussie.service >/dev/null 2>&1 || true
systemctl restart bussie.service
systemctl reload dbus 2>/dev/null || systemctl restart dbus 2>/dev/null || true

# -------- 8. build the Chrome extension ---------------------------------
# Run npm as the real user so node_modules/ and extension/build/ end up
# owned by them, not by root. Falls back to stat'ing the package.json
# owner if SUDO_USER isn't set (e.g. user already had a root shell open).
DEV_USER="${SUDO_USER:-$(stat -c %U "$ATTACK_DIR/extension/package.json")}"
step "Building the Chrome extension (as user: $DEV_USER)"
cd "$ATTACK_DIR/extension"
if [[ ! -d node_modules ]]; then
    step "node_modules missing — running npm install"
    sudo -u "$DEV_USER" npm install --no-audit --no-fund
else
    step "node_modules already present — skipping npm install"
    step "  (delete extension/node_modules to force a clean reinstall)"
fi
sudo -u "$DEV_USER" npm run build
EXT_BUILD_DIR="$ATTACK_DIR/extension/build"

# -------- 9. summary ----------------------------------------------------
echo
c_green "================================================================="
c_green "  Bussie attack demo — dev install complete."
c_green "================================================================="
echo

c_red "NEXT STEP — REQUIRED (the installer cannot do this for you):"
echo
echo "  Load the unpacked extension into Chrome (or Chromium):"
echo
echo "    1. Open  chrome://extensions   (or  chromium://extensions)"
echo "    2. Toggle Developer mode ON (top right)"
echo "    3. Click \"Load unpacked\""
echo "    4. Select this folder:"
c_green "         $EXT_BUILD_DIR"
echo "    5. Confirm the loaded extension ID is:"
c_green "         $EXTENSION_ID"
echo
echo "  Already loaded? After every code change:"
echo "    - re-run this script (rebuilds binaries + extension, restarts daemon)"
echo "    - click the reload icon on the extension card in chrome://extensions"
echo

c_blue "Service status:"
systemctl --no-pager --lines=3 status bussie.service || true
echo

c_yellow "Where things landed:"
echo "  Service binary:       /usr/local/sbin/bussie-service"
echo "  Bridge binary:        /usr/local/bin/bussie-bridge"
echo "  D-Bus policy:         /usr/share/dbus-1/system.d/org.bussie.Pwn.conf"
echo "  systemd unit:         /etc/systemd/system/bussie.service"
echo "  Chrome NM manifest:   /etc/opt/chrome/native-messaging-hosts/com.bussie.bridge.json"
echo "  Chromium NM manifest: /etc/chromium/native-messaging-hosts/com.bussie.bridge.json"
echo "  Extension build dir:  $EXT_BUILD_DIR"
echo

c_blue "Dev iteration loop:"
echo "  1. Edit service/src/service.cpp, bridge/src/bridge.cpp, or any extension/src/*.ts"
echo "  2. Re-run: sudo bash $SCRIPT_PATH"
echo "  3. For extension changes — click reload on the extension card"
echo

c_blue "Stage 1 demo (safe sandbox target):"
echo "  mkdir -p /tmp/bussie-demo-victim && touch /tmp/bussie-demo-victim/file1"
echo "  click the extension → type  /tmp/bussie-demo-victim  → Destroy"
echo

c_red "Stage 2 demo (full blast — TAKE A VM SNAPSHOT FIRST):"
echo "  click the extension → type  /  → Destroy"
echo

c_blue "Uninstall (clean teardown when you're done):"
echo "  sudo bash $ATTACK_DIR/uninstall.sh"
echo
