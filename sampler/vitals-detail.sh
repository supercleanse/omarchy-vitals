# Vitals detail sampler: the data behind one detail panel tab.
#
#   sh vitals-detail.sh <interval> <tab> [all]
#
# Runs only while a detail panel is open for a machine: locally under sh, on
# remote machines as `ssh <dest> sh -s -- ...` with this file on stdin, so
# nothing is installed there. Linux and macOS, never root.
#
# Each line is one JSON object in the snapshot shape OmaStats' panel pages
# read (cpu, mem, net, disks, gpus, sensors, battery, procs), filled in for
# the visible tab only: cpu, gpu, memory, disks, network, sensors or
# battery. CPU, memory and network totals ride along on every tab so the
# history graphs keep moving. `all` adds the full process list (the panel's
# expanded process view). Anything a machine does not report without root is
# left out, never guessed.
#
# Each sample gathers raw text in marked sections and one awk turns it into
# JSON. Counters from the previous sample travel as a "@STATE" line awk
# prints first, so there are no temporary files.
#
# Like the card sampler, everything lives in functions and the last line runs
# `main` with stdin from /dev/null, so nothing reads the script off stdin.

vd_emit() {
  printf '%s\n' "$1" || exit 0
}

# A loop ends itself after a while and asks to be restarted, so one whose
# reader vanished without closing the connection (it happens behind some
# SSH proxies) cannot run on forever. Vitals reconnects at once.
vd_lifetime() {
  vd_age=$((vd_age + ${1%%.*} + 0))
  if [ "$vd_age" -ge 900 ]; then vd_emit '{"type":"renew"}'; exit 0; fi
}

vd_read() {
  val=""
  [ -r "$1" ] || return 1
  read -r val 2>/dev/null < "$1" || [ -n "$val" ]
}

vd_asleep() {
  vd_read "$1/power/runtime_status" && [ "$val" = suspended ]
}

# ---------------------------------------------------------------- Linux

linux_disk_of() {
  do_dev=$(readlink -f "$1" 2>/dev/null)
  do_name=${do_dev##*/}
  do_hops=0
  while [ "$do_hops" -lt 4 ]; do
    do_hops=$((do_hops + 1))
    [ -e "/sys/block/$do_name/device" ] && { printf '%s' "$do_name"; return; }
    if [ -d "/sys/block/$do_name/slaves" ]; then
      for do_slave in "/sys/block/$do_name/slaves"/*; do do_name=${do_slave##*/}; break; done
      continue
    fi
    if [ -e "/sys/class/block/$do_name/partition" ]; then
      do_parent=$(readlink -f "/sys/class/block/$do_name/.." 2>/dev/null)
      do_name=${do_parent##*/}
      continue
    fi
    break
  done
}

# Mounted local volumes with the whole disk under each:
#   device mount fstype sizeK usedK availK disk
linux_volumes() {
  lv_seen=" "
  df -kPT 2>/dev/null | while read -r lv_src lv_type lv_size lv_used lv_avail _ lv_mount; do
    case $lv_src in /dev/loop*) continue ;; /dev/*) ;; *) continue ;; esac
    case $lv_seen in *" $lv_src "*) continue ;; esac
    lv_seen="$lv_seen$lv_src "
    printf '%s %s %s %s %s %s %s\n' "$lv_src" "$lv_mount" "$lv_type" "$lv_size" "$lv_used" "$lv_avail" "$(linux_disk_of "$lv_src")"
  done
}

# What each whole disk is: name model rotational removable
linux_disk_info() {
  for di in /sys/block/*; do
    dn=${di##*/}
    case $dn in loop*|ram*|zram*|dm-*|sr*|fd*|nbd*) continue ;; esac
    [ -e "$di/device" ] || continue
    dm=""; vd_read "$di/device/model" && dm=$val
    dr=0; vd_read "$di/queue/rotational" && dr=$val
    dv=0; vd_read "$di/removable" && dv=$val
    printf '%s|%s|%s|%s\n' "$dn" "$(printf '%s' "$dm" | tr -d '"\\|' | sed 's/  *$//')" "$dr" "$dv"
  done
}

# Every hwmon file the sensors tab reads, skipping devices that runtime power
# management has put to sleep (reading them would wake them).
linux_hwmon_files() {
  for h in /sys/class/hwmon/hwmon*; do
    [ -e "$h/device" ] && vd_asleep "$h/device" && continue
    printf '%s\n' "$h/name"
    for f in "$h"/temp*_input "$h"/temp*_label "$h"/temp*_crit "$h"/temp*_max "$h"/fan*_input "$h"/fan*_label; do
      [ -e "$f" ] && printf '%s\n' "$f"
    done
  done
}

linux_gpus() {
  g_out=""
  nvsmi=$(command -v nvidia-smi 2>/dev/null)
  nv_lines=""
  for g_card in /sys/class/drm/card[0-9]*; do
    case ${g_card##*/} in *-*) continue ;; esac
    g_dev=$g_card/device
    vd_read "$g_dev/vendor" || continue
    case $val in
      0x1002) g_kind=amd; g_name="AMD GPU" ;;
      0x10de) g_kind=nvidia; g_name="NVIDIA GPU" ;;
      0x8086) g_kind=intel; g_name="Intel GPU" ;;
      *) continue ;;
    esac
    g_id=$(readlink -f "$g_dev" 2>/dev/null); g_id=${g_id##*/}
    g_util=null; g_mhz=null; g_max=null; g_temp=null; g_mu=null; g_mt=null; g_pw=null; g_fan=null
    g_int=false
    [ "$g_kind" = intel ] && g_int=true
    if vd_asleep "$g_dev"; then
      g_util=0
    else
      case $g_kind in
        amd)
          vd_read "$g_dev/gpu_busy_percent" && g_util=$val
          vd_read "$g_dev/mem_info_vram_used" && g_mu=$val
          vd_read "$g_dev/mem_info_vram_total" && g_mt=$val
          for g_h in "$g_dev"/hwmon/hwmon*; do
            vd_read "$g_h/temp1_input" && g_temp=$((val / 1000))
            vd_read "$g_h/freq1_input" && g_mhz=$((val / 1000000))
            vd_read "$g_h/power1_average" && g_pw=$((val / 1000000))
            vd_read "$g_h/fan1_input" && g_fan=$val
            break
          done
          ;;
        intel)
          if vd_read "$g_card/gt_act_freq_mhz"; then g_mhz=$val; vd_read "$g_card/gt_max_freq_mhz" && g_max=$val
          elif vd_read "$g_dev/tile0/gt0/freq0/act_freq"; then g_mhz=$val; vd_read "$g_dev/tile0/gt0/freq0/max_freq" && g_max=$val
          fi
          ;;
        nvidia)
          if [ -n "$nvsmi" ]; then
            [ -n "$nv_lines" ] || nv_lines=$("$nvsmi" --query-gpu=pci.bus_id,utilization.gpu,memory.used,memory.total,temperature.gpu,clocks.gr,clocks.max.gr,power.draw,fan.speed,name --format=csv,noheader,nounits 2>/dev/null)
            g_bus=$(printf '%s' "$g_id" | tr 'a-f' 'A-F')
            g_line=$(printf '%s\n' "$nv_lines" | grep -i "$g_bus" | head -n 1)
            if [ -n "$g_line" ]; then
              IFS=',' read -r _ g_util g_mu g_mt g_temp g_mhz g_max g_pw g_fan g_nm <<EOF
$g_line
EOF
              g_name=$(printf '%s' "$g_nm" | tr -d '"\\' | sed 's/^ *//')
              for v in g_util g_mu g_mt g_temp g_mhz g_max g_pw g_fan; do
                eval "x=\$$v"; x=$(printf '%s' "$x" | tr -d ' ')
                case $x in ''|*[!0-9.]*) x=null ;; esac
                eval "$v=\$x"
              done
              [ "$g_mu" != null ] && g_mu=$(awk -v m="$g_mu" 'BEGIN { printf "%.0f", m * 1048576 }')
              [ "$g_mt" != null ] && g_mt=$(awk -v m="$g_mt" 'BEGIN { printf "%.0f", m * 1048576 }')
            fi
          fi
          ;;
      esac
    fi
    g_out="$g_out${g_out:+,}{\"id\":\"$g_id\",\"name\":\"$g_name\",\"vendor\":\"$g_kind\",\"integrated\":$g_int,\"util\":$g_util,\"mhz\":$g_mhz,\"maxMhz\":$g_max,\"temp\":$g_temp,\"power\":$g_pw,\"fan\":$g_fan,\"memUsed\":$g_mu,\"memTotal\":$g_mt}"
  done
  gpus_json="[$g_out]"
}

# The Linux sample as OmaStats' snapshot JSON. Sections arrive marked "@NAME";
# counters from the last sample come in `prev` as key=value pairs.
linux_awk() {
  cat <<'AWK'
function psiavg(s,  a) { split(s, a, "="); return a[2] + 0 }
function js(s) { gsub(/["\\]/, "", s); gsub(/[\001-\037]/, "", s); return "\"" s "\"" }
function num(v) { return (v == "" ? "null" : v) }
function f1(v) { return sprintf("%.1f", v) }
function rate(cur, key,   q) { if (!(key in P) || dt <= 0) return 0; q = cur - P[key]; return q > 0 ? q / dt : 0 }
function friendly(name) {
  if (name ~ /^(k10temp|zenpower|coretemp)$/) return "CPU"
  if (name ~ /^(amdgpu|nouveau|radeon)$/) return "GPU"
  if (name == "nvme") return "NVMe"
  if (name ~ /^(iwlwifi|ath|mt7)/) return "Wi-Fi"
  if (name == "acpitz") return "ACPI"
  if (name ~ /^BAT/) return "Battery"
  if (name ~ /^dell_/) return "Dell"
  if (name == "thinkpad") return "ThinkPad"
  return name
}
# Keep the n largest of key k in group arrays, as a JSON list.
function toplist(k, n,   out, used, i, j, best, bv, v, cnt) {
  out = ""; cnt = 0
  for (i = 0; i < n; i++) {
    best = ""; bv = -1
    for (j in GCOUNT) {
      if (j in used) continue
      v = (k == "cpu" ? GCPU[j] : (k == "mem" ? GMEM[j] : GIO[j]))
      if (v > bv) { bv = v; best = j }
    }
    if (best == "") break
    used[best] = 1
    if (k == "io" && bv <= 0) break
    out = out (cnt++ ? "," : "") procjson(best)
  }
  return "[" out "]"
}
function procjson(g) {
  return "{\"name\":" js(g) ",\"pid\":" GPID[g] ",\"count\":" GCOUNT[g] ",\"cpu\":" f1(GCPU[g]) ",\"mem\":" sprintf("%.0f", GMEM[g]) ",\"read\":" sprintf("%.0f", GREAD[g]) ",\"write\":" sprintf("%.0f", GWRITE[g]) "}"
}
BEGIN {
  n = split(prev, kv, " ")
  for (i = 1; i <= n; i++) { p = index(kv[i], "="); if (p) P[substr(kv[i], 1, p - 1)] = substr(kv[i], p + 1) }
  t = up + 0
  dt = ("t" in P) ? t - P["t"] : 0
  # Keep the hundredths: awk's default number format would round uptime to
  # six digits and throw the sample length off by up to a second.
  S = "t=" sprintf("%.2f", t)
  split(cpus, cs, "|")
  ncore = 0
}
/^@/ { sec = substr($0, 2); next }
sec == "STAT" && /^cpu/ {
  bu = $2 + $3; bs = $4 + $7 + $8 + $9; id = $5 + $6; io = $6; tot = bu + bs + id
  key = "c" $1
  du = 0; ds = 0; dtot = 0; dio = 0
  if (key in P) { split(P[key], q, ","); du = bu - q[1]; ds = bs - q[2]; dtot = tot - q[3]; dio = io - q[4] }
  S = S " " key "=" bu "," bs "," tot "," io
  if ($1 == "cpu") { cu = dtot > 0 ? du * 100 / dtot : 0; csy = dtot > 0 ? ds * 100 / dtot : 0; cio = dtot > 0 ? dio * 100 / dtot : 0 }
  else core[ncore++] = dtot > 0 ? (du + ds) * 100 / dtot : 0
  next
}
sec == "MEM" { k = $1; sub(/:$/, "", k); M[k] = $2 * 1024; next }
sec == "NET" && index($0, ":") {
  nm = substr($0, 1, index($0, ":") - 1); gsub(/ /, "", nm)
  if (nm == "lo") next
  split(substr($0, index($0, ":") + 1), f, " ")
  NRX[nm] = f[1]; NTX[nm] = f[9]; netorder[++nnet] = nm
  next
}
sec == "SYSNET" { NUP[$1] = ($2 == "up"); NSPEED[$1] = $3; NWL[$1] = $4; NDEV[$1] = $5; next }
sec == "LOAD" { l1 = $1; l2 = $2; l3 = $3; next }
sec == "PSIMEM" { if ($1 == "some") pms = psiavg($2); if ($1 == "full") pmf = psiavg($2); next }
sec == "PSIIO" { if ($1 == "some") pis = psiavg($2); if ($1 == "full") pif = psiavg($2); hasio = 1; next }
sec == "ZRAM" { zorig += $1; zcomp += $2; next }
sec == "FREQ" { if ($1 > 0) { fsum += $1; fn++ }; next }
sec == "CPUT" { if ($1 ~ /^-?[0-9]+$/) ctemp = $1 / 1000; next }
sec == "PROC" {
  o = index($0, " ("); c = 0
  for (i = length($0); i > o; i--) if (substr($0, i, 1) == ")") { c = i; break }
  if (!o || !c) next
  pid = substr($0, 1, o - 1); comm = substr($0, o + 2, c - o - 2)
  m = split(substr($0, c + 2), r, " ")
  ticks = r[12] + r[13]; rss = r[22] * page
  key = "p" pid; S = S " " key "=" ticks
  pc = (key in P && dt > 0) ? (ticks - P[key]) * 100 / (clk * dt) : 0
  if (pc < 0) pc = 0
  GCPU[comm] += pc; GMEM[comm] += rss; GCOUNT[comm]++
  if (!(comm in GTOP) || pc >= GTOP[comm]) { GTOP[comm] = pc; GPID[comm] = pid }
  next
}
sec == "DINFO" && NF { split($0, d, "|"); DMODEL[d[1]] = d[2]; DROT[d[1]] = d[3]; DREM[d[1]] = d[4]; isdisk[d[1]] = 1; next }
sec == "DISK" {
  nm = $3
  if (!(nm in isdisk)) next
  key = "d" nm
  rd = $6 * 512; wr = $10 * 512; tk = $13
  if (key in P && dt > 0) { split(P[key], q, ","); DR[nm] = (rd - q[1]) / dt; DW[nm] = (wr - q[2]) / dt; DB[nm] = (tk - q[3]) / (dt * 10) }
  else { DR[nm] = 0; DW[nm] = 0; DB[nm] = 0 }
  if (DR[nm] < 0) DR[nm] = 0; if (DW[nm] < 0) DW[nm] = 0; if (DB[nm] > 100) DB[nm] = 100
  S = S " " key "=" rd "," wr "," tk
  diskorder[++ndisk] = nm
  next
}
sec == "VOLS" && NF >= 6 { vols[++nvol] = $0; next }
sec == "PIO" {
  split($0, a, "/"); pid = a[3]
  iov = $2 + 0
  if ($0 ~ /read_bytes/) PRD[pid] = iov; else PWR[pid] = iov
  next
}
sec == "PCOMM" { split($0, a, "/"); pid = a[3]; c = substr($0, index($0, "comm:") + 5); PCN[pid] = c; next }
sec == "ROUTE" && $2 == "00000000" { defif = $1; next }
sec == "WIFI" && index($1, ":") { w = $1; sub(/:$/, "", w); d = $4; sub(/\.$/, "", d); WDBM[w] = d + 0; next }
sec == "ADDR" && NF >= 3 {
  if ($2 == "inet") V4[$1] = V4[$1] (V4[$1] == "" ? "" : ",") js($3)
  else if ($2 == "inet6" && $3 !~ /^fe80/) V6[$1] = V6[$1] (V6[$1] == "" ? "" : ",") js($3)
  next
}
sec == "SSID" && NF >= 2 { w = $1; $1 = ""; sub(/^ /, ""); SSID[w] = $0; next }
sec == "SS" {
  if (match($0, /users:\(\("[^"]*",pid=[0-9]+/)) {
    u = substr($0, RSTART + 9, RLENGTH - 9)
    sname = substr(u, 1, index(u, "\"") - 1)
    spid = u; sub(/.*pid=/, "", spid)
    SCONN[sname]++; SPID[sname] = spid; cur = sname
    next
  }
  if (cur != "" && $0 ~ /bytes_/) {
    if (match($0, /bytes_acked:[0-9]+/)) STX[cur] += substr($0, RSTART + 12, RLENGTH - 12)
    if (match($0, /bytes_received:[0-9]+/)) SRX[cur] += substr($0, RSTART + 15, RLENGTH - 15)
    cur = ""
  }
  next
}
sec == "HW" {
  p = index($0, ":"); path = substr($0, 1, p - 1); val = substr($0, p + 1)
  nparts = split(path, a, "/"); dir = a[5]; file = a[6]
  if (file == "name") { HNAME[dir] = val; hdirs[++nh] = dir; next }
  base = file; sub(/_.*/, "", base); attr = file; sub(/^[^_]*_/, "", attr)
  HK[dir SUBSEP base] = 1
  if (attr == "input") HIN[dir SUBSEP base] = val
  else if (attr == "label") HLAB[dir SUBSEP base] = val
  else if (attr == "crit" && !((dir SUBSEP base) in HMAX)) HMAX[dir SUBSEP base] = val
  else if (attr == "max") HMAX[dir SUBSEP base] = val
  next
}
sec == "BAT" { p = index($0, ":"); path = substr($0, 1, p - 1); val = substr($0, p + 1); sub(/.*\//, "", path); B[path] = val; next }
sec == "AC" { if ($1 == "1") acon = 1; hasac = 1; next }
sec == "PERIPH" {
  p = index($0, ":"); path = substr($0, 1, p - 1); val = substr($0, p + 1)
  n2 = split(path, a, "/"); dev = a[5]; attr = a[6]
  if (!(dev in PH)) { PH[dev] = 1; porder[++np] = dev }
  PV[dev SUBSEP attr] = val
  next
}
END {
  out = "{\"type\":\"detail\",\"tab\":\"" tab "\",\"elapsed\":" f1(dt)

  # cpu
  out = out ",\"cpu\":{\"user\":" f1(cu) ",\"system\":" f1(csy) ",\"iowait\":" f1(cio) ",\"total\":" f1(cu + csy)
  out = out ",\"load\":[" num(l1) "," num(l2) "," num(l3) "],\"uptime\":" f1(t)
  out = out ",\"model\":" js(cs[1]) ",\"coreCount\":" (cs[2] + 0) ",\"threadCount\":" (cs[3] + 0)
  if (tab == "cpu") {
    lst = ""; for (i = 0; i < ncore; i++) lst = lst (i ? "," : "") f1(core[i])
    out = out ",\"cores\":[" lst "]"
    lst = ""
    if (effic != "") {
      ne = split(effic, er, ",")
      for (i = 1; i <= ne; i++) {
        if (split(er[i], rr, "-") == 2) { for (j = rr[1]; j <= rr[2]; j++) lst = lst (lst == "" ? "" : ",") j }
        else lst = lst (lst == "" ? "" : ",") er[i]
      }
    }
    out = out ",\"efficiency\":[" lst "]"
    out = out ",\"mhz\":" (fn ? sprintf("%.0f", fsum / fn / 1000) : "null") ",\"maxMhz\":" num(maxmhz)
    out = out ",\"temp\":" (ctemp != "" ? f1(ctemp) : "null")
  }
  out = out "}"

  # memory
  tot = M["MemTotal"]; av = ("MemAvailable" in M) ? M["MemAvailable"] : M["MemFree"] + M["Cached"] + M["Buffers"]
  cached = M["Cached"] + M["Buffers"] - M["Shmem"]; if (cached < 0) cached = 0
  used = tot - av
  apps = tot - M["MemFree"] - M["Cached"] - M["Buffers"] - M["SReclaimable"]; if (apps < 0) apps = 0
  out = out ",\"mem\":{\"total\":" sprintf("%.0f", tot) ",\"used\":" sprintf("%.0f", used) ",\"available\":" sprintf("%.0f", av)
  out = out ",\"free\":" sprintf("%.0f", M["MemFree"]) ",\"cached\":" sprintf("%.0f", cached) ",\"shared\":" sprintf("%.0f", M["Shmem"])
  out = out ",\"apps\":" sprintf("%.0f", apps) ",\"swapTotal\":" sprintf("%.0f", M["SwapTotal"]) ",\"swapUsed\":" sprintf("%.0f", M["SwapTotal"] - M["SwapFree"])
  out = out ",\"compressed\":" sprintf("%.0f", zorig) ",\"compressedSize\":" sprintf("%.0f", zcomp)
  out = out ",\"pressureSome\":" (pms != "" ? pms : "null") ",\"pressureFull\":" (pmf != "" ? pmf : "null") "}"

  # network totals (device-backed interfaces, else every one)
  srx = 0; stx = 0; arx = 0; atx = 0; anydev = 0
  for (i = 1; i <= nnet; i++) {
    nm = netorder[i]
    rr2 = rate(NRX[nm], "nr" nm); tt2 = rate(NTX[nm], "nt" nm)
    IRX[nm] = rr2; ITX[nm] = tt2
    S2 = S2 " nr" nm "=" NRX[nm] " nt" nm "=" NTX[nm]
    arx += rr2; atx += tt2
    if (NDEV[nm]) { srx += rr2; stx += tt2; anydev = 1 }
  }
  if (!anydev) { srx = arx; stx = atx }
  out = out ",\"net\":{\"rx\":" sprintf("%.0f", srx) ",\"tx\":" sprintf("%.0f", stx)
  if (tab == "network") {
    lst = ""; online = 0
    for (i = 1; i <= nnet; i++) {
      nm = netorder[i]
      if (!NDEV[nm] && V4[nm] == "" && V6[nm] == "") continue
      if (NUP[nm] || V4[nm] != "") online = online || (V4[nm] != "")
      e = "{\"name\":" js(nm) ",\"up\":" (NUP[nm] || V4[nm] != "" ? "true" : "false") ",\"wireless\":" (NWL[nm] ? "true" : "false")
      e = e ",\"default\":" (nm == defif ? "true" : "false") ",\"ipv4\":[" V4[nm] "],\"ipv6\":[" V6[nm] "]"
      e = e ",\"rx\":" sprintf("%.0f", IRX[nm]) ",\"tx\":" sprintf("%.0f", ITX[nm]) ",\"rxTotal\":" NRX[nm] ",\"txTotal\":" NTX[nm]
      e = e ",\"speed\":" (NSPEED[nm] > 0 ? NSPEED[nm] : 0)
      if (nm in WDBM) e = e ",\"dbm\":" WDBM[nm]
      if (nm in SSID) e = e ",\"ssid\":" js(SSID[nm])
      lst = lst (lst == "" ? "" : ",") e "}"
    }
    out = out ",\"ifaces\":[" lst "],\"default\":" js(defif) ",\"online\":" (online || defif != "" ? "true" : "false")
    lst = ""; cnt = 0
    for (g in SCONN) {
      key = "s" g; gsub(/[ =]/, "_", key)
      cur = STX[g] "," SRX[g]
      txr = 0; rxr = 0
      if (key in P && dt > 0) { split(P[key], q, ","); txr = (STX[g] - q[1]) / dt; rxr = (SRX[g] - q[2]) / dt; if (txr < 0) txr = 0; if (rxr < 0) rxr = 0 }
      S2 = S2 " " key "=" cur
      NP[g] = "{\"name\":" js(g) ",\"pid\":" SPID[g] ",\"count\":1,\"connections\":" SCONN[g] ",\"rx\":" sprintf("%.0f", rxr) ",\"tx\":" sprintf("%.0f", txr) "}"
      NPV[g] = rxr + txr + SCONN[g] / 1000
    }
    for (k2 = 0; k2 < 40; k2++) {
      best = ""; bv = -1
      for (g in NPV) if (!(g in usedn) && NPV[g] > bv) { bv = NPV[g]; best = g }
      if (best == "") break
      usedn[best] = 1; lst = lst (cnt++ ? "," : "") NP[best]
    }
    out = out ",\"procs\":[" lst "]"
  }
  out = out "}"

  if (tab == "cpu" || tab == "memory") {
    ng = 0; for (g in GCOUNT) ng++
    out = out ",\"procs\":{\"total\":" ng ",\"cpu\":" toplist("cpu", 8) ",\"mem\":" toplist("mem", 8)
    if (all == 1) out = out ",\"all\":" toplist((tab == "memory" ? "mem" : "cpu"), 200)
    out = out "}"
  }

  if (tab == "disks") {
    tr = 0; tw = 0; pd = ""
    for (i = 1; i <= ndisk; i++) {
      nm = diskorder[i]; tr += DR[nm]; tw += DW[nm]
      pd = pd (pd == "" ? "" : ",") js(nm) ":{\"read\":" sprintf("%.0f", DR[nm]) ",\"write\":" sprintf("%.0f", DW[nm]) ",\"busy\":" f1(DB[nm]) ",\"id\":" js(nm) "}"
    }
    vl = ""
    for (i = 1; i <= nvol; i++) {
      split(vols[i], vf, " ")
      dk = vf[7]
      vl = vl (vl == "" ? "" : ",") "{\"device\":" js(vf[1]) ",\"mount\":" js(vf[2]) ",\"fstype\":" js(vf[3]) ",\"size\":" sprintf("%.0f", vf[4] * 1024) ",\"used\":" sprintf("%.0f", vf[5] * 1024) ",\"avail\":" sprintf("%.0f", vf[6] * 1024)
      vl = vl ",\"disk\":" js(dk) ",\"key\":" js(dk) ",\"model\":" js(DMODEL[dk]) ",\"rotational\":" (DROT[dk] == 1 ? "true" : "false") ",\"removable\":" (DREM[dk] == 1 ? "true" : "false") ",\"kind\":" (DREM[dk] == 1 ? "\"external\"" : "\"internal\"") "}"
    }
    out = out ",\"disks\":{\"read\":" sprintf("%.0f", tr) ",\"write\":" sprintf("%.0f", tw) ",\"perDisk\":{" pd "},\"volumes\":[" vl "]"
    if (hasio) out = out ",\"pressureSome\":" (pis != "" ? pis : "null") ",\"pressureFull\":" (pif != "" ? pif : "null")
    out = out "}"
    # Per-process disk traffic: only the user's own processes are readable.
    for (pid in PRD) {
      key = "i" pid; cur = PRD[pid] "," PWR[pid]
      S2 = S2 " " key "=" cur
      if (!(key in P) || dt <= 0) continue
      split(P[key], q, ","); rr3 = (PRD[pid] - q[1]) / dt; ww3 = (PWR[pid] - q[2]) / dt
      if (rr3 < 0) rr3 = 0; if (ww3 < 0) ww3 = 0
      g = (pid in PCN) ? PCN[pid] : pid
      GREAD[g] += rr3; GWRITE[g] += ww3; GIO[g] += rr3 + ww3; GCOUNT[g]++
      if (!(g in GPID)) GPID[g] = pid
    }
    ng = 0; for (g in GCOUNT) ng++
    out = out ",\"procs\":{\"total\":" ng ",\"io\":" toplist("io", 8)
    if (all == 1) out = out ",\"all\":" toplist("io", 200)
    out = out "}"
  }

  if (tab == "gpu" && gpus != "") {
    out = out ",\"gpus\":" gpus
    if (gpus != "[]") { g1 = substr(gpus, 2); depth = 0; for (i = 1; i <= length(g1); i++) { ch = substr(g1, i, 1); if (ch == "{") depth++; if (ch == "}") { depth--; if (!depth) { g1 = substr(g1, 1, i); break } } }; out = out ",\"gpu\":" g1 }
  }

  if (tab == "sensors") {
    tl = ""; fl = ""; seen = " "; gt = ""
    for (i = 1; i <= nh; i++) {
      dir = hdirs[i]; name = HNAME[dir]
      chip = name; if (index(seen, " " name " ")) chip = name "." substr(dir, 6); seen = seen name " "
      for (k in HK) {
        split(k, kk, SUBSEP); if (kk[1] != dir || !(k in HIN)) continue
        base = kk[2]; lab = (k in HLAB) ? HLAB[k] : base
        if (base ~ /^temp/) {
          v = HIN[k] / 1000; mx = (k in HMAX) ? HMAX[k] / 1000 : 0
          if (v <= -50 || v > 200) continue
          tl = tl (tl == "" ? "" : ",") "{\"chip\":" js(friendly(name)) ",\"id\":" js(chip "/" base) ",\"label\":" js(lab) ",\"max\":" f1(mx) ",\"value\":" f1(v) "}"
          if (gt == "" && name ~ /^(amdgpu|nouveau|radeon)$/) gt = f1(v)
        } else if (base ~ /^fan/) {
          fl = fl (fl == "" ? "" : ",") "{\"chip\":" js(friendly(name)) ",\"id\":" js(chip "/" base) ",\"label\":" js(lab) ",\"rpm\":" (HIN[k] + 0) "}"
        }
      }
    }
    out = out ",\"sensors\":{\"temps\":[" tl "],\"fans\":[" fl "],\"gpuTemp\":" (gt == "" ? "null" : gt) "}"
    if (ctemp != "") out = out ",\"cpuTemp\":" f1(ctemp)
  }

  if (tab == "battery") {
    if (!("capacity" in B)) out = out ",\"battery\":{\"present\":false"
    else {
      vv = B["voltage_now"] / 1000000
      if ("energy_now" in B) { en = B["energy_now"] / 1e6; ef = B["energy_full"] / 1e6; ed = B["energy_full_design"] / 1e6; pw = B["power_now"] / 1e6 }
      else { en = B["charge_now"] / 1e6 * vv; ef = B["charge_full"] / 1e6 * vv; ed = B["charge_full_design"] / 1e6 * vv; pw = B["current_now"] / 1e6 * vv }
      if (pw < 0) pw = -pw
      st = B["status"]
      tte = 0; ttf = 0
      if (pw > 0 && st == "Discharging") tte = int(en / pw * 60)
      if (pw > 0 && st == "Charging") ttf = int((ef - en) / pw * 60)
      ac = hasac ? acon : (st == "Charging" || st == "Full" || st == "Not charging")
      out = out ",\"battery\":{\"present\":true,\"percent\":" (B["capacity"] + 0) ",\"status\":" js(st)
      out = out ",\"timeToEmpty\":" tte ",\"timeToFull\":" ttf ",\"energyNow\":" sprintf("%.2f", en) ",\"energyFull\":" sprintf("%.2f", ef) ",\"energyDesign\":" sprintf("%.2f", ed)
      out = out ",\"power\":" sprintf("%.2f", pw) ",\"voltage\":" sprintf("%.2f", vv) ",\"cycles\":" (B["cycle_count"] + 0)
      out = out ",\"health\":" (ed > 0 ? f1(ef / ed * 100 > 100 ? 100 : ef / ed * 100) : "null") ",\"acOnline\":" (ac ? "true" : "false")
      out = out ",\"model\":" js(B["model_name"]) ",\"technology\":" js(B["technology"])
    }
    pl = ""
    for (i = 1; i <= np; i++) {
      dev = porder[i]
      nmv = PV[dev SUBSEP "model_name"]; if (nmv == "") nmv = dev
      pl = pl (pl == "" ? "" : ",") "{\"name\":" js(nmv) ",\"percent\":" ((dev SUBSEP "capacity") in PV ? PV[dev SUBSEP "capacity"] + 0 : "null") ",\"status\":" js(PV[dev SUBSEP "status"]) "}"
    }
    out = out ",\"peripherals\":[" pl "]}"
  }
  out = out "}"
  # State first (always), the sample only once there is an interval to report.
  print "@STATE " S S2
  if (dt > 0) print out
}
AWK
}

# Every section the Linux sample needs, marked for the awk program. A
# function rather than inline in $( ), which old shells misparse with case.
linux_gather() {
    echo @STAT; cat /proc/stat
    echo @MEM; cat /proc/meminfo
    echo @NET; cat /proc/net/dev
    echo @LOAD; cat /proc/loadavg
    echo @PSIMEM; cat /proc/pressure/memory 2>/dev/null
    echo @ZRAM; for z in /sys/block/zram*/mm_stat; do [ -r "$z" ] && cat "$z"; done
    echo @SYSNET
    for n in /sys/class/net/*; do
      nn=${n##*/}; [ "$nn" = lo ] && continue
      os=""; vd_read "$n/operstate" && os=$val
      sp=0; vd_read "$n/speed" && sp=$val
      wl=0; [ -e "$n/wireless" ] && wl=1
      dv=0; [ -e "$n/device" ] && dv=1
      printf '%s %s %s %s %s\n' "$nn" "$os" "$sp" "$wl" "$dv"
    done
    case $tab in
      cpu|memory)
        echo @PROC; cat /proc/[0-9]*/stat 2>/dev/null
        if [ "$tab" = cpu ]; then
          echo @FREQ; grep -sh "" /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq
          echo @CPUT; [ -n "$cpu_temp_file" ] && cat "$cpu_temp_file" 2>/dev/null
        fi
        ;;
      disks)
        echo @DINFO; printf '%s\n' "$disk_info"
        echo @DISK; cat /proc/diskstats
        echo @PSIIO; cat /proc/pressure/io 2>/dev/null
        echo @VOLS; printf '%s\n' "$vols"
        echo @PIO; grep -sH -E '^(read|write)_bytes' /proc/[0-9]*/io
        echo @PCOMM; grep -sH "" /proc/[0-9]*/comm
        ;;
      network)
        echo @ROUTE; cat /proc/net/route 2>/dev/null
        echo @WIFI; cat /proc/net/wireless 2>/dev/null
        echo @ADDR; printf '%s\n' "$addrs"
        echo @SSID; printf '%s' "$ssids"
        echo @SS; ss -tinpH 2>/dev/null
        ;;
      sensors)
        echo @HW; hw_files=$(linux_hwmon_files); [ -n "$hw_files" ] && grep -sH "" $hw_files
        echo @CPUT; [ -n "$cpu_temp_file" ] && cat "$cpu_temp_file" 2>/dev/null
        ;;
      battery)
        echo @BAT; [ -n "$bat" ] && grep -sH "" "$bat"/*
        echo @AC; for a in /sys/class/power_supply/*; do vd_read "$a/type" && [ "$val" = Mains ] && vd_read "$a/online" && echo "$val"; done
        echo @PERIPH; for p in $periph; do grep -sH "" "$p/model_name" "$p/capacity" "$p/status" "$p/name" 2>/dev/null; done
        ;;
    esac
}

linux_main() {
  page=$(getconf PAGESIZE 2>/dev/null || echo 4096)
  clk=$(getconf CLK_TCK 2>/dev/null || echo 100)
  # Static facts, once: CPU model, cores and threads, efficiency cores, the
  # CPU temperature file, the system battery.
  cpu_static=$(awk -F': *' '
    /^model name/ && model == "" { model = $2 }
    /^processor/ { threads++ }
    /^physical id/ { phys = $2 }
    /^core id/ { key = phys "-" $2; if (!(key in seen)) { seen[key] = 1; cores++ } }
    END { gsub(/["\\]/, "", model); printf "%s|%d|%d", model, (cores ? cores : threads), threads }' /proc/cpuinfo 2>/dev/null)
  effic=""; vd_read /sys/devices/cpu_atom/cpus && effic=$val
  maxmhz=""; vd_read /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq && maxmhz=$((val / 1000))
  cpu_temp_file=""; best=99
  for h in /sys/class/hwmon/hwmon*; do
    vd_read "$h/name" || continue; hn=$val
    for f in "$h"/temp*_input; do
      [ -r "$f" ] || continue
      lab=""; vd_read "${f%_input}_label" && lab=$val
      r=99
      case $hn in
        k10temp|zenpower) case $lab in Tctl|Tdie|"") r=1 ;; esac ;;
        coretemp) case $lab in Package*) r=2 ;; esac ;;
        cpu_thermal|soc_thermal) r=3 ;;
        acpitz) r=5 ;;
      esac
      [ "$r" -lt "$best" ] && { best=$r; cpu_temp_file=$f; }
    done
  done
  bat=""; periph=""
  for b in /sys/class/power_supply/*; do
    vd_read "$b/type" && [ "$val" = Battery ] || continue
    if vd_read "$b/scope" && [ "$val" = Device ]; then periph="$periph $b"; continue; fi
    [ -n "$bat" ] || bat=$b
  done
  disk_info=""; [ "$tab" = disks ] && disk_info=$(linux_disk_info)
  state=""; vols=""; addrs=""; ssids=""; slow_due=0; first=1
  linux_prog=$(linux_awk)
  nl='
'

  # The first pass only records counters; the second follows half a second
  # later so the panel fills quickly, then every interval.
  while :; do
    case $first in
      1) first=2 ;;
      2) sleep 0.5 2>/dev/null || sleep 1; first=0 ;;
      *) sleep "$interval" || exit 0; vd_lifetime "$interval" ;;
    esac
    read -r up_s _ < /proc/uptime
    now=${up_s%%.*}
    if [ "$now" -ge "$slow_due" ]; then
      slow_due=$((now + 10))
      [ "$tab" = disks ] && vols=$(linux_volumes)
      if [ "$tab" = network ]; then
        addrs=$(ip -o addr show 2>/dev/null | awk '{ sub(/\/.*/, "", $4); print $2, $3, $4 }')
        ssids=""
        if command -v iwgetid >/dev/null 2>&1; then
          for w in /sys/class/net/*/wireless; do
            [ -e "$w" ] || continue
            wi=${w%/wireless}; wi=${wi##*/}
            ss_name=$(iwgetid -r "$wi" 2>/dev/null | tr -d '"\\')
            [ -n "$ss_name" ] && ssids="$ssids$wi $ss_name
"
          done
        fi
      fi
    fi
    gpus_json=""
    [ "$tab" = gpu ] && linux_gpus

    out=$(linux_gather | awk -v prev="$state" -v up="$up_s" -v tab="$tab" -v page="$page" -v clk="$clk" \
          -v cpus="$cpu_static" -v effic="$effic" -v maxmhz="$maxmhz" -v all="$want_all" \
          -v gpus="$gpus_json" "$linux_prog")
    state=${out%%"$nl"*}
    state=${state#@STATE }
    json=${out#*"$nl"}
    [ "$json" != "$out" ] && [ -n "$json" ] && vd_emit "$json"
  done
}

# ---------------------------------------------------------------- macOS

darwin_awk() {
  cat <<'AWK'
function js(s) { gsub(/["\\]/, "", s); gsub(/[\001-\037]/, "", s); return "\"" s "\"" }
function f1(v) { return sprintf("%.1f", v) }
function bytes(s,  u, v) {
  v = s + 0; u = s; gsub(/[0-9.]/, "", u)
  if (u == "K") v *= 1024; else if (u == "M") v *= 1048576; else if (u == "G") v *= 1073741824; else if (u == "T") v *= 1099511627776
  return v
}
# ioreg prints a negative amperage as an unsigned 64-bit number; recover it
# from its last eight digits, which a double holds exactly.
function signed(s,  low) {
  if (length(s) < 19) return s + 0
  low = substr(s, length(s) - 7) + 0
  return -((9551616 - low + 100000000) % 100000000)
}
function toplist(k, n,   out, used, i, j, best, bv, v, cnt) {
  out = ""; cnt = 0
  for (i = 0; i < n; i++) {
    best = ""; bv = -1
    for (j in GCOUNT) {
      if (j in used) continue
      v = (k == "cpu" ? GCPU[j] : GMEM[j])
      if (v > bv) { bv = v; best = j }
    }
    if (best == "") break
    used[best] = 1
    out = out (cnt++ ? "," : "") "{\"name\":" js(best) ",\"pid\":" GPID[best] ",\"count\":" GCOUNT[best] ",\"cpu\":" f1(GCPU[best]) ",\"mem\":" sprintf("%.0f", GMEM[best]) "}"
  }
  return "[" out "]"
}
BEGIN {
  n = split(prev, kv, " ")
  for (i = 1; i <= n; i++) { p = index(kv[i], "="); if (p) P[substr(kv[i], 1, p - 1)] = substr(kv[i], p + 1) }
  split(statics, cs, "|")
}
/^@/ { sec = substr($0, 2); next }
sec == "IOSTAT" && NF >= 3 && $1 ~ /^[0-9]+$/ { us = $1; sy = $2 }
sec == "VM" {
  if ($0 ~ /page size of/) { for (i = 1; i <= NF; i++) if ($i == "of") page = $(i + 1) }
  v = $NF; gsub(/\./, "", v)
  if ($0 ~ /^Pages free/) VF = v
  else if ($0 ~ /^Pages speculative/) VS = v
  else if ($0 ~ /^Anonymous pages/) VA = v
  else if ($0 ~ /^Pages purgeable/) VP = v
  else if ($0 ~ /^Pages wired down/) VW = v
  else if ($0 ~ /^Pages occupied by compressor/) VC = v
  else if ($0 ~ /^Pages stored in compressor/) VSC = v
  else if ($0 ~ /^File-backed pages/) VFB = v
  next
}
sec == "NET" && $3 ~ /^<Link/ && $1 != "lo0" {
  nm = $1; if (nm in NRX) next
  NRX[nm] = $(NF - 4); NTX[nm] = $(NF - 1); netorder[++nnet] = nm
  next
}
sec == "SYS" {
  if ($0 ~ /\{ sec = /) { b = $0; sub(/^[^=]*= /, "", b); sub(/,.*/, "", b); boot = b + 0 }
  else if ($1 == "{") { l1 = $2; l2 = $3; l3 = $4 }
  else if ($1 == "total") { swt = bytes($3); swu = bytes($6) }
  else if ($1 ~ /^[0-9]+$/) now = $1 + 0
  next
}
sec == "PS" && NF >= 4 {
  pid = $1; pc = $2 + 0; rss = $3 * 1024
  comm = $4; for (i = 5; i <= NF; i++) comm = comm " " $i
  GCPU[comm] += pc; GMEM[comm] += rss; GCOUNT[comm]++
  if (!(comm in GTOP) || pc >= GTOP[comm]) { GTOP[comm] = pc; GPID[comm] = pid }
  next
}
sec == "DSK" && /"Statistics" = \{/ {
  if (match($0, /"Bytes \(Read\)"=[0-9]+/)) drd += substr($0, RSTART + 15, RLENGTH - 15)
  if (match($0, /"Bytes \(Write\)"=[0-9]+/)) dwr += substr($0, RSTART + 16, RLENGTH - 16)
  dsk = 1
  next
}
sec == "DF" && $1 ~ /^\/dev\// {
  mnt = $NF
  if (mnt ~ /^\/System\/Volumes\// || mnt ~ /^\/Library\/Developer\//) next
  vols[++nvol] = $1 " " $2 " " $4 " " mnt
  next
}
sec == "IFC" {
  if ($0 ~ /^[a-z]/) { ci = $1; sub(/:$/, "", ci); IFUP[ci] = ($0 ~ /<UP/); next }
  if ($1 == "status:") IFACT[ci] = ($2 == "active")
  else if ($1 == "inet" && ci != "lo0") V4[ci] = V4[ci] (V4[ci] == "" ? "" : ",") js($2)
  else if ($1 == "inet6" && ci != "lo0" && $2 !~ /^fe80/) { a6 = $2; sub(/%.*/, "", a6); V6[ci] = V6[ci] (V6[ci] == "" ? "" : ",") js(a6) }
  next
}
sec == "ROUTE" && $1 == "interface:" { defif = $2; next }
sec == "NT" && NR > 0 {
  if ($0 ~ /^,/ || $0 == "") next
  split($0, f, ",")
  key = f[1]; nmn = key; sub(/\.[0-9]+$/, "", nmn); pid = key; sub(/.*\./, "", pid)
  if (nmn == "" || pid !~ /^[0-9]+$/) next
  rxb = f[2] + 0; txb = f[3] + 0
  sk = "n" pid
  S2 = S2 " " sk "=" rxb "," txb
  rr = 0; tt = 0
  if (sk in P && dt > 0) { split(P[sk], q, ","); rr = (rxb - q[1]) / dt; tt = (txb - q[2]) / dt; if (rr < 0) rr = 0; if (tt < 0) tt = 0 }
  NPRX[nmn] += rr; NPTX[nmn] += tt; NPC[nmn]++; if (!(nmn in NPPID)) NPPID[nmn] = pid
  next
}
sec == "GPU" && gutil == "" && match($0, /"Device Utilization %"=[0-9]+/) {
  gutil = substr($0, RSTART + 23, RLENGTH - 23)
  if (match($0, /"In use system memory"=[0-9]+/)) gmem = substr($0, RSTART + 23, RLENGTH - 23)
  next
}
sec == "BAT" {
  if ($2 == "=" && $1 ~ /^"[A-Za-z]+"$/) { k = $1; gsub(/"/, "", k); BV[k] = $3 }
  if (match($0, /"CycleCount"=[0-9]+/)) BV["CycleCount"] = substr($0, RSTART + 13, RLENGTH - 13)
  next
}
END {
  # The iostat wait is the sample's length; date's whole seconds are too
  # coarse to time it.
  dt = ("t" in P) ? interval : 0
  S = "t=" now
  out = "{\"type\":\"detail\",\"tab\":\"" tab "\",\"elapsed\":" f1(dt)
  out = out ",\"cpu\":{\"user\":" f1(us) ",\"system\":" f1(sy) ",\"total\":" f1(us + sy)
  out = out ",\"load\":[" (l1 == "" ? "null" : l1) "," (l2 == "" ? "null" : l2) "," (l3 == "" ? "null" : l3) "]"
  out = out ",\"uptime\":" (boot > 0 && now > 0 ? now - boot : "null")
  out = out ",\"model\":" js(cs[1]) ",\"coreCount\":" (cs[2] + 0) ",\"threadCount\":" (cs[3] + 0) "}"

  # Activity Monitor's terms: app memory plus wired is what apps hold,
  # file-backed pages are the cache, the compressor's pages are compressed.
  app = VA - VP; if (app < 0) app = 0
  tot = cs[4] + 0
  used = (app + VW + VC) * page; if (used > tot) used = tot
  out = out ",\"mem\":{\"total\":" sprintf("%.0f", tot) ",\"used\":" sprintf("%.0f", used)
  out = out ",\"apps\":" sprintf("%.0f", (app + VW) * page) ",\"cached\":" sprintf("%.0f", VFB * page)
  out = out ",\"free\":" sprintf("%.0f", (VF + VS) * page) ",\"compressed\":" sprintf("%.0f", VSC * page) ",\"compressedSize\":" sprintf("%.0f", VC * page)
  if (swt != "") out = out ",\"swapTotal\":" sprintf("%.0f", swt) ",\"swapUsed\":" sprintf("%.0f", swu)
  out = out "}"

  srx = 0; stx = 0
  for (i = 1; i <= nnet; i++) {
    nm = netorder[i]
    S = S " r" nm "=" NRX[nm] "," NTX[nm]
    IRX[nm] = 0; ITX[nm] = 0
    if (("r" nm) in P && dt > 0) { split(P["r" nm], q, ","); IRX[nm] = (NRX[nm] - q[1]) / dt; ITX[nm] = (NTX[nm] - q[2]) / dt; if (IRX[nm] < 0) IRX[nm] = 0; if (ITX[nm] < 0) ITX[nm] = 0 }
    if (nm ~ /^en[0-9]+$/) { srx += IRX[nm]; stx += ITX[nm] }
  }
  out = out ",\"net\":{\"rx\":" sprintf("%.0f", srx) ",\"tx\":" sprintf("%.0f", stx)
  if (tab == "network") {
    lst = ""; online = 0
    for (i = 1; i <= nnet; i++) {
      nm = netorder[i]
      if (V4[nm] == "" && V6[nm] == "" && !IFACT[nm]) continue
      up = (IFACT[nm] || (IFUP[nm] && V4[nm] != ""))
      if (V4[nm] != "") online = 1
      e = "{\"name\":" js(nm) ",\"up\":" (up ? "true" : "false") ",\"wireless\":" (nm == wifi ? "true" : "false")
      e = e ",\"default\":" (nm == defif ? "true" : "false") ",\"ipv4\":[" V4[nm] "],\"ipv6\":[" V6[nm] "]"
      e = e ",\"rx\":" sprintf("%.0f", IRX[nm]) ",\"tx\":" sprintf("%.0f", ITX[nm]) ",\"rxTotal\":" NRX[nm] ",\"txTotal\":" NTX[nm] ",\"speed\":0}"
      lst = lst (lst == "" ? "" : ",") e
    }
    out = out ",\"ifaces\":[" lst "],\"default\":" js(defif) ",\"online\":" (online ? "true" : "false")
    out = out ",\"procsAllProtocols\":true"
    lst = ""; cnt = 0
    for (k2 = 0; k2 < 40; k2++) {
      best = ""; bv = -1
      for (g in NPC) if (!(g in usedn) && NPRX[g] + NPTX[g] > bv) { bv = NPRX[g] + NPTX[g]; best = g }
      if (best == "") break
      usedn[best] = 1
      lst = lst (cnt++ ? "," : "") "{\"name\":" js(best) ",\"pid\":" NPPID[best] ",\"count\":" NPC[best] ",\"rx\":" sprintf("%.0f", NPRX[best]) ",\"tx\":" sprintf("%.0f", NPTX[best]) "}"
    }
    out = out ",\"procs\":[" lst "]"
  }
  out = out "}"

  if (tab == "cpu" || tab == "memory") {
    ng = 0; for (g in GCOUNT) ng++
    out = out ",\"procs\":{\"total\":" ng ",\"cpu\":" toplist("cpu", 8) ",\"mem\":" toplist("mem", 8)
    if (all == 1) out = out ",\"all\":" toplist((tab == "memory" ? "mem" : "cpu"), 200)
    out = out "}"
  }

  if (tab == "disks") {
    rd = 0; wr = 0
    if (dsk) {
      S = S " d=" sprintf("%.0f", drd) "," sprintf("%.0f", dwr)
      if (("d") in P && dt > 0) { split(P["d"], q, ","); rd = (drd - q[1]) / dt; wr = (dwr - q[2]) / dt; if (rd < 0) rd = 0; if (wr < 0) wr = 0 }
    }
    vl = ""
    for (i = 1; i <= nvol; i++) {
      split(vols[i], vf, " ")
      dev = vf[1]; dk = dev; sub(/^\/dev\//, "", dk); sub(/s[0-9]+.*$/, "", dk)
      mnt = vf[4]
      sz = vf[2] * 1024; av = vf[3] * 1024; usd = sz - av; if (usd < 0) usd = 0
      ext = (mnt ~ /^\/Volumes\//)
      vl = vl (vl == "" ? "" : ",") "{\"device\":" js(dev) ",\"mount\":" js(mnt) ",\"size\":" sprintf("%.0f", sz) ",\"used\":" sprintf("%.0f", usd) ",\"avail\":" sprintf("%.0f", av) ",\"disk\":" js(dk) ",\"key\":" js(dk) ",\"rotational\":false,\"removable\":" (ext ? "true" : "false") ",\"kind\":" (ext ? "\"external\"" : "\"internal\"") "}"
    }
    out = out ",\"disks\":{\"read\":" sprintf("%.0f", rd) ",\"write\":" sprintf("%.0f", wr) ",\"perDisk\":{},\"volumes\":[" vl "]}"
  }

  if (tab == "gpu" && gutil != "") {
    g = "{\"id\":\"apple\",\"name\":" js(cs[1] " GPU") ",\"vendor\":\"apple\",\"integrated\":true,\"util\":" gutil ",\"mhz\":null,\"maxMhz\":null,\"temp\":null,\"power\":null,\"fan\":null,\"memUsed\":" (gmem == "" ? "null" : gmem) ",\"memTotal\":null}"
    out = out ",\"gpus\":[" g "],\"gpu\":" g
  }

  if ((tab == "battery" || tab == "sensors") && BV["MaxCapacity"] + 0 > 0) {
    pct = int(BV["CurrentCapacity"] * 100 / BV["MaxCapacity"] + 0.5); if (pct > 100) pct = 100
    if (BV["FullyCharged"] == "Yes") st = "Full"
    else if (BV["IsCharging"] == "Yes") st = "Charging"
    else if (BV["ExternalConnected"] == "Yes") st = "Not charging"
    else st = "Discharging"
    mv = BV["Voltage"] + 0; vv = mv / 1000
    amp = signed(BV["InstantAmperage"] != "" ? BV["InstantAmperage"] : BV["Amperage"])
    pw = vv * (amp < 0 ? -amp : amp) / 1000
    nom = BV["NominalChargeCapacity"] + 0; des = BV["DesignCapacity"] + 0
    tte = (st == "Discharging" && BV["TimeRemaining"] + 0 > 0 && BV["TimeRemaining"] + 0 < 65535) ? BV["TimeRemaining"] + 0 : 0
    ttf = (st == "Charging" && BV["AvgTimeToFull"] + 0 > 0 && BV["AvgTimeToFull"] + 0 < 65535) ? BV["AvgTimeToFull"] + 0 : 0
    if (tab == "battery") {
      out = out ",\"battery\":{\"present\":true,\"percent\":" pct ",\"status\":" js(st) ",\"timeToEmpty\":" tte ",\"timeToFull\":" ttf
      if (mv > 0) out = out ",\"voltage\":" sprintf("%.2f", vv) ",\"power\":" sprintf("%.2f", pw)
      if (mv > 0 && nom > 0) out = out ",\"energyFull\":" sprintf("%.2f", nom * vv / 1000)
      if (mv > 0 && des > 0) out = out ",\"energyDesign\":" sprintf("%.2f", des * vv / 1000)
      if (nom > 0 && des > 0) out = out ",\"health\":" f1(nom / des * 100 > 100 ? 100 : nom / des * 100)
      out = out ",\"cycles\":" (BV["CycleCount"] + 0) ",\"acOnline\":" (BV["ExternalConnected"] == "Yes" ? "true" : "false") ",\"peripherals\":[]}"
    }
    if (tab == "sensors" && BV["Temperature"] + 0 > 0)
      out = out ",\"sensors\":{\"temps\":[{\"chip\":\"Battery\",\"id\":\"battery\",\"label\":\"Temperature\",\"max\":0,\"value\":" f1(BV["Temperature"] / 100) "}],\"fans\":[],\"gpuTemp\":null}"
  }
  out = out "}"
  print "@STATE " S S2
  if (dt > 0) print out
}
AWK
}

# Every section the macOS sample needs; the first pass skips the iostat wait.
darwin_gather() {
    echo @IOSTAT
    if [ "$first" = 1 ]; then echo; else iostat -n0 -c 2 -w "$span"; fi
    echo @VM; vm_stat
    echo @NET; netstat -ibn
    echo @SYS; sysctl -n vm.loadavg kern.boottime; [ "$tab" = memory ] && sysctl -n vm.swapusage; date +%s
    case $tab in
      cpu|memory) echo @PS; ps -Aceo pid=,pcpu=,rss=,comm= ;;
      disks) echo @DSK; ioreg -c IOBlockStorageDriver -r -d 1 -w0 -k Statistics; echo @DF; df -kl ;;
      network) echo @IFC; ifconfig -a; echo @ROUTE; route -n get default; echo @NT; nettop -P -L 1 -x -J bytes_in,bytes_out -n ;;
      gpu) echo @GPU; ioreg -r -d 1 -c IOAccelerator -k PerformanceStatistics ;;
      battery|sensors) echo @BAT; ioreg -rc AppleSmartBattery -w0 ;;
    esac
}

darwin_main() {
  wait_s=${interval%%.*}
  [ -n "$wait_s" ] && [ "$wait_s" -ge 1 ] 2>/dev/null || wait_s=1
  # shellcheck disable=SC2046
  set -- $(sysctl -n hw.physicalcpu hw.logicalcpu hw.memsize 2>/dev/null)
  statics="$(sysctl -n machdep.cpu.brand_string 2>/dev/null | tr -d '"\\|')|${1:-0}|${2:-0}|${3:-0}"
  wifi=""
  [ "$tab" = network ] && wifi=$(networksetup -listallhardwareports 2>/dev/null | awk '/Hardware Port: Wi-Fi/ { getline; print $2; exit }')
  darwin_prog=$(darwin_awk)
  state=""; first=1; span=1
  nl='
'
  while :; do
    out=$(darwin_gather 2>/dev/null | awk -v prev="$state" -v tab="$tab" -v statics="$statics" -v all="$want_all" \
          -v wifi="$wifi" -v interval="$span" "$darwin_prog")
    # The first report comes after a one-second window, then every interval.
    [ "$first" = 1 ] && span=1 || span=$wait_s
    first=0
    vd_lifetime "$span"
    state=${out%%"$nl"*}
    state=${state#@STATE }
    json=${out#*"$nl"}
    [ "$json" != "$out" ] && [ -n "$json" ] && vd_emit "$json"
  done
}


main() {
  interval=${1:-2}
  case $interval in ''|*[!0-9.]*|.*|*.*.*) interval=2 ;; esac
  tab=$(printf '%s' "${2:-cpu}" | tr -cd 'a-z')
  want_all=0; [ "${3:-}" = all ] && want_all=1
  vd_age=0
  export LC_ALL=C
  case $(uname -s 2>/dev/null) in
    Linux) linux_main ;;
    Darwin) darwin_main ;;
    *) vd_emit '{"type":"error","message":"unsupported system"}'; exit 1 ;;
  esac
}

main "$@" < /dev/null; exit
