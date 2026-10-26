#!/bin/bash
#
# Load the real plugin offscreen and let it sample for a few seconds.
#
#   dev/load-check.sh <scratch-dir> [ssh-destination ...]
#
# Uses <scratch-dir> as HOME, so machines.json and state.json are created
# there (the first-run path) and nothing under your real ~/.config changes.
# Each ssh-destination is added as a remote machine; ssh still reads your
# real ~/.ssh. Prints the service summary and saves <scratch-dir>/live-view.png.
# Real host data ends up in that PNG, so keep it out of the repository.
# Like dev/render.sh, it never touches the running desktop.

set -euo pipefail

scratch=${1:?usage: dev/load-check.sh <scratch-dir> [ssh-destination ...]}
shift
mkdir -p "$scratch"
scratch=$(cd "$scratch" && pwd)
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
case $scratch in "$repo"*) echo "load-check.sh: keep the scratch dir outside the repo" >&2; exit 2 ;; esac
shell_dir=${OMARCHY_PATH:-/usr/share/omarchy}/shell

# A short path: the IPC socket lives under the runtime dir and Unix socket
# paths are limited to about 100 bytes.
work=$(mktemp -d /tmp/vl.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/config" "$work/runtime"
chmod 700 "$work/runtime"
ln -s "$shell_dir/Commons" "$work/config/Commons"
ln -s "$shell_dir/Ui" "$work/config/Ui"
ln -s "$repo" "$work/config/plugin"
cat > "$work/config/shell.qml" <<'QML'
import Quickshell
import "plugin/dev/harness" as H

ShellRoot {
  H.LoadCheck { }
}
QML

home=$scratch/home
mkdir -p "$home/.local/state/omarchy/current"
# Read the active theme in place so colors match the desktop.
ln -sfn "$HOME/.local/state/omarchy/current/theme" "$home/.local/state/omarchy/current/theme"

if (( $# )); then
  mkdir -p "$home/.config/vitals" "$home/.local/state/vitals"
  {
    printf '{ "version": 1, "machines": [ { "id": "local", "alias": "", "host": "", "enabled": true }'
    for dest in "$@"; do printf ', { "alias": "%s", "host": "%s" }' "$dest" "$dest"; done
    printf ' ] }\n'
  } > "$home/.config/vitals/machines.json"
  echo '{"open":true}' > "$home/.local/state/vitals/state.json"
fi

# Exercise the IPC target against this private instance (never the real
# shell: a different runtime dir and config path) partway through the run.
(
  sleep 7
  for call in status window close open toggle toggle edit refresh status; do
    printf 'ipc %s -> ' "$call"
    env -u WAYLAND_DISPLAY -u DISPLAY XDG_RUNTIME_DIR="$work/runtime" timeout 5 qs ipc -p "$work/config" call supercleanse.vitals "$call" 2>&1 | head -c 400
    echo
  done
) &
ipc_pid=$!

env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
  -u QT_QPA_PLATFORMTHEME -u QT_IM_MODULE -u GDK_BACKEND -u XDG_STATE_HOME \
  HOME="$home" \
  XDG_CONFIG_HOME="$home/.config" \
  XDG_RUNTIME_DIR="$work/runtime" \
  QT_QPA_PLATFORM=offscreen \
  QT_QUICK_BACKEND=software \
  QT_SCALE_FACTOR=2 \
  QS_DISABLE_FILE_WATCHER=1 \
  QS_NO_RELOAD_POPUP=1 \
  VITALS_OUT="$scratch" \
  VITALS_WAIT_MS="${VITALS_WAIT_MS:-14000}" \
  timeout 90 qs -p "$work/config" 2>&1 | grep -v -e 'Failed to start IPC server' -e 'does not support setting window masks' || true

wait "$ipc_pid" 2>/dev/null || true
echo "--- files written under the scratch HOME"
find "$home/.config/vitals" "$home/.local/state/vitals" -type f -print -exec cat {} \; 2>/dev/null || true
