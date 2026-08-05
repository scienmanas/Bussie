#!/usr/bin/env bash
# Bussie attack demo — build the Chrome extension standalone.
#
# Same "install deps + build" step that install.sh / dev.install.sh run as
# part of a full system install, pulled out on its own for when you just
# want to compile the extension — no root, no D-Bus policy, no systemd unit.
#
# Usage:
#   bash attack/extension/build.sh            # npm ci/install + npm run build
#   bash attack/extension/build.sh --clean    # wipe node_modules/build first
#
# Output lands in extension/build/ — load it via chrome://extensions →
# Developer mode → Load unpacked.

set -euo pipefail

c_red()   { printf "\033[31m%s\033[0m\n" "$*"; }
c_green() { printf "\033[32m%s\033[0m\n" "$*"; }
c_blue()  { printf "\033[34m%s\033[0m\n" "$*"; }
step()    { c_blue "==> $*"; }

EXTENSION_ID="bmcdglmldgcgdlodlkdimbpofnpcmijn"

CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN=1 ;;
        *)
            c_red "Unknown option: $arg"
            c_red "Usage: bash build.sh [--clean]"
            exit 1
            ;;
    esac
done

# -------- 0. locate the extension dir ------------------------------------
SCRIPT_PATH=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
fi
if [[ -z "$SCRIPT_PATH" ]]; then
    c_red "Cannot determine script path. Run with:"
    c_red "    bash attack/extension/build.sh"
    exit 1
fi
EXT_DIR="$(dirname "$SCRIPT_PATH")"
cd "$EXT_DIR"
step "Building extension in $EXT_DIR"

# -------- 1. sanity-check tooling -----------------------------------------
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    c_red "node/npm not found on PATH."
    c_red "Install Node.js (e.g. 'sudo apt-get install nodejs npm') and re-run."
    exit 1
fi
step "Using $(node --version) / npm $(npm --version)"

# -------- 2. clean, if asked ----------------------------------------------
if [[ "$CLEAN" -eq 1 ]]; then
    step "Cleaning node_modules/, build/, dev_build/"
    rm -rf node_modules build dev_build
fi

# -------- 3. install dependencies -----------------------------------------
if [[ ! -d node_modules ]]; then
    if [[ -f package-lock.json ]]; then
        step "Installing dependencies (npm ci)"
        npm ci --no-audit --no-fund
    else
        step "Installing dependencies (npm install)"
        npm install --no-audit --no-fund
    fi
else
    step "node_modules already present — skipping install"
    step "  (pass --clean to force a fresh install)"
fi

# -------- 4. build ----------------------------------------------------
step "Running production build"
npm run build
BUILD_DIR="$EXT_DIR/build"

# -------- 5. summary ----------------------------------------------------
echo
c_green "================================================================="
c_green "  Extension build complete."
c_green "================================================================="
echo
echo "  Output:       $BUILD_DIR"
echo "  Expected ID:  $EXTENSION_ID"
echo
echo "  Load it: chrome://extensions → Developer mode → Load unpacked →"
echo "  select the folder above, then confirm the loaded ID matches."
echo
