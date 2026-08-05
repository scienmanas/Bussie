#!/bin/bash
# ─────────────────────────────────────────────────────────────
# build.sh — Install deps & build D-Bus service + caller
# ─────────────────────────────────────────────────────────────

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${RESET}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${RESET}    $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}  $1"; }
log_err()   { echo -e "${RED}[ERROR]${RESET} $1"; }
log_step()  { echo -e "\n${BOLD}── $1 ──${RESET}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"

# ─── Step 1: Detect distro & install dependencies ────────────
log_step "Step 1/4: Checking dependencies"

install_deps() {
    if command -v apt-get &>/dev/null; then
        log_info "Detected Debian/Ubuntu (apt)"
        sudo apt-get update -qq
        sudo apt-get install -y -qq g++ pkg-config libdbus-1-dev
    elif command -v dnf &>/dev/null; then
        log_info "Detected Fedora/RHEL (dnf)"
        sudo dnf install -y gcc-c++ pkg-config dbus-devel
    elif command -v pacman &>/dev/null; then
        log_info "Detected Arch Linux (pacman)"
        sudo pacman -Sy --noconfirm gcc pkgconf dbus
    elif command -v zypper &>/dev/null; then
        log_info "Detected openSUSE (zypper)"
        sudo zypper install -y gcc-c++ pkg-config dbus-1-devel
    else
        log_err "Unsupported package manager. Install manually: g++, pkg-config, libdbus-1-dev"
        exit 1
    fi
}

# Check if everything is already available
MISSING=0
command -v g++        &>/dev/null || { log_warn "g++ not found";        MISSING=1; }
command -v pkg-config &>/dev/null || { log_warn "pkg-config not found"; MISSING=1; }
pkg-config --exists dbus-1 2>/dev/null || { log_warn "libdbus-1-dev not found"; MISSING=1; }

if [ "$MISSING" -eq 1 ]; then
    log_info "Installing missing dependencies..."
    install_deps
    log_ok "Dependencies installed"
else
    log_ok "All dependencies already present"
fi

# ─── Step 2: Verify toolchain ────────────────────────────────
log_step "Step 2/4: Verifying toolchain"

GCC_VER=$(g++ --version | head -1)
# We use pkg-config to get the correct flags for compiling and linking against D-Bus
DBUS_CFLAGS=$(pkg-config --cflags dbus-1)
DBUS_LIBS=$(pkg-config --libs dbus-1)

log_info "Compiler:    $GCC_VER"
log_info "DBUS_CFLAGS: $DBUS_CFLAGS"
log_info "DBUS_LIBS:   $DBUS_LIBS"
log_ok "Toolchain ready"

# ─── Step 3: Create build directory ──────────────────────────
log_step "Step 3/4: Preparing build directory"

mkdir -p "$BUILD_DIR"
log_ok "Build directory: $BUILD_DIR"

# ─── Step 4: Compile ─────────────────────────────────────────
log_step "Step 4/4: Compiling"

log_info "Compiling service.cpp ..."
g++ -std=c++11 -Wall -Wextra -o "$BUILD_DIR/service.out" "$SCRIPT_DIR/service.cpp" $DBUS_CFLAGS $DBUS_LIBS
log_ok "Built: build/service.out"

log_info "Compiling caller.cpp ..."
g++ -std=c++11 -Wall -Wextra -o "$BUILD_DIR/caller.out" "$SCRIPT_DIR/caller.cpp" $DBUS_CFLAGS $DBUS_LIBS
log_ok "Built: build/caller.out"

log_info "Compiling generic.cpp ..."
g++ -std=c++11 -Wall -Wextra -o "$BUILD_DIR/generic.out" "$SCRIPT_DIR/generic.cpp" $DBUS_CFLAGS $DBUS_LIBS
log_ok "Built: build/generic.out"

# ─── Done ─────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Build complete!${RESET}"
echo ""
echo "  Run the service:"
echo "    ./build/service"
echo ""
echo "  In another terminal, call it:"
echo "    ./build/caller YourName"
echo ""
