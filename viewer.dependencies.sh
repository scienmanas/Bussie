#!/usr/bin/env bash
# Install GUI D-Bus inspectors used while developing/debugging Bussie.
# Usage:  bash viewer.dependencies.sh
#
# Installs:
#   - bustle             GTK-based D-Bus message monitor / inspector
#   - qdbusviewer        Qt-based service/object/method browser
#                        (ships inside qttools5-dev-tools on newer Debian/Kali)

set -euo pipefail

echo "==> Installing D-Bus GUI inspectors (sudo required)"
sudo apt update
sudo apt install -y bustle qttools5-dev-tools

echo
echo "Done. Launch with:"
echo "  bustle           # record/inspect live D-Bus traffic"
echo "  qdbusviewer      # browse services, objects, methods"
