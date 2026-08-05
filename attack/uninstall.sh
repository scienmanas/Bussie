#!/usr/bin/env bash
# Bussie attack demo — teardown.
#
# Reverses everything attack/install.sh did:
#   - stops and disables the systemd unit
#   - removes the service binary, bridge binary, D-Bus policy,
#     systemd unit, and both Chrome/Chromium native-messaging manifests
#   - reloads dbus so it drops the now-deleted policy
#
# Idempotent. Re-runs against a partially-installed system are fine —
# every removal is `rm -f`, every systemctl call is wrapped in `|| true`.
#
# What this script does NOT do (and why):
#   - It does not uninstall the Chrome/Chromium extension. Browsers reject
#     external removal of developer-loaded extensions; the user must open
#     chrome://extensions and click Remove.
#   - It does not delete /opt/bussie/. If you curl-installed, this script
#     usually lives *inside* /opt/bussie/attack/, and removing the repo
#     mid-run would delete the script. Run `sudo rm -rf /opt/bussie`
#     yourself once this script finishes if you want the clone gone too.

set -euo pipefail

c_red()   { printf "\033[31m%s\033[0m\n" "$*"; }
c_green() { printf "\033[32m%s\033[0m\n" "$*"; }
c_blue()  { printf "\033[34m%s\033[0m\n" "$*"; }
step()    { c_blue "==> $*"; }

# -------- 0. require root ------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    step "Re-executing under sudo"
    exec sudo -E bash "${BASH_SOURCE[0]:-$0}" "$@"
fi

# -------- 1. stop + disable the service ----------------------------------
step "Stopping and disabling bussie.service (if present)"
systemctl disable --now bussie.service 2>/dev/null || true

# -------- 2. remove installed files --------------------------------------
step "Removing installed files"
rm -f /usr/local/sbin/bussie-service
rm -f /usr/local/bin/bussie-bridge
rm -f /usr/share/dbus-1/system.d/org.bussie.Pwn.conf
rm -f /etc/systemd/system/bussie.service
rm -f /etc/opt/chrome/native-messaging-hosts/com.bussie.bridge.json
rm -f /etc/chromium/native-messaging-hosts/com.bussie.bridge.json

# -------- 3. reload state -----------------------------------------------
step "Reloading systemd and dbus"
systemctl daemon-reload || true
systemctl reload dbus 2>/dev/null || systemctl restart dbus || true

# -------- 4. summary ----------------------------------------------------
echo
c_green "================================================================="
c_green "  Bussie attack demo uninstalled."
c_green "================================================================="
echo
c_blue "Two manual follow-ups (the script can't do these for you):"
echo
echo "  1. Remove the Chrome / Chromium extension"
echo "     chrome://extensions → click Remove on the Bussie entry."
echo "     Browsers refuse external removal of dev-loaded extensions,"
echo "     so this has to be a user click."
echo
echo "  2. (Curl-install only) drop the repo clone:"
echo "     sudo rm -rf /opt/bussie"
echo "     Skipped automatically because this script may live inside"
echo "     that directory and would otherwise delete itself mid-run."
echo
