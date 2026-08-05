#!/usr/bin/env bash
# Bussie attack demo — bootstrap installer.
#
# One-liner:
#   curl -sSf https://raw.githubusercontent.com/scienmanas/Bussie/main/attack/install.sh | sudo bash
# From a local checkout:
#   sudo bash attack/install.sh
#
# By default apt/make/npm output is hidden — only the "==>" progress lines
# print, so demo runs stay clean. Pass --view (or -v) to see full output:
#   sudo bash attack/install.sh --view
#   curl -sSf .../install.sh | sudo bash -s -- --view   # note the `-s --`,
#                                                        # needed so bash
#                                                        # forwards the flag
#                                                        # instead of eating it
#
# INSECURE BY DESIGN. Installs a system-bus D-Bus service that runs
# `rm -rf` as root on any path a local user supplies, plus a Chrome
# native-messaging host that forwards browser-extension input to it.
# Run only inside a disposable VM with a snapshot.

set -euo pipefail

REPO_URL="https://github.com/scienmanas/Bussie.git"
INSTALL_PREFIX="/opt/bussie"
EXTENSION_ID="bmcdglmldgcgdlodlkdimbpofnpcmijn"

VERBOSE=0
for arg in "$@"; do
    case "$arg" in
        -v|--verbose|--view) VERBOSE=1 ;;
    esac
done

c_red()   { printf "\033[31m%s\033[0m\n" "$*"; }
c_green() { printf "\033[32m%s\033[0m\n" "$*"; }
c_blue()  { printf "\033[34m%s\033[0m\n" "$*"; }
step()    { c_blue "==> $*"; }

# Run a command quietly, only surfacing its output if it fails (or --view is set).
LOG_FILE="$(mktemp)"
trap 'rm -f "$LOG_FILE"' EXIT
run() {
    if [[ $VERBOSE -eq 1 ]]; then
        "$@"
    elif ! "$@" >"$LOG_FILE" 2>&1; then
        c_red "Command failed: $*"
        cat "$LOG_FILE" >&2
        exit 1
    fi
}

# -------- 0. require root ------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    step "Re-executing under sudo"
    exec sudo -E bash "${BASH_SOURCE[0]:-$0}" "$@"
fi

# -------- 1. locate or clone the repo -----------------------------------
SCRIPT_PATH=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
fi

if [[ -n "$SCRIPT_PATH" && -f "$(dirname "$SCRIPT_PATH")/service/Makefile" ]]; then
    ATTACK_DIR="$(dirname "$SCRIPT_PATH")"
    step "Using local checkout at $ATTACK_DIR"
else
    step "No local checkout detected — cloning $REPO_URL into $INSTALL_PREFIX"
    if [[ ! -x "$(command -v git)" ]]; then
        run apt-get update -qq
        run apt-get install -y --no-install-recommends git
    fi
    if [[ -d "$INSTALL_PREFIX/.git" ]]; then
        run git -C "$INSTALL_PREFIX" fetch --depth 1 origin
        run git -C "$INSTALL_PREFIX" reset --hard origin/HEAD
    else
        rm -rf "$INSTALL_PREFIX"
        run git clone --depth 1 "$REPO_URL" "$INSTALL_PREFIX"
    fi
    ATTACK_DIR="$INSTALL_PREFIX/attack"
fi
cd "$ATTACK_DIR"

# -------- 2. apt dependencies -------------------------------------------
step "Installing build & runtime dependencies"
run apt-get update -qq
run apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    libdbus-1-dev \
    nlohmann-json3-dev \
    git \
    nodejs \
    npm

# -------- 3. build native binaries --------------------------------------
step "Building bussie-service (C++ D-Bus service)"
make -C service clean >/dev/null 2>&1 || true
run make -C service

step "Building bussie-bridge (C++ native-messaging host)"
make -C bridge clean >/dev/null 2>&1 || true
run make -C bridge

# -------- 4. install binaries -------------------------------------------
step "Installing binaries to /usr/local"
install -m 0755 -D service/bussie-service /usr/local/sbin/bussie-service
install -m 0755 -D bridge/bussie-bridge   /usr/local/bin/bussie-bridge

# -------- 5. D-Bus policy + systemd unit --------------------------------
step "Installing D-Bus policy and systemd unit"
install -m 0644 -D service/config/org.bussie.Pwn.conf \
        /usr/share/dbus-1/system.d/org.bussie.Pwn.conf
install -m 0644 -D service/config/bussie.service \
        /etc/systemd/system/bussie.service

# -------- 6. native-messaging-host manifest (substitute extension ID) ---
step "Installing native-messaging-host manifest (extension ID: $EXTENSION_ID)"
NM_TMP="$(mktemp)"
sed "s/__EXTENSION_ID__/$EXTENSION_ID/g" \
    bridge/manifests/com.bussie.bridge.json.in > "$NM_TMP"
install -m 0644 -D "$NM_TMP" \
        /etc/opt/chrome/native-messaging-hosts/com.bussie.bridge.json
install -m 0644 -D "$NM_TMP" \
        /etc/chromium/native-messaging-hosts/com.bussie.bridge.json
rm -f "$NM_TMP"

# -------- 7. start the service ------------------------------------------
step "Reloading systemd and starting bussie.service"
run systemctl daemon-reload
run systemctl enable --now bussie.service
run bash -c 'systemctl reload dbus || systemctl restart dbus'

# -------- 8. build the Chrome extension ---------------------------------
step "Installing extension npm deps and building"
cd "$ATTACK_DIR/extension"
run npm ci --no-audit --no-fund
run npm run build
EXT_BUILD_DIR="$ATTACK_DIR/extension/build"

# -------- 9. summary ----------------------------------------------------
UNINSTALL_PATH="$(dirname "${SCRIPT_PATH:-$ATTACK_DIR/install.sh}")/uninstall.sh"

echo
c_green "================================================================="
c_green "  Bussie attack demo installed."
c_green "================================================================="
echo

# --- NEXT STEP — the one manual thing the user must do ------------------
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
echo "  The same unpacked build works for both Chrome and Chromium —"
echo "  the installer already dropped the native-messaging manifest"
echo "  for both browsers, so no further setup is needed."
echo

# --- background info, after the manual step -----------------------------
c_blue "Service status:"
systemctl --no-pager --lines=3 status bussie.service || true
echo
c_blue "Stage 1 demo (safe sandbox target):"
echo "  mkdir -p /tmp/bussie-demo-victim && touch /tmp/bussie-demo-victim/file1"
echo "  click the extension → type  /tmp/bussie-demo-victim  → Destroy"
echo
c_red  "Stage 2 demo (full blast — TAKE A VM SNAPSHOT FIRST):"
echo "  click the extension → type  /  → Destroy"
echo
c_blue "Mitigation (run between stages to show the fix):"
echo "  edit /usr/share/dbus-1/system.d/org.bussie.Pwn.conf"
echo "  delete the <policy context=\"default\"> block"
echo "  systemctl reload dbus"
echo "  the next Destroy call now fails with AccessDenied at the bus."
echo
c_blue "Uninstall (clean teardown when you're done):"
echo "  sudo bash $UNINSTALL_PATH"
echo
