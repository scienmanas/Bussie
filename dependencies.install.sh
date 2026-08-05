#!/usr/bin/env bash
# dependencies.install — top-level dependency installer for the Bussie project.
#
# Installs every apt package needed to:
#   - run / build the Python service & caller         (Part 1, program/python/)
#   - build the C++ service & caller                  (Part 2, program/cpp/)
#   - build the attack demo (service + bridge + ext)  (Part 3, attack/)
#   - inspect D-Bus traffic with GUI tools            (bustle, qdbusviewer)
#
# Idempotent. Re-runs are cheap — already-installed packages are skipped,
# and apt-get update only runs when something actually needs installing.
# Distro support: apt only (Debian / Ubuntu / Kali).
#
# Usage:
#   bash dependencies.install            # re-execs under sudo if needed
#   sudo bash dependencies.install       # equivalent

set -euo pipefail

# ---------------------------------------------------------------- groups
CORE_PKGS=(
    build-essential
    pkg-config
    git
    curl
)

# Part 1 — Python (program/python/). PyGObject's native build needs these
# headers; pydbus is pulled in via uv from pyproject.toml.
PYTHON_PKGS=(
    python3
    python3-dev
    libcairo2-dev
    libgirepository-2.0-dev
    libgirepository1.0-dev
    gobject-introspection
    gir1.2-glib-2.0
    meson
    ninja-build
)

# Part 2 — raw libdbus C++ (program/cpp/).
CPP_PKGS=(
    libdbus-1-dev
)

# Part 3 — attack/. Bridge uses nlohmann/json for native-messaging frames.
# Extension is built with webpack via nodejs/npm.
ATTACK_PKGS=(
    nlohmann-json3-dev
    nodejs
    npm
)

# D-Bus inspectors (CLI tools busctl / dbus-monitor / gdbus are in dbus &
# libglib2.0-bin and ship by default; only the GUI tools need extras).
# Note: d-feet used to live here but upstream archived it in 2022 and Debian
# removed it from the archive in 2023, so `apt install d-feet` now fails.
# bustle (message timeline) + qdbusviewer (tree browser) cover the same
# ground.
VIEWER_PKGS=(
    bustle
    qttools5-dev-tools
)

# @ is used for correct expansion when [*]. is used it expands the array into separate words, while [@] expands into a single word.
ALL_PKGS=(
    "${CORE_PKGS[@]}"
    "${PYTHON_PKGS[@]}"
    "${CPP_PKGS[@]}"
    "${ATTACK_PKGS[@]}"
    "${VIEWER_PKGS[@]}"
)

# ---------------------------------------------------------------- colors
# Is this std out a terminal ? if yes enable colors, 1 is stdout file descriptor and -t tells if it's a terminal, -t stands to TTY, this syntax build already in bash, it asks stdout is it a terminal?, 1 is passes, u can say to understand
if [[ -t 1 ]]; then  
    BOLD=$'\033[1m'; GREEN=$'\033[32m'; BLUE=$'\033[34m'
    YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
    BOLD=; GREEN=; BLUE=; YELLOW=; RED=; RESET=
fi

step() { printf "%s==>%s %s\n"  "$BLUE"  "$RESET" "$*"; }
ok()   { printf "%s[ok]%s %s\n" "$GREEN" "$RESET" "$*"; }
warn() { printf "%s[warn]%s %s\n" "$YELLOW" "$RESET" "$*"; }
fail() { printf "%s[err]%s %s\n"  "$RED"    "$RESET" "$*" >&2; }

# ---------------------------------------------------------------- sanity
if ! command -v apt-get >/dev/null 2>&1; then
    fail "This installer only supports apt-based distros (Debian / Ubuntu / Kali)."
    fail "Install the equivalents manually:"
    fail "  ${ALL_PKGS[*]}"
    exit 1
fi

# ------------------------------------------------------- find missing pkgs
step "Checking installed apt packages…"

MISSING=()
for pkg in "${ALL_PKGS[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        MISSING+=("$pkg")
    fi
done

# ------------------------------------------------------- install if needed
if [[ ${#MISSING[@]} -eq 0 ]]; then
    ok "All apt dependencies already installed."
else
    step "Will install ${#MISSING[@]} package(s): ${MISSING[*]}"
    if [[ $EUID -ne 0 ]]; then
        step "Re-executing under sudo"
        exec sudo -E bash "${BASH_SOURCE[0]:-$0}" "$@"
    fi
    apt-get update -qq
    apt-get install -y --no-install-recommends "${MISSING[@]}"
    ok "Apt dependencies installed."
fi

# --------------------------------------------------------------------- uv
# uv (Python package manager) is needed for Part 1 (program/python/). Not
# an apt package on most distros; install via Astral's script as the
# invoking user, so the binary lands in their ~/.local/bin and not root's.

# Use sudo user if available otherwise switch to default user. This is important because if the script is run with sudo, we want to install uv for the original user, not root.
INSTALL_USER="${SUDO_USER:-${USER}}"
INSTALL_HOME="$(getent passwd "$INSTALL_USER" | cut -d: -f6)". # Extract the home directory of the user from /etc/passwd
USER_UV="$INSTALL_HOME/.local/bin/uv"

if command -v uv >/dev/null 2>&1 || [[ -x "$USER_UV" ]]; then
    ok "uv is installed (Python package manager)."
else
    step "Installing uv for user '$INSTALL_USER'"
    if [[ -n "${SUDO_USER:-}" ]]; then
        sudo -u "$SUDO_USER" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
    else
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
    ok "uv installed."
fi

# ----------------------------------------------------------------- summary
echo
echo "${BOLD}Installed package groups${RESET}"
printf "  ${GREEN}Core${RESET}         %s\n" "${CORE_PKGS[*]}"
printf "  ${GREEN}Part 1 Python${RESET} %s\n" "${PYTHON_PKGS[*]}"
printf "  ${GREEN}Part 2 C++${RESET}    %s\n" "${CPP_PKGS[*]}"
printf "  ${GREEN}Part 3 attack${RESET} %s\n" "${ATTACK_PKGS[*]}"
printf "  ${GREEN}Bus viewers${RESET}   %s\n" "${VIEWER_PKGS[*]}"

echo
echo "${BOLD}Next steps${RESET}"
echo "  Part 1 (Python venv): bash program/python/install.dependencies.sh"
echo "  Part 2 (C++ build):   bash program/cpp/build.sh"
echo "  Part 3 (attack demo): sudo bash attack/install.sh   # VM ONLY — destructive"

echo
echo "${BOLD}Inspectors${RESET}"
echo "  busctl --user list                  # services on session bus"
echo "  busctl --system list                # services on system bus"
echo "  dbus-monitor --session              # live trace, session"
echo "  bustle                              # GTK message timeline"
echo "  qdbusviewer                         # Qt service browser"
