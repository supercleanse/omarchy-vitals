#!/bin/bash
#
# Run the sampler for a few samples and check every line is valid JSON with
# the expected fields.
#
#   dev/test-sampler.sh                 # this machine
#   dev/test-sampler.sh <ssh-dest> ...  # also stream it to each destination
#
# Remote runs are read-only and end when this script stops reading.

set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
sampler=$repo/sampler/vitals-sampler.sh
samples=${SAMPLES:-3}
command -v jq >/dev/null || { echo "test-sampler.sh: jq is required" >&2; exit 1; }

check() {
  local name=$1; shift
  local out
  out=$(timeout 40 "$@" 2>&1 | head -n $((samples + 1)) || true)
  local hello
  hello=$(head -n1 <<<"$out")
  if ! jq -e '.type == "hello" and (.os | test("linux|macos")) and (.cores > 0)' <<<"$hello" >/dev/null 2>&1; then
    echo "not ok - $name: bad hello: $hello"; return 1
  fi
  local lines
  lines=$(tail -n +2 <<<"$out")
  if [[ $(wc -l <<<"$lines") -lt $samples ]] || ! jq -e -s 'all(.[]; .type == "sample" and .cpu >= 0 and .cpu <= 100 and .memTotal > 0 and .memUsed <= .memTotal and .rx >= 0 and .tx >= 0)' <<<"$lines" >/dev/null 2>&1; then
    echo "not ok - $name: bad samples:"; echo "$lines"; return 1
  fi
  echo "ok - $name: $(jq -r '"\(.os) \(.osName), \(.cores) cores"' <<<"$hello")"
  jq -r '"     cpu \(.cpu)%  mem \(.memUsed / .memTotal * 100 | floor)%  rx \(.rx) B/s  tx \(.tx) B/s"' <<<"$(tail -n1 <<<"$lines")"
}

status=0
check "local" sh "$sampler" 1 || status=1
for dest in "$@"; do
  check "$dest" sh -c 'f=$1; shift; exec ssh "$@" < "$f"' vitals-ssh "$sampler" \
    -T -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=10 -o ServerAliveCountMax=2 \
    -- "$dest" sh -s -- 1 || status=1
done
exit $status
