# Vitals sampler: a small POSIX sh loop that prints one JSON line per sample.
#
# Runs locally as `sh vitals-sampler.sh <interval>` and on remote machines as
# `ssh <dest> sh -s -- <interval>` with this file streamed on stdin, so nothing
# is installed on the remote side. Supports Linux and macOS.
#
# First line:   {"type":"hello","v":1,"os":"linux","osName":"...","host":"...","cores":8,"interval":2}
# Then, every interval:
#               {"type":"sample","cpu":12.3,"user":8.1,"sys":4.2,"memUsed":...,"memTotal":...,"rx":...,"tx":...,"load":0.42}
#
# cpu/user/sys are percentages of all cores. memUsed/memTotal are bytes, rx/tx
# are bytes per second summed over physical interfaces. On error it prints
# {"type":"error","message":"..."} and exits non-zero.
#
# Everything lives in functions and the last line runs `main` with stdin from
# /dev/null. The shell parses that whole line before running it, so no command
# can read the rest of the script off stdin when it arrives through `sh -s`.

vitals_json_text() {
  # Keep JSON strings safe: drop quotes, backslashes and control characters.
  printf '%s' "$1" | tr -d '"\\\000-\037' | cut -c1-80
}

vitals_emit() {
  printf '%s\n' "$1" || exit 0
}

vitals_fail() {
  vitals_emit "{\"type\":\"error\",\"message\":\"$(vitals_json_text "$1")\"}"
  exit 1
}

# Integer tenths to "12.3".
vitals_tenths() {
  vitals_t=$1
  [ "$vitals_t" -lt 0 ] && vitals_t=0
  printf '%d.%d' $((vitals_t / 10)) $((vitals_t % 10))
}

# ---------------------------------------------------------------- Linux

linux_cpu() {
  # First line of /proc/stat: cpu user nice system idle iowait irq softirq steal ...
  read -r _ c_user c_nice c_sys c_idle c_iow c_irq c_sirq c_steal _rest < /proc/stat
  c_iow=${c_iow:-0}; c_irq=${c_irq:-0}; c_sirq=${c_sirq:-0}; c_steal=${c_steal:-0}
  cpu_u=$((c_user + c_nice))
  cpu_s=$((c_sys + c_irq + c_sirq + c_steal))
  cpu_i=$((c_idle + c_iow))
}

linux_mem() {
  m_total=0; m_avail=-1; m_free=0; m_buf=0; m_cache=0
  while read -r m_key m_val _unit; do
    case $m_key in
      MemTotal:) m_total=$m_val ;;
      MemAvailable:) m_avail=$m_val ;;
      MemFree:) m_free=$m_val ;;
      Buffers:) m_buf=$m_val ;;
      Cached:) m_cache=$m_val ;;
    esac
  done < /proc/meminfo
  # Kernels before 3.14 have no MemAvailable.
  [ "$m_avail" -lt 0 ] && m_avail=$((m_free + m_buf + m_cache))
  mem_total=$((m_total * 1024))
  mem_used=$(((m_total - m_avail) * 1024))
}

# Physical interfaces have a device link in sysfs; bridges, veths, tunnels,
# Tailscale and Docker interfaces do not. When nothing qualifies (a container,
# say), fall back to every non-loopback interface.
linux_net() {
  n_rx=0; n_tx=0; n_any_rx=0; n_any_tx=0; n_phys=0
  while IFS= read -r n_line; do
    case $n_line in
      *:*) ;;
      *) continue ;;
    esac
    n_if=${n_line%%:*}
    n_if=${n_if##* }
    n_rest=${n_line#*:}
    [ "$n_if" = lo ] && continue
    # shellcheck disable=SC2086
    set -- $n_rest
    [ $# -ge 9 ] || continue
    n_any_rx=$((n_any_rx + $1)); n_any_tx=$((n_any_tx + $9))
    if [ -e "/sys/class/net/$n_if/device" ]; then
      n_rx=$((n_rx + $1)); n_tx=$((n_tx + $9)); n_phys=1
    fi
  done < /proc/net/dev
  if [ "$n_phys" -eq 0 ]; then n_rx=$n_any_rx; n_tx=$n_any_tx; fi
}

# /proc/uptime in centiseconds, for an exact elapsed time between samples.
linux_clock() {
  read -r u_up _ < /proc/uptime
  u_int=${u_up%%.*}
  u_frac=${u_up#*.}
  case $u_frac in ?) u_frac=${u_frac}0 ;; ??) ;; *) u_frac=$(printf '%.2s' "$u_frac") ;; esac
  # Strip a leading zero so the shell does not read it as octal.
  u_frac=${u_frac#0}
  clock_cs=$((u_int * 100 + ${u_frac:-0}))
}

linux_main() {
  [ -r /proc/stat ] && [ -r /proc/meminfo ] && [ -r /proc/net/dev ] || vitals_fail "/proc is not readable"
  host=$(uname -n 2>/dev/null)
  host=${host%%.*}
  os_name=Linux
  if [ -r /etc/os-release ]; then
    while IFS='=' read -r o_key o_val; do
      [ "$o_key" = PRETTY_NAME ] && { o_val=${o_val#\"}; os_name=${o_val%\"}; }
    done < /etc/os-release
  fi
  cores=0
  while read -r c_key _; do
    case $c_key in cpu[0-9]*) cores=$((cores + 1)) ;; esac
  done < /proc/stat
  vitals_emit "{\"type\":\"hello\",\"v\":1,\"os\":\"linux\",\"osName\":\"$(vitals_json_text "$os_name")\",\"host\":\"$(vitals_json_text "$host")\",\"cores\":$cores,\"interval\":$interval}"

  linux_cpu; p_u=$cpu_u; p_s=$cpu_s; p_i=$cpu_i
  linux_net; p_rx=$n_rx; p_tx=$n_tx
  linux_clock; p_clock=$clock_cs

  while :; do
    sleep "$interval" || exit 0
    linux_cpu
    linux_net
    linux_clock
    linux_mem
    d_u=$((cpu_u - p_u)); d_s=$((cpu_s - p_s)); d_i=$((cpu_i - p_i))
    d_t=$((d_u + d_s + d_i))
    [ "$d_t" -le 0 ] && d_t=1
    t_user=$((d_u * 1000 / d_t)); t_sys=$((d_s * 1000 / d_t))
    d_cs=$((clock_cs - p_clock))
    [ "$d_cs" -le 0 ] && d_cs=1
    d_rx=$((n_rx - p_rx)); d_tx=$((n_tx - p_tx))
    # Counters reset when an interface goes away; never report a negative rate.
    [ "$d_rx" -lt 0 ] && d_rx=0
    [ "$d_tx" -lt 0 ] && d_tx=0
    r_rx=$((d_rx * 100 / d_cs)); r_tx=$((d_tx * 100 / d_cs))
    read -r l_one _ < /proc/loadavg
    vitals_emit "{\"type\":\"sample\",\"cpu\":$(vitals_tenths $((t_user + t_sys))),\"user\":$(vitals_tenths $t_user),\"sys\":$(vitals_tenths $t_sys),\"memUsed\":$mem_used,\"memTotal\":$mem_total,\"rx\":$r_rx,\"tx\":$r_tx,\"load\":$l_one}"
    p_u=$cpu_u; p_s=$cpu_s; p_i=$cpu_i; p_rx=$n_rx; p_tx=$n_tx; p_clock=$clock_cs
  done
}

# ---------------------------------------------------------------- macOS

# One iostat run per sample doubles as the wait: it prints the since-boot line,
# waits the interval, then prints the interval's cpu split and load average.
# vm_stat and netstat follow it into a single awk, which prints
#   user sys idle load1 memUsed rxBytes txBytes
# Memory used matches Activity Monitor: app memory (anonymous pages minus
# purgeable) plus wired plus compressed. Network counts only en* interfaces at
# the link level, so Tailscale and other utun traffic is not counted twice.
darwin_sample() {
  {
    if [ "$1" = wait ]; then iostat -n0 -c 2 -w "$wait_s"; else echo; fi
    echo @VM
    vm_stat
    echo @NET
    netstat -ibn
  } 2>/dev/null | awk -v page="$page_size" '
    /^@VM/ { part = "vm"; next }
    /^@NET/ { part = "net"; next }
    part == "" && NF >= 3 && $1 ~ /^[0-9]+$/ { us = $1; sy = $2; id = $3; ld = (NF >= 4 ? $4 : 0) }
    part == "vm" {
      if ($0 ~ /page size of/) { for (i = 1; i <= NF; i++) if ($i == "of") page = $(i + 1) }
      v = $NF; gsub(/\./, "", v)
      if ($0 ~ /^Anonymous pages/) anon = v
      else if ($0 ~ /^Pages purgeable/) purge = v
      else if ($0 ~ /^Pages wired down/) wired = v
      else if ($0 ~ /^Pages occupied by compressor/) comp = v
    }
    part == "net" && $1 ~ /^en[0-9]+$/ && $3 ~ /^<Link/ { rx += $(NF - 4); tx += $(NF - 1) }
    END {
      app = anon - purge; if (app < 0) app = 0
      printf "%d %d %d %s %.0f %.0f %.0f\n", us, sy, id, (ld == "" ? 0 : ld), (app + wired + comp) * page, rx, tx
    }'
}

darwin_main() {
  command -v vm_stat >/dev/null 2>&1 && command -v iostat >/dev/null 2>&1 \
    && command -v netstat >/dev/null 2>&1 || vitals_fail "vm_stat, iostat or netstat missing"
  host=$(scutil --get LocalHostName 2>/dev/null || uname -n 2>/dev/null)
  host=${host%%.*}
  os_name="macOS $(sw_vers -productVersion 2>/dev/null)"
  # shellcheck disable=SC2046
  set -- $(sysctl -n hw.ncpu hw.memsize hw.pagesize 2>/dev/null)
  cores=${1:-0}; mem_total=${2:-0}; page_size=${3:-4096}
  # iostat waits in whole seconds.
  wait_s=${interval%%.*}
  [ -n "$wait_s" ] && [ "$wait_s" -ge 1 ] 2>/dev/null || wait_s=1
  vitals_emit "{\"type\":\"hello\",\"v\":1,\"os\":\"macos\",\"osName\":\"$(vitals_json_text "$os_name")\",\"host\":\"$(vitals_json_text "$host")\",\"cores\":$cores,\"interval\":$wait_s}"

  # shellcheck disable=SC2046
  set -- $(darwin_sample nowait)
  p_rx=${6:-0}; p_tx=${7:-0}
  while :; do
    # shellcheck disable=SC2046
    set -- $(darwin_sample wait)
    [ $# -eq 7 ] || { sleep "$wait_s"; continue; }
    d_rx=$(($6 - p_rx)); d_tx=$(($7 - p_tx))
    [ "$d_rx" -lt 0 ] && d_rx=0
    [ "$d_tx" -lt 0 ] && d_tx=0
    used=$5
    [ "$used" -gt "$mem_total" ] && used=$mem_total
    vitals_emit "{\"type\":\"sample\",\"cpu\":$(($1 + $2)),\"user\":$1,\"sys\":$2,\"memUsed\":$used,\"memTotal\":$mem_total,\"rx\":$((d_rx / wait_s)),\"tx\":$((d_tx / wait_s)),\"load\":$4}"
    p_rx=$6; p_tx=$7
  done
}

main() {
  interval=${1:-2}
  case $interval in
    ''|*[!0-9.]*|.*|*.*.*) interval=2 ;;
  esac
  export LC_ALL=C
  case $(uname -s 2>/dev/null) in
    Linux) linux_main ;;
    Darwin) darwin_main ;;
    *) vitals_fail "unsupported system: $(uname -s 2>/dev/null)" ;;
  esac
}

main "$@" < /dev/null; exit
