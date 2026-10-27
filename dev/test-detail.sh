#!/bin/bash
#
# Run the detail sampler on every tab and check each report has the shape
# OmaStats' pages read.
#
#   dev/test-detail.sh                 # this machine
#   dev/test-detail.sh <ssh-dest> ...  # also each destination (read-only)
#
# A tab the machine cannot report is checked only for the basics; nothing in
# it may be invented.

set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
detail=$repo/sampler/vitals-detail.sh
command -v jq >/dev/null || { echo "test-detail.sh: jq is required" >&2; exit 1; }

# What each tab must carry, as a jq test on one report.
declare -A want=(
  [cpu]='.cpu.user >= 0 and (.cpu.load | length) == 3 and .cpu.coreCount > 0 and (.procs.cpu | type) == "array"'
  [memory]='.mem.total > 0 and .mem.used <= .mem.total and (.procs.mem | type) == "array"'
  [disks]='(.disks.volumes | length) > 0 and .disks.read >= 0'
  [network]='(.net.ifaces | type) == "array" and (.net.procs | type) == "array"'
  [gpu]='(.gpus | type) == "array"'
  [sensors]='(.sensors == null) or ((.sensors.temps | type) == "array")'
  [battery]='(.battery == null) or (.battery.present == false) or (.battery.percent >= 0 and .battery.percent <= 100)'
)

run() {
  local name=$1 tab=$2; shift 2
  local line
  line=$(timeout 40 "$@" 2>/dev/null | head -n 1 || true)
  if ! jq -e --arg t "$tab" ".type == \"detail\" and .tab == \$t and .mem.total > 0 and (${want[$tab]})" <<<"$line" >/dev/null 2>&1; then
    echo "not ok - $name $tab: ${line:0:300}"; return 1
  fi
  echo "ok - $name $tab: $(jq -c '[.cpu.total, (.procs.total // empty), (.net.ifaces // [] | length), (.disks.volumes // [] | length), (.sensors.temps // [] | length), (.battery.percent // empty)] | map(tostring) | join(" ")' <<<"$line")"
}

status=0
for tab in cpu memory disks network gpu sensors battery; do
  run local "$tab" sh "$detail" 1 "$tab" || status=1
done
for dest in "$@"; do
  for tab in cpu memory disks network gpu sensors battery; do
    run "$dest" "$tab" sh -c 'f=$1; shift; exec ssh "$@" < "$f"' vitals-ssh "$detail" \
      -T -o BatchMode=yes -o ConnectTimeout=8 -- "$dest" sh -s -- 1 "$tab" - || status=1
  done
done
exit $status
