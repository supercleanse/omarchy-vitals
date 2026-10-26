#!/bin/bash
#
# Render the Vitals UI offscreen from fixture data and save PNGs.
#
#   dev/render.sh --fake-data [--theme <name>] [--scale <n>] [--out <dir>]
#
# Runs a private Quickshell instance with QT_QPA_PLATFORM=offscreen, its own
# runtime directory and no Wayland, Hyprland or D-Bus connection, so nothing
# appears on (or talks to) the running desktop. Every number shown comes from
# dev/harness/fixtures.js; --fake-data is required to make that explicit.
#
# Without --theme it reads the active Omarchy theme. --theme <name> renders a
# first-party theme from $OMARCHY_PATH/themes (or ~/.config/omarchy/themes)
# through a scratch HOME instead, leaving the real theme untouched.

set -euo pipefail

fake=0 theme="" scale=2 out=""
while (( $# )); do
  case $1 in
    --fake-data) fake=1 ;;
    --theme) theme=${2:?}; shift ;;
    --scale) scale=${2:?}; shift ;;
    --out) out=${2:?}; shift ;;
    -h|--help) sed -n '3,16p' "$0"; exit 0 ;;
    *) echo "render.sh: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

(( fake )) || { echo "render.sh renders fixture data only; pass --fake-data" >&2; exit 2; }

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy=${OMARCHY_PATH:-/usr/share/omarchy}
shell_dir=$omarchy/shell
[[ -d $shell_dir/Commons ]] || { echo "render.sh: no Omarchy shell at $shell_dir" >&2; exit 1; }
out=${out:-$repo/dev/renders}
mkdir -p "$out"
out=$(cd "$out" && pwd)

work=$(mktemp -d "${TMPDIR:-/tmp}/vitals-render.XXXXXX")
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
  H.Harness { }
}
QML

render_home=$HOME
if [[ -n $theme ]]; then
  src=""
  for dir in "$HOME/.config/omarchy/themes/$theme" "$omarchy/themes/$theme"; do
    [[ -f $dir/colors.toml ]] && { src=$dir; break; }
  done
  [[ -n $src ]] || { echo "render.sh: theme '$theme' not found" >&2; exit 1; }
  render_home=$work/home
  mkdir -p "$render_home/.local/state/omarchy/current/theme"
  cp "$src"/colors.toml "$render_home/.local/state/omarchy/current/theme/"
  [[ -f $src/shell.toml ]] && cp "$src/shell.toml" "$render_home/.local/state/omarchy/current/theme/"
  tag=$theme
else
  tag=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || echo current)
fi

env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
  -u QT_QPA_PLATFORMTHEME -u QT_IM_MODULE -u GDK_BACKEND \
  HOME="$render_home" \
  XDG_CONFIG_HOME="$HOME/.config" \
  XDG_RUNTIME_DIR="$work/runtime" \
  QT_QPA_PLATFORM=offscreen \
  QT_QUICK_BACKEND=software \
  QT_SCALE_FACTOR="$scale" \
  QS_DISABLE_FILE_WATCHER=1 \
  QS_NO_RELOAD_POPUP=1 \
  VITALS_FAKE_DATA=1 \
  VITALS_OUT="$out" \
  VITALS_THEME_TAG="$tag" \
  timeout 60 qs -p "$work/config" 2>&1 | grep -v -e 'Failed to start IPC server' -e 'does not support setting window masks' || true

ls -1 "$out"/*-"$tag".png
