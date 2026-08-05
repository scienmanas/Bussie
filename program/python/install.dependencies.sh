#!/usr/bin/env bash
# Install system + Python dependencies for the Bussie service.
# Usage:  bash program/python/install.dependencies.sh
#
# Installs:
#   - System libs needed to build PyGObject / pycairo (pydbus depends on these)
#   - uv (Python package manager) if missing
#   - A project-local .venv with pydbus + PyGObject

set -euo pipefail

# Gets the absolute path to the directory containing this script, even if called from another directory, pwd helps in printing the current working directory for debugging purposes.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

INSTALL_USER="${SUDO_USER:-${USER}}"
INSTALL_HOME="$(getent passwd "$INSTALL_USER" | cut -d: -f6)"
USER_UV="$INSTALL_HOME/.local/bin/uv"

echo "==> Installing system packages (sudo required)"
sudo apt update
sudo apt install -y \
    pkg-config \
    libcairo2-dev \
    libgirepository1.0-dev \
    libgirepository-2.0-dev \
    gir1.2-glib-2.0 \
    python3-dev \
    build-essential

if ! command -v uv >/dev/null 2>&1 && ! [[ -x "$USER_UV" ]]; then
    echo "==> uv not found, installing for user '$INSTALL_USER'"
    if [[ -n "${SUDO_USER:-}" ]]; then
        sudo -u "$SUDO_USER" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
    else
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi
    if ! command -v uv >/dev/null 2>&1 && ! [[ -x "$USER_UV" ]]; then
        echo "uv install failed. Add ~/.local/bin to PATH and re-run." >&2
        exit 1
    fi
fi
echo "==> uv $( [[ -x "$USER_UV" ]] && "$USER_UV" --version || uv --version )"

echo "==> Syncing virtual environment from uv.lock"
# `uv sync` creates .venv if missing and installs the exact versions from
# uv.lock (or resolves from pyproject.toml on first run if no lock exists).
if [[ -n "${SUDO_USER:-}" ]]; then
    sudo -u "$SUDO_USER" "$USER_UV" sync
else
    uv sync
fi

echo
echo "Done. Activate the venv with:  source .venv/bin/activate"
