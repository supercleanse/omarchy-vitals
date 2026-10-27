# Vitals sampler: a small POSIX sh loop that prints one JSON line per sample.
#
#   sh vitals-sampler.sh <interval> [extras] [sensor-ids]
#
# Runs locally under sh, and on remote machines as `ssh <dest> sh -s -- ...`
# with this file streamed on stdin, so nothing is installed on the remote side.
# Supports Linux and macOS and never needs root.
#
# CPU, memory and network are always sampled. `extras` is a comma list of the
# costlier modules to sample as well: gpu, disks, sensors, battery. `sensor-ids`
# is a comma list of the sensors to read (ids from the hello line). Modules
# that are not asked for cost nothing.
#
# First line, a description of the machine:
#   {"type":"hello","v":2,"os":"linux","osName":"...","host":"...","cores":8,
#    "interval":2,"caps":{"gpu":true,"disks":true,"sensors":true,"battery":false},
#    "gpus":[...],"disks":["nvme0n1"],"sensors":[{"id":"cpu","label":"...","kind":"temp"}]}
# Then one line per interval:
#   {"type":"sample","cpu":12.3,"user":8.1,"sys":4.2,"memUsed":...,"memTotal":...,
#    "rx":...,"tx":...,"load":0.42, plus "gpus", "disk", "temps", "fans",
#    "battery" for the extras asked for}
#
# Percentages are of all cores; memory and space are bytes; rates are bytes per
# second; temperatures are degrees Celsius. On error it prints
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

vitals_has() {
  case ",$extras," in *",$1,"*) return 0 ;; esac
  return 1
}

vitals_bool() {
  if [ "$1" -gt 0 ] 2>/dev/null; then printf true; else printf false; fi
}

# Read the first line of a file into $val with the read builtin (no fork).
# Fails, leaving $val empty, when the file is missing or unreadable.
vitals_read() {
  val=""
  [ -r "$1" ] || return 1
  read -r val 2>/dev/null < "$1" || [ -n "$val" ]
}

# A device that runtime power management has put to sleep stays asleep:
# reading its counters would wake it (and drain a laptop's battery).
vitals_asleep() {
  vitals_read "$1/power/runtime_status" && [ "$val" = suspended ]
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

# --- what this machine has, found once at start

linux_scan_gpus() {
  g_n=0; gpus_json=""
  for g_card in /sys/class/drm/card[0-9]*; do
    case ${g_card##*/} in *-*) continue ;; esac
    vitals_read "$g_card/device/vendor" || continue
    case $val in
      0x1002) g_kind=amd; g_name="AMD GPU" ;;
      0x10de) g_kind=nvidia; g_name="NVIDIA GPU" ;;
      0x8086) g_kind=intel; g_name="Intel GPU" ;;
      *) continue ;;
    esac
    g_id=$(cd "$g_card/device" 2>/dev/null && pwd -P)
    g_id=${g_id##*/}
    g_util=0
    [ "$g_kind" = amd ] && [ -r "$g_card/device/gpu_busy_percent" ] && g_util=1
    [ "$g_kind" = nvidia ] && [ -n "$nvsmi" ] && g_util=1
    g_n=$((g_n + 1))
    eval "g_kind_$g_n=\$g_kind g_card_$g_n=\$g_card g_id_$g_n=\$g_id"
    gpus_json="$gpus_json${gpus_json:+,}{\"id\":\"$g_id\",\"name\":\"$g_name\",\"vendor\":\"$g_kind\",\"util\":$(vitals_bool $g_util)}"
  done
}

linux_scan_battery() {
  bat=""
  for b_dir in /sys/class/power_supply/*; do
    vitals_read "$b_dir/type" && [ "$val" = Battery ] || continue
    # Mice, keyboards and headsets report scope=Device; only the system battery counts.
    vitals_read "$b_dir/scope" && [ "$val" = Device ] && continue
    bat=$b_dir
    break
  done
}

# Whole disks: NVMe, SATA/SCSI, virtio, MMC and md arrays, never partitions,
# loop devices, RAM disks or device-mapper volumes.
linux_scan_disks() {
  d_list=""; disks_json=""
  for d_dir in /sys/block/*; do
    d_name=${d_dir##*/}
    case $d_name in loop*|ram*|zram*|dm-*|sr*|fd*|nbd*) continue ;; esac
    case $d_name in md*) ;; *) [ -e "$d_dir/device" ] || continue ;; esac
    case $d_name in *[!A-Za-z0-9_]*) continue ;; esac
    d_list="$d_list $d_name"
    disks_json="$disks_json${disks_json:+,}\"$d_name\""
  done
}

# Every hwmon temperature and fan, with a friendly label, plus "cpu" for the
# best CPU package reading (the same preference order OmaStats uses).
linux_scan_sensors() {
  s_n=0; s_lines=""; s_cpu=""; s_rank=99; s_seen=" "
  for h_dir in /sys/class/hwmon/hwmon*; do
    vitals_read "$h_dir/name" || continue
    h_name=$val
    [ -e "$h_dir/device" ] && vitals_asleep "$h_dir/device" && continue
    h_chip=$h_name
    case $s_seen in *" $h_name "*) h_chip="$h_name.${h_dir##*hwmon}" ;; esac
    s_seen="$s_seen$h_name "
    case $h_name in
      k10temp|zenpower|coretemp) h_label=CPU ;;
      amdgpu|nouveau|radeon) h_label=GPU ;;
      nvme) h_label=NVMe ;;
      iwlwifi*|ath*|mt7*) h_label=Wi-Fi ;;
      acpitz) h_label=ACPI ;;
      BAT*) h_label=Battery ;;
      dell_*) h_label=Dell ;;
      thinkpad) h_label=ThinkPad ;;
      *) h_label=$h_name ;;
    esac
    for h_file in "$h_dir"/temp*_input "$h_dir"/fan*_input; do
      [ -r "$h_file" ] || continue
      h_base=${h_file##*/}; h_base=${h_base%_input}
      h_lab=""
      vitals_read "$h_dir/${h_base}_label" && h_lab=$val
      case $h_base in temp*) h_kind=temp ;; *) h_kind=fan ;; esac
      h_rank=99
      case $h_name in
        k10temp|zenpower) case $h_lab in Tctl|Tdie|"") h_rank=1 ;; esac ;;
        coretemp) case $h_lab in Package*) h_rank=2 ;; esac ;;
        cpu_thermal|soc_thermal) h_rank=3 ;;
        acpitz) h_rank=5 ;;
      esac
      if [ "$h_kind" = temp ] && [ "$h_rank" -lt "$s_rank" ]; then s_rank=$h_rank; s_cpu=$h_file; fi
      [ "$s_n" -ge 48 ] && continue
      s_n=$((s_n + 1))
      eval "s_id_$s_n=\$h_chip/\$h_base s_path_$s_n=\$h_file s_kind_$s_n=\$h_kind"
      s_lines="$s_lines$h_chip/$h_base|$h_label ${h_lab:-$h_base}|$h_kind
"
    done
  done
  [ -n "$s_cpu" ] && s_lines="cpu|CPU temperature|temp
$s_lines"
  sensors_json=$(printf '%s' "$s_lines" | awk -F'|' '
    NF >= 3 { gsub(/["\\]/, "", $2); printf "%s{\"id\":\"%s\",\"label\":\"%s\",\"kind\":\"%s\"}", (n++ ? "," : ""), $1, substr($2, 1, 40), $3 }')
}

# --- per-sample readers for the extras

linux_gpus() {
  g_out=""; nv_lines=""
  if [ -n "$nvsmi" ]; then
    g_i=1; nv_awake=0
    while [ "$g_i" -le "$g_n" ]; do
      eval "g_kind=\$g_kind_$g_i g_card=\$g_card_$g_i"
      [ "$g_kind" = nvidia ] && ! vitals_asleep "$g_card/device" && nv_awake=1
      g_i=$((g_i + 1))
    done
    [ "$nv_awake" -eq 1 ] && nv_lines=$("$nvsmi" --query-gpu=pci.bus_id,utilization.gpu,memory.used,memory.total,temperature.gpu,clocks.gr --format=csv,noheader,nounits 2>/dev/null)
  fi
  g_i=1
  while [ "$g_i" -le "$g_n" ]; do
    eval "g_kind=\$g_kind_$g_i g_card=\$g_card_$g_i g_id=\$g_id_$g_i"
    g_util=null; g_mhz=null; g_temp=null; g_mu=null; g_mt=null
    g_dev=$g_card/device
    if vitals_asleep "$g_dev"; then
      # Runtime-suspended means idle; report that without waking it.
      g_util=0
    else
      case $g_kind in
        amd)
          vitals_read "$g_dev/gpu_busy_percent" && g_util=$val
          vitals_read "$g_dev/mem_info_vram_used" && g_mu=$val
          vitals_read "$g_dev/mem_info_vram_total" && g_mt=$val
          for g_h in "$g_dev"/hwmon/hwmon*; do
            vitals_read "$g_h/temp1_input" && g_temp=$(vitals_tenths $((val / 100)))
            vitals_read "$g_h/freq1_input" && g_mhz=$((val / 1000000))
            break
          done
          ;;
        intel)
          if vitals_read "$g_card/gt_act_freq_mhz"; then g_mhz=$val
          elif vitals_read "$g_dev/tile0/gt0/freq0/act_freq"; then g_mhz=$val
          fi
          ;;
        nvidia)
          g_bus=$(printf '%s' "$g_id" | tr 'a-f' 'A-F')
          g_line=$(printf '%s\n' "$nv_lines" | grep -i "$g_bus" | head -n 1)
          if [ -n "$g_line" ]; then
            IFS=', ' read -r _ g_util g_mu g_mt g_temp g_mhz <<EOF
$g_line
EOF
            case $g_util in ''|*[!0-9]*) g_util=null ;; esac
            case $g_mu in ''|*[!0-9]*) g_mu=null ;; *) g_mu=$((g_mu * 1048576)) ;; esac
            case $g_mt in ''|*[!0-9]*) g_mt=null ;; *) g_mt=$((g_mt * 1048576)) ;; esac
            case $g_temp in ''|*[!0-9]*) g_temp=null ;; esac
            case $g_mhz in ''|*[!0-9]*) g_mhz=null ;; esac
          fi
          ;;
      esac
    fi
    case $g_util in ''|*[!0-9]*) [ "$g_util" = null ] || g_util=null ;; esac
    g_out="$g_out${g_out:+,}{\"id\":\"$g_id\",\"util\":$g_util,\"mhz\":$g_mhz,\"temp\":$g_temp,\"memUsed\":$g_mu,\"memTotal\":$g_mt}"
    g_i=$((g_i + 1))
  done
  gpu_part=",\"gpus\":[$g_out]"
}

# Read and write rates per whole disk from /proc/diskstats (512-byte sectors).
linux_disk_counters() {
  dc_r=0; dc_w=0
  while read -r _ _ dc_name _ _ dc_sr _ _ _ dc_sw _rest; do
    case " $d_list " in *" $dc_name "*) ;; *) continue ;; esac
    eval "dc_r_$dc_name=\$dc_sr dc_w_$dc_name=\$dc_sw"
    dc_r=$((dc_r + dc_sr)); dc_w=$((dc_w + dc_sw))
  done < /proc/diskstats
}

# The whole disk under a mounted block device, following partitions and
# device-mapper (LUKS, LVM) down to the first physical disk.
linux_disk_of() {
  do_dev=$(readlink -f "$1" 2>/dev/null)
  do_name=${do_dev##*/}
  do_hops=0
  while [ "$do_hops" -lt 4 ]; do
    do_hops=$((do_hops + 1))
    case " $d_list " in *" $do_name "*) printf '%s' "$do_name"; return ;; esac
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

# Space used per disk from df, every half minute: it changes slowly and df
# is the one process this module starts.
linux_space() {
  sp_out=""; sp_au=0; sp_as=0; sp_seen=" "; sp_disks=" "
  sp_df=$(df -kP 2>/dev/null)
  while read -r sp_src sp_size sp_used _ _ _; do
    case $sp_src in /dev/loop*) continue ;; /dev/*) ;; *) continue ;; esac
    case $sp_seen in *" $sp_src "*) continue ;; esac
    sp_seen="$sp_seen$sp_src "
    sp_disk=$(linux_disk_of "$sp_src")
    [ -n "$sp_disk" ] || continue
    case $sp_disks in *" $sp_disk "*) ;; *) sp_disks="$sp_disks$sp_disk "; eval "sp_u_$sp_disk=0 sp_s_$sp_disk=0" ;; esac
    eval "sp_u_$sp_disk=\$((sp_u_$sp_disk + sp_used * 1024)) sp_s_$sp_disk=\$((sp_s_$sp_disk + sp_size * 1024))"
    sp_au=$((sp_au + sp_used * 1024)); sp_as=$((sp_as + sp_size * 1024))
  done <<EOF
$sp_df
EOF
  for sp_disk in $sp_disks; do
    eval "sp_out=\"\$sp_out,\\\"\$sp_disk\\\":[\$sp_u_$sp_disk,\$sp_s_$sp_disk]\""
  done
  space_part="\"space\":{\"all\":[$sp_au,$sp_as]$sp_out}"
}

linux_sensors() {
  t_out=""; f_out=""
  # Split the comma list without starting a process.
  t_ifs=$IFS; IFS=,
  for t_id in $sensor_ids; do
    IFS=$t_ifs
    if [ "$t_id" = cpu ]; then
      [ -n "$s_cpu" ] && vitals_read "$s_cpu" && t_out="$t_out${t_out:+,}\"cpu\":$(vitals_tenths $((val / 100)))"
      continue
    fi
    t_i=1
    while [ "$t_i" -le "$s_n" ]; do
      eval "t_sid=\$s_id_$t_i"
      if [ "$t_sid" = "$t_id" ]; then
        eval "t_path=\$s_path_$t_i t_kind=\$s_kind_$t_i"
        if vitals_read "$t_path"; then
          case $val in ''|*[!0-9-]*) ;; *)
            if [ "$t_kind" = temp ]; then t_out="$t_out${t_out:+,}\"$t_id\":$(vitals_tenths $((val / 100)))"
            else f_out="$f_out${f_out:+,}\"$t_id\":$val"; fi ;;
          esac
        fi
        break
      fi
      t_i=$((t_i + 1))
    done
  done
  IFS=$t_ifs
  sensor_part=",\"temps\":{$t_out},\"fans\":{$f_out}"
}

linux_battery() {
  battery_part=""
  [ -n "$bat" ] || return
  b_pct=null; b_status=Unknown; b_empty=null; b_full=null
  vitals_read "$bat/capacity" && b_pct=$val
  vitals_read "$bat/status" && b_status=$val
  # Energy (µWh, µW) or charge (µAh, µA), whichever the battery exposes.
  b_now=""; b_max=""; b_rate=""
  if vitals_read "$bat/energy_now"; then b_now=$val
    vitals_read "$bat/energy_full" && b_max=$val
    vitals_read "$bat/power_now" && b_rate=$val
  elif vitals_read "$bat/charge_now"; then b_now=$val
    vitals_read "$bat/charge_full" && b_max=$val
    vitals_read "$bat/current_now" && b_rate=$val
  fi
  b_rate=${b_rate#-}
  if [ -n "$b_now" ] && [ -n "$b_rate" ] && [ "$b_rate" -gt 0 ] 2>/dev/null; then
    case $b_status in
      Discharging) b_empty=$((b_now * 60 / b_rate)) ;;
      Charging) [ -n "$b_max" ] && b_full=$(((b_max - b_now) * 60 / b_rate)) ;;
    esac
  fi
  battery_part=",\"battery\":{\"percent\":$b_pct,\"status\":\"$(printf '%s' "$b_status" | tr -cd 'A-Za-z ')\",\"toEmpty\":$b_empty,\"toFull\":$b_full}"
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
  nvsmi=$(command -v nvidia-smi 2>/dev/null)
  linux_scan_gpus
  linux_scan_battery
  linux_scan_disks
  linux_scan_sensors
  vitals_emit "{\"type\":\"hello\",\"v\":2,\"os\":\"linux\",\"osName\":\"$(vitals_json_text "$os_name")\",\"host\":\"$(vitals_json_text "$host")\",\"cores\":$cores,\"interval\":$interval,\"caps\":{\"gpu\":$(vitals_bool "$g_n"),\"disks\":$([ -n "$d_list" ] && printf true || printf false),\"sensors\":$([ -n "$s_lines" ] && printf true || printf false),\"battery\":$([ -n "$bat" ] && printf true || printf false)},\"gpus\":[$gpus_json],\"disks\":[$disks_json],\"sensors\":[$sensors_json]}"

  linux_cpu; p_u=$cpu_u; p_s=$cpu_s; p_i=$cpu_i
  linux_net; p_rx=$n_rx; p_tx=$n_tx
  linux_clock; p_clock=$clock_cs
  if vitals_has disks; then
    linux_disk_counters; p_dr=$dc_r; p_dw=$dc_w
    for p_d in $d_list; do eval "p_r_$p_d=\${dc_r_$p_d:-0} p_w_$p_d=\${dc_w_$p_d:-0}"; done
  fi
  space_due=0; space_part=""

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

    gpu_part=""; disk_part=""; sensor_part=""; battery_part=""
    vitals_has gpu && [ "$g_n" -gt 0 ] && linux_gpus
    if vitals_has disks && [ -n "$d_list" ]; then
      linux_disk_counters
      dk_per=""
      for dk in $d_list; do
        eval "dk_r=\$(( (\${dc_r_$dk:-0} - \${p_r_$dk:-0}) * 51200 / d_cs )) dk_w=\$(( (\${dc_w_$dk:-0} - \${p_w_$dk:-0}) * 51200 / d_cs ))"
        [ "$dk_r" -lt 0 ] && dk_r=0
        [ "$dk_w" -lt 0 ] && dk_w=0
        dk_per="$dk_per${dk_per:+,}\"$dk\":[$dk_r,$dk_w]"
        eval "p_r_$dk=\${dc_r_$dk:-0} p_w_$dk=\${dc_w_$dk:-0}"
      done
      dk_r=$(( (dc_r - p_dr) * 51200 / d_cs )); dk_w=$(( (dc_w - p_dw) * 51200 / d_cs ))
      [ "$dk_r" -lt 0 ] && dk_r=0
      [ "$dk_w" -lt 0 ] && dk_w=0
      p_dr=$dc_r; p_dw=$dc_w
      if [ "$clock_cs" -ge "$space_due" ]; then linux_space; space_due=$((clock_cs + 3000)); fi
      disk_part=",\"disk\":{\"read\":$dk_r,\"write\":$dk_w,\"per\":{$dk_per},$space_part}"
    fi
    vitals_has sensors && [ -n "$s_lines" ] && linux_sensors
    vitals_has battery && linux_battery

    vitals_emit "{\"type\":\"sample\",\"cpu\":$(vitals_tenths $((t_user + t_sys))),\"user\":$(vitals_tenths $t_user),\"sys\":$(vitals_tenths $t_sys),\"memUsed\":$mem_used,\"memTotal\":$mem_total,\"rx\":$r_rx,\"tx\":$r_tx,\"load\":$l_one$gpu_part$disk_part$sensor_part$battery_part}"
    p_u=$cpu_u; p_s=$cpu_s; p_i=$cpu_i; p_rx=$n_rx; p_tx=$n_tx; p_clock=$clock_cs
  done
}

# ---------------------------------------------------------------- macOS

# One iostat run per sample doubles as the wait: it prints the since-boot line,
# waits the interval, then prints the interval's cpu split and load average.
# vm_stat and netstat follow it, plus ioreg and df for the extras asked for,
# all into a single awk that prints one line of space-separated fields:
#   user sys idle load1 memUsed rxBytes txBytes gpuUtil gpuMem batPercent
#   batStatus batToEmpty batToFull batTemp diskRead diskWrite spaceSize spaceAvail
# with "-" for anything not measured.
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
    if [ "$want_gpu" = 1 ]; then echo @GPU; ioreg -r -d 1 -c IOAccelerator -k PerformanceStatistics; fi
    if [ "$want_bat" = 1 ]; then echo @BAT; ioreg -rc AppleSmartBattery; fi
    if [ "$want_disk" = 1 ]; then echo @DSK; ioreg -c IOBlockStorageDriver -r -d 1 -w0 -k Statistics; fi
    if [ "$want_space" = 1 ]; then echo @DF; df -k /; fi
  } 2>/dev/null | awk -v page="$page_size" '
    /^@VM/ { part = "vm"; next }
    /^@NET/ { part = "net"; next }
    /^@GPU/ { part = "gpu"; next }
    /^@BAT/ { part = "bat"; next }
    /^@DSK/ { part = "dsk"; next }
    /^@DF/ { part = "df"; next }
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
    part == "gpu" && gutil == "" && match($0, /"Device Utilization %"=[0-9]+/) {
      gutil = substr($0, RSTART + 23, RLENGTH - 23)
      if (match($0, /"In use system memory"=[0-9]+/)) gmem = substr($0, RSTART + 23, RLENGTH - 23)
    }
    part == "bat" && $2 == "=" {
      k = $1; gsub(/"/, "", k); bv[k] = $3
    }
    part == "dsk" && /"Statistics" = \{/ {
      if (match($0, /"Bytes \(Read\)"=[0-9]+/)) drd += substr($0, RSTART + 15, RLENGTH - 15)
      if (match($0, /"Bytes \(Write\)"=[0-9]+/)) dwr += substr($0, RSTART + 16, RLENGTH - 16)
      dsk = 1
    }
    part == "df" && $NF == "/" { dfs = $2 * 1024; dfa = $4 * 1024 }
    END {
      app = anon - purge; if (app < 0) app = 0
      bp = "-"; bs = "-"; be = "-"; bf = "-"; bt = "-"
      if (bv["MaxCapacity"] + 0 > 0) {
        bp = int(bv["CurrentCapacity"] * 100 / bv["MaxCapacity"] + 0.5)
        if (bp > 100) bp = 100
        if (bv["FullyCharged"] == "Yes") bs = "Full"
        else if (bv["IsCharging"] == "Yes") bs = "Charging"
        else if (bv["ExternalConnected"] == "Yes") bs = "NotCharging"
        else bs = "Discharging"
        if (bs == "Discharging" && bv["TimeRemaining"] + 0 > 0 && bv["TimeRemaining"] + 0 < 65535) be = bv["TimeRemaining"] + 0
        if (bs == "Charging" && bv["AvgTimeToFull"] + 0 > 0 && bv["AvgTimeToFull"] + 0 < 65535) bf = bv["AvgTimeToFull"] + 0
        if (bv["Temperature"] + 0 > 0) bt = int(bv["Temperature"] / 10)
      }
      printf "%d %d %d %s %.0f %.0f %.0f %s %s %s %s %s %s %s %s %s %s %s\n", us, sy, id, (ld == "" ? 0 : ld), (app + wired + comp) * page, rx, tx,
        (gutil == "" ? "-" : gutil), (gmem == "" ? "-" : gmem), bp, bs, be, bf, bt,
        (dsk ? sprintf("%.0f", drd) : "-"), (dsk ? sprintf("%.0f", dwr) : "-"),
        (dfs == "" ? "-" : sprintf("%.0f", dfs)), (dfa == "" ? "-" : sprintf("%.0f", dfa))
    }'
}

vitals_or_null() {
  if [ "$1" = - ]; then printf null; else printf '%s' "$1"; fi
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

  # What this Mac has: Apple GPU load from IOAccelerator, a battery from
  # AppleSmartBattery. Without root the only temperature macOS hands out is
  # the battery's; CPU and GPU temperatures and fan speeds need a helper.
  has_gpu=0; has_bat=0
  ioreg -r -d 1 -c IOAccelerator 2>/dev/null | grep -q '"Device Utilization %"' && has_gpu=1
  ioreg -rc AppleSmartBattery 2>/dev/null | awk '$1 == "\"MaxCapacity\"" && $3 + 0 > 0 { found = 1 } END { exit !found }' && has_bat=1
  gpus_json=""
  if [ "$has_gpu" = 1 ]; then
    g_name=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
    gpus_json="{\"id\":\"apple\",\"name\":\"$(vitals_json_text "${g_name:-Apple} GPU")\",\"vendor\":\"apple\",\"util\":true}"
  fi
  sensors_json=""
  [ "$has_bat" = 1 ] && sensors_json='{"id":"battery","label":"Battery temperature","kind":"temp"}'
  vitals_emit "{\"type\":\"hello\",\"v\":2,\"os\":\"macos\",\"osName\":\"$(vitals_json_text "$os_name")\",\"host\":\"$(vitals_json_text "$host")\",\"cores\":$cores,\"interval\":$wait_s,\"caps\":{\"gpu\":$(vitals_bool $has_gpu),\"disks\":true,\"sensors\":$(vitals_bool $has_bat),\"battery\":$(vitals_bool $has_bat)},\"gpus\":[$gpus_json],\"disks\":[],\"sensors\":[$sensors_json],\"sensorsNote\":\"CPU and GPU temperatures and fan speeds need root on macOS\"}"

  want_gpu=0; want_bat=0; want_disk=0; want_space=0; use_bat=0
  vitals_has gpu && [ "$has_gpu" = 1 ] && want_gpu=1
  if [ "$has_bat" = 1 ]; then
    vitals_has battery && use_bat=1
    vitals_has sensors && case ",$sensor_ids," in *,battery,*) use_bat=1 ;; esac
  fi
  want_bat=$use_bat
  vitals_has disks && want_disk=1 && want_space=1
  # Space and the battery change slowly: read them every 30 and 10 seconds,
  # which keeps two of the ioreg/df runs out of most samples.
  space_every=$(( (30 + wait_s - 1) / wait_s ))
  bat_every=$(( (10 + wait_s - 1) / wait_s ))
  space_count=0; space_size=-; space_avail=-
  bat_count=0; bat_fields="- - - - -"

  # shellcheck disable=SC2046
  set -- $(darwin_sample nowait)
  p_rx=${6:-0}; p_tx=${7:-0}; p_dr=${15:--}; p_dw=${16:--}
  [ "$want_space" = 1 ] && { space_size=${17:--}; space_avail=${18:--}; }
  [ "$want_bat" = 1 ] && bat_fields="${10} ${11} ${12} ${13} ${14}"
  while :; do
    want_space=0; want_bat=0
    if vitals_has disks; then
      space_count=$((space_count + 1))
      [ "$space_count" -ge "$space_every" ] && { want_space=1; space_count=0; }
    fi
    if [ "$use_bat" = 1 ]; then
      bat_count=$((bat_count + 1))
      [ "$bat_count" -ge "$bat_every" ] && { want_bat=1; bat_count=0; }
    fi
    # shellcheck disable=SC2046
    set -- $(darwin_sample wait)
    [ $# -eq 18 ] || { sleep "$wait_s"; continue; }
    if [ "$want_bat" = 1 ]; then bat_fields="${10} ${11} ${12} ${13} ${14}"; fi
    # shellcheck disable=SC2086
    set -- $1 $2 $3 $4 $5 $6 $7 $8 $9 $bat_fields ${15} ${16} ${17} ${18}
    d_rx=$(($6 - p_rx)); d_tx=$(($7 - p_tx))
    [ "$d_rx" -lt 0 ] && d_rx=0
    [ "$d_tx" -lt 0 ] && d_tx=0
    used=$5
    [ "$used" -gt "$mem_total" ] && used=$mem_total
    extra=""
    if [ "$want_gpu" = 1 ]; then
      extra="$extra,\"gpus\":[{\"id\":\"apple\",\"util\":$(vitals_or_null "$8"),\"mhz\":null,\"temp\":null,\"memUsed\":$(vitals_or_null "$9"),\"memTotal\":null}]"
    fi
    if vitals_has battery && [ "$has_bat" = 1 ]; then
      b_status=${11}; [ "$b_status" = NotCharging ] && b_status="Not charging"
      extra="$extra,\"battery\":{\"percent\":$(vitals_or_null "${10}"),\"status\":\"$b_status\",\"toEmpty\":$(vitals_or_null "${12}"),\"toFull\":$(vitals_or_null "${13}")}"
    fi
    if vitals_has sensors; then
      t_out=""
      [ "${14}" != - ] && case ",$sensor_ids," in *,battery,*) t_out="\"battery\":$(vitals_tenths "${14}")" ;; esac
      extra="$extra,\"temps\":{$t_out},\"fans\":{}"
    fi
    if vitals_has disks && [ "${15}" != - ]; then
      dk_r=0; dk_w=0
      if [ "$p_dr" != - ]; then
        dk_r=$(( (${15} - p_dr) / wait_s )); dk_w=$(( (${16} - p_dw) / wait_s ))
        [ "$dk_r" -lt 0 ] && dk_r=0
        [ "$dk_w" -lt 0 ] && dk_w=0
      fi
      p_dr=${15}; p_dw=${16}
      if [ "${17}" != - ]; then space_size=${17}; space_avail=${18}; fi
      space=""
      [ "$space_size" != - ] && space=",\"space\":{\"all\":[$((space_size - space_avail)),$space_size]}"
      extra="$extra,\"disk\":{\"read\":$dk_r,\"write\":$dk_w,\"per\":{}$space}"
    fi
    vitals_emit "{\"type\":\"sample\",\"cpu\":$(($1 + $2)),\"user\":$1,\"sys\":$2,\"memUsed\":$used,\"memTotal\":$mem_total,\"rx\":$((d_rx / wait_s)),\"tx\":$((d_tx / wait_s)),\"load\":$4$extra}"
    p_rx=$6; p_tx=$7
  done
}

main() {
  interval=${1:-2}
  case $interval in
    ''|*[!0-9.]*|.*|*.*.*) interval=2 ;;
  esac
  extras=$(printf '%s' "${2:-}" | tr -cd 'a-z,')
  sensor_ids=$(printf '%s' "${3:-cpu}" | tr -cd 'A-Za-z0-9_.:/,-')
  export LC_ALL=C
  case $(uname -s 2>/dev/null) in
    Linux) linux_main ;;
    Darwin) darwin_main ;;
    *) vitals_fail "unsupported system: $(uname -s 2>/dev/null)" ;;
  esac
}

main "$@" < /dev/null; exit
