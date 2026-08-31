#!/usr/bin/env bash
# hyn-view :: cpu / memory / disk / process / system collectors
#
# Two things here are deliberately unlike htop, because this is aimed at rented
# 24/7 servers rather than laptops:
#
#   * steal% is a first-class number. On a VPS it is the difference between "my
#     node is slow" and "my neighbour is loud", and htop hides it in a submenu.
#   * PSI (/proc/pressure) is collected alongside load average. Load average
#     counts runnable tasks; PSI measures time actually lost to contention,
#     which is the number that correlates with missed work.

CLK_TCK=100
PAGE_SIZE=4096
CPU_COUNT=1
CPU_MODEL='unknown'
KERNEL='' HOSTNAME_S='' DISTRO=''

# Two forks, once, at startup. Hardcoding 100/4096 is right on virtually every
# amd64 Ubuntu box but wrong often enough (arm64 pages) to matter for RSS.
collect_init() {
  local v
  if have getconf; then
    v=$(getconf CLK_TCK 2>/dev/null) && [[ $v =~ ^[0-9]+$ ]] && CLK_TCK=$v
    v=$(getconf PAGESIZE 2>/dev/null) && [[ $v =~ ^[0-9]+$ ]] && PAGE_SIZE=$v
  fi
  readval KERNEL "$HYN_PROC/sys/kernel/osrelease"
  readval HOSTNAME_S "$HYN_PROC/sys/kernel/hostname"
  local line
  if [[ -r /etc/os-release ]]; then
    while IFS= read -r line; do
      case $line in
        PRETTY_NAME=*)
          DISTRO=${line#*=}
          DISTRO=${DISTRO%\"}
          DISTRO=${DISTRO#\"}
          break ;;
      esac
    done </etc/os-release
  fi
  if [[ -r $HYN_PROC/cpuinfo ]]; then
    while IFS= read -r line; do
      case $line in
        'model name'*) [[ $CPU_MODEL == unknown ]] && CPU_MODEL=${line#*: } ;;
        'Model'* | 'Hardware'*) [[ $CPU_MODEL == unknown ]] && CPU_MODEL=${line#*: } ;;
      esac
    done <"$HYN_PROC/cpuinfo"
  fi
  # Trim the marketing noise so the header has room for facts.
  CPU_MODEL=${CPU_MODEL//(R)/}
  CPU_MODEL=${CPU_MODEL//(TM)/}
  CPU_MODEL=${CPU_MODEL//(tm)/}
  CPU_MODEL=${CPU_MODEL//CPU /}
  CPU_MODEL=${CPU_MODEL//Processor/}
  while [[ $CPU_MODEL == *'  '* ]]; do CPU_MODEL=${CPU_MODEL//  / }; done
  CPU_MODEL=${CPU_MODEL# }
  CPU_MODEL=${CPU_MODEL% }
  thermal_discover
  cpufreq_discover
  power_discover
  return 0
}

# ---------------------------------------------------------------------------
# cpu
# ---------------------------------------------------------------------------
CPU_PCT=0 CPU_USER=0 CPU_SYS=0 CPU_IOWAIT=0 CPU_STEAL=0 CPU_IRQ=0
CPU_CTXT_R=0 CPU_INTR_R=0 CPU_FORK_R=0 PROCS_RUN=0 PROCS_BLK=0
LOAD1='' LOAD5='' LOAD15=''
declare -a CORE_PCT=()
declare -a CPU_HIST=()
declare -A _CPU_PREV=()

# Percent of one field's delta over the total delta. Sets SHARE rather than
# printing: this runs five times per tick and $( ) would fork five subshells.
SHARE=0
_cpu_share() {
  local d=$1 t=$2
  if ((t <= 0 || d < 0)); then SHARE=0; else SHARE=$((d * 100 / t)); fi
  return 0
}

_CPU_SEEDED=0
cpu_sample() {
  local ms=$1 label user nice sys idle iowait irq softirq steal rest
  local total idle_all dt didle key n=0
  CORE_PCT=()
  while read -r label user nice sys idle iowait irq softirq steal rest; do
    case $label in
      cpu | cpu[0-9]*) ;;
      ctxt) delta_rate cpu:ctxt "$user" "$ms"; CPU_CTXT_R=$DELTA_RATE; continue ;;
      intr) delta_rate cpu:intr "$user" "$ms"; CPU_INTR_R=$DELTA_RATE; continue ;;
      processes) delta_rate cpu:forks "$user" "$ms"; CPU_FORK_R=$DELTA_RATE; continue ;;
      procs_running) PROCS_RUN=$user; continue ;;
      procs_blocked) PROCS_BLK=$user; continue ;;
      *) continue ;;
    esac
    [[ $steal =~ ^[0-9]+$ ]] || steal=0
    total=$((user + nice + sys + idle + iowait + irq + softirq + steal))
    idle_all=$((idle + iowait))
    key=$label
    dt=$((total - ${_CPU_PREV[$key.t]:-0}))
    didle=$((idle_all - ${_CPU_PREV[$key.i]:-0}))
    _CPU_PREV[$key.t]=$total
    _CPU_PREV[$key.i]=$idle_all
    local pct=0
    # Until we have two samples, every "delta" is really a since-boot total.
    # Reporting that as current load would open the tool on a lie, so the first
    # tick reports zero and the second is the first real measurement.
    if ((_CPU_SEEDED && dt > 0)); then
      pct=$(((dt - didle) * 100 / dt))
      ((pct < 0)) && pct=0
      ((pct > 100)) && pct=100
    fi
    if [[ $label == cpu ]]; then
      CPU_PCT=$pct
      if ((_CPU_SEEDED)); then
        _cpu_share $((user + nice - ${_CPU_PREV[$key.u]:-0})) "$dt"; CPU_USER=$SHARE
        _cpu_share $((sys - ${_CPU_PREV[$key.s]:-0})) "$dt"; CPU_SYS=$SHARE
        _cpu_share $((iowait - ${_CPU_PREV[$key.w]:-0})) "$dt"; CPU_IOWAIT=$SHARE
        _cpu_share $((steal - ${_CPU_PREV[$key.st]:-0})) "$dt"; CPU_STEAL=$SHARE
        _cpu_share $((irq + softirq - ${_CPU_PREV[$key.q]:-0})) "$dt"; CPU_IRQ=$SHARE
      else
        CPU_USER=0 CPU_SYS=0 CPU_IOWAIT=0 CPU_STEAL=0 CPU_IRQ=0
      fi
      _CPU_PREV[$key.u]=$((user + nice))
      _CPU_PREV[$key.s]=$sys
      _CPU_PREV[$key.w]=$iowait
      _CPU_PREV[$key.st]=$steal
      _CPU_PREV[$key.q]=$((irq + softirq))
      ring_push CPU_HIST "$pct"
    else
      CORE_PCT+=("$pct")
      ((n++))
    fi
  done <"$HYN_PROC/stat"
  ((n > 0)) && CPU_COUNT=$n
  read -r LOAD1 LOAD5 LOAD15 _ <"$HYN_PROC/loadavg" 2>/dev/null
  _CPU_SEEDED=1
  return 0
}

# Highest core frequency in MHz -- one number that shows whether the host is
# actually giving us the clock we pay for.
CPU_MHZ=''
cpu_freq() {
  local f v max=0
  for f in "$HYN_SYS/devices/system/cpu"/cpu[0-9]*/cpufreq/scaling_cur_freq; do
    [[ -r $f ]] || continue
    readval v "$f" || continue
    ((v > max)) && max=$v
  done
  if ((max > 0)); then CPU_MHZ=$((max / 1000)); return 0; fi
  local line
  while IFS= read -r line; do
    case $line in
      'cpu MHz'*) v=${line#*: }; CPU_MHZ=${v%%.*}; return 0 ;;
    esac
  done <"$HYN_PROC/cpuinfo" 2>/dev/null
  return 1
}

# ---------------------------------------------------------------------------
# temperature
# ---------------------------------------------------------------------------
THERMAL_PATH='' CPU_TEMP=''
thermal_discover() {
  local d name
  # Prefer a real CPU sensor over whatever thermal_zone0 happens to be, which on
  # many boards is the chipset or an ACPI fiction.
  for d in "$HYN_SYS/class/hwmon"/hwmon*; do
    [[ -r $d/name ]] || continue
    readval name "$d/name" || continue
    case $name in
      coretemp | k10temp | zenpower | cpu_thermal | soc_thermal)
        [[ -r $d/temp1_input ]] && { THERMAL_PATH=$d/temp1_input; return 0; } ;;
    esac
  done
  for d in "$HYN_SYS/class/thermal"/thermal_zone*; do
    [[ -r $d/type ]] || continue
    readval name "$d/type" || continue
    case $name in
      x86_pkg_temp | cpu-thermal | cpu_thermal | acpitz)
        [[ -r $d/temp ]] && { THERMAL_PATH=$d/temp; return 0; } ;;
    esac
  done
  return 1
}

thermal_read() {
  CPU_TEMP=''
  [[ -n $THERMAL_PATH ]] || return 1
  local v
  readval v "$THERMAL_PATH" || return 1
  [[ $v =~ ^-?[0-9]+$ ]] || return 1
  CPU_TEMP=$((v / 1000))
  return 0
}

# ---------------------------------------------------------------------------
# clock speed
# ---------------------------------------------------------------------------
# Current core frequency in MHz, or empty when the platform will not say.
#
# cpufreq is preferred over /proc/cpuinfo: on many server parts cpuinfo's
# "cpu MHz" reports the nominal base clock and never moves, which would draw a
# perfectly flat line and imply the governor is doing nothing. scaling_cur_freq
# is the actual current frequency, in kHz.
#
# A VM usually exposes neither, so an empty result is a normal outcome and must
# serialise as null rather than 0 -- graphing 0 MHz would be inventing a reading.
CPU_MHZ=''
CPUFREQ_PATH=''
cpufreq_discover() {
  local c
  for c in "$HYN_SYS/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq" \
           "$HYN_SYS/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq"; do
    [[ -r $c ]] && { CPUFREQ_PATH=$c; return 0; }
  done
  return 1
}

cpu_freq_read() {
  CPU_MHZ=''
  local v
  if [[ -n $CPUFREQ_PATH ]] && readval v "$CPUFREQ_PATH"; then
    [[ $v =~ ^[0-9]+$ ]] || return 1
    CPU_MHZ=$((v / 1000))
    return 0
  fi
  # Fall back to the first "cpu MHz" line. Decimal, so parse then drop the
  # fraction -- a tenth of a MHz is not a number anyone acts on.
  [[ -r $HYN_PROC/cpuinfo ]] || return 1
  local line
  while IFS= read -r line; do
    case $line in
      'cpu MHz'*)
        v=${line#*: }
        parse_fixed3_v "$v"
        CPU_MHZ=$((FIX3 / 1000))
        return 0 ;;
    esac
  done <"$HYN_PROC/cpuinfo"
  return 1
}

# Per-core frequency, the governor, and the range the hardware admits. Useful
# beyond curiosity: a box pinned at its minimum multiplier under load is being
# thermally or administratively throttled, which looks like "the server is slow"
# and is invisible if you only sample one core.
declare -a CPU_CORE_MHZ=()
CPU_MHZ_MIN='' CPU_MHZ_MAX='' CPU_GOVERNOR='' CPU_MHZ_AVG=''
cpu_freq_all() {
  CPU_CORE_MHZ=() CPU_MHZ_MIN='' CPU_MHZ_MAX='' CPU_GOVERNOR='' CPU_MHZ_AVG=''
  local d v sum=0 n=0
  for d in "$HYN_SYS/devices/system/cpu"/cpu[0-9]*; do
    [[ -r $d/cpufreq/scaling_cur_freq ]] || continue
    readval v "$d/cpufreq/scaling_cur_freq" || continue
    [[ $v =~ ^[0-9]+$ ]] || continue
    v=$((v / 1000))
    CPU_CORE_MHZ+=("$v")
    sum=$((sum + v))
    n=$((n + 1))
  done
  ((n > 0)) && CPU_MHZ_AVG=$((sum / n))
  local base="$HYN_SYS/devices/system/cpu/cpu0/cpufreq"
  if readval v "$base/cpuinfo_min_freq"; then
    [[ $v =~ ^[0-9]+$ ]] && CPU_MHZ_MIN=$((v / 1000))
  fi
  if readval v "$base/cpuinfo_max_freq"; then
    [[ $v =~ ^[0-9]+$ ]] && CPU_MHZ_MAX=$((v / 1000))
  fi
  readval CPU_GOVERNOR "$base/scaling_governor" || CPU_GOVERNOR=''
  ((n > 0))
}

# ---------------------------------------------------------------------------
# every temperature sensor
# ---------------------------------------------------------------------------
# thermal_read picks the one sensor worth putting in the CPU panel. This reads
# them all, because on real hardware the interesting reading is often not the
# package: an NVMe at 70C or an ambient sensor climbing is what explains a fan
# that will not stop, and neither shows up as "CPU temperature".
#
# Labelled by whatever the platform calls them, deduplicated, and skipped
# entirely when a value is outside plausible physical range -- a sensor reading
# -274C or 3000C is a driver bug, not a measurement.
declare -A SENSORS=()
sensors_read() {
  SENSORS=()
  local d f label chip v key
  for d in "$HYN_SYS/class/hwmon"/hwmon*; do
    [[ -d $d ]] || continue
    readval chip "$d/name" || chip=${d##*/}
    for f in "$d"/temp*_input; do
      [[ -r $f ]] || continue
      readval v "$f" || continue
      [[ $v =~ ^-?[0-9]+$ ]] || continue
      v=$((v / 1000))
      ((v < -50 || v > 200)) && continue
      label=''
      readval label "${f%_input}_label" 2>/dev/null || label=''
      if [[ -z $label ]]; then
        key=${f##*/}
        label="$chip ${key%_input}"
      else
        label="$chip $label"
      fi
      SENSORS[$label]=$v
    done
  done
  # thermal_zone covers SoCs and VMs that expose no hwmon at all.
  for d in "$HYN_SYS/class/thermal"/thermal_zone*; do
    [[ -r $d/temp ]] || continue
    readval v "$d/temp" || continue
    [[ $v =~ ^-?[0-9]+$ ]] || continue
    v=$((v / 1000))
    ((v < -50 || v > 200)) && continue
    readval label "$d/type" || label=${d##*/}
    [[ -v SENSORS[$label] ]] || SENSORS[$label]=$v
  done
  ((${#SENSORS[@]} > 0))
}

# ---------------------------------------------------------------------------
# power
# ---------------------------------------------------------------------------
# "Power input" is three different measurements on Linux, and which one exists
# depends entirely on the hardware. All three are read, because on any given box
# one or two of them are simply absent:
#
#   1. hwmon `power*_input` -- instantaneous microwatts. On a server with a PMBus
#      PSU driver or a BMC bridged into hwmon this is the real answer: what the
#      chassis is drawing from the wall. It is also the rarest.
#   2. Intel/AMD RAPL under /sys/class/powercap -- `energy_uj`, a monotonic
#      microjoule COUNTER, not a reading. Differentiating it gives package and
#      DRAM watts. Nearly every bare-metal x86 server has this and no VM does.
#   3. /sys/class/power_supply -- mains present, and a battery or USB-HID UPS
#      with its charge and state. On a relay node behind a domestic link "the box
#      is running on battery" is the most actionable line this tool can print.
#
# Everything is kept in DECIWATTS (tenths of a watt) as integers, the same
# fixed-point approach used for load and PSI, so there is no floating point
# anywhere and 0.1 W of resolution survives for an idle CPU package.
#
# An absent sensor stays empty and serialises as null. A server that cannot
# measure its own draw is a normal outcome; a plotted 0 W is a lie about a
# machine that is plainly running.
PWR_CPU_DW='' PWR_DRAM_DW='' PWR_INPUT_DW='' PWR_INPUT_SRC=''
PWR_AC='' PWR_BAT_PCT='' PWR_BAT_STATUS='' PWR_BAT_DW=''
declare -A PWR_RAILS=()
declare -a PWR_RAPL=()
declare -A PWR_RAPL_NAME=()
declare -A PWR_RAPL_MAX=()
declare -a PWR_HWMON=()
# Previous energy counter readings, keyed by domain path.
#
# Declared here rather than reusing net.sh's _PREV, which is what this used to do.
# That worked only because every entry point happens to source net.sh before
# collect.sh: without it, `_PREV[$key]=...` on an undeclared name is an INDEXED
# array assignment, the key is evaluated as arithmetic, and the process aborts
# under `set -u` with "rapl: unbound variable". A collector must not depend on
# another module's globals for that.
declare -A _PWR_PREV=()

# Discovery is done once at boot, not per tick: walking /sys/class/powercap and
# every hwmon directory is dozens of reads, and the answer cannot change without
# a driver being loaded.
power_discover() {
  PWR_RAPL=() PWR_RAPL_NAME=() PWR_RAPL_MAX=() PWR_HWMON=()
  local d name f mx
  # RAPL domains. intel-rapl:0 is the package, intel-rapl:0:N its sub-domains
  # (core, uncore, dram). The name file is what says which is which; the
  # directory numbering is not stable across parts.
  for d in "$HYN_SYS/class/powercap"/*; do
    [[ -r $d/energy_uj ]] || continue
    readval name "$d/name" || name=${d##*/}
    PWR_RAPL+=("$d")
    PWR_RAPL_NAME[$d]=$name
    # Needed to unwrap the counter. RAPL's energy register is narrow enough to
    # roll over in about a minute on a busy part, so treating a backwards delta
    # as "no data" (which is right for a 64-bit network counter) would silently
    # drop a sample every wrap.
    if readval mx "$d/max_energy_range_uj" && [[ $mx =~ ^[0-9]+$ ]]; then
      PWR_RAPL_MAX[$d]=$mx
    else
      PWR_RAPL_MAX[$d]=0
    fi
  done
  # hwmon power rails.
  for d in "$HYN_SYS/class/hwmon"/hwmon*; do
    [[ -d $d ]] || continue
    for f in "$d"/power*_input; do
      [[ -r $f ]] || continue
      PWR_HWMON+=("$f")
    done
  done
  ((${#PWR_RAPL[@]} > 0 || ${#PWR_HWMON[@]} > 0)) || return 1
  return 0
}

# power_energy_rate_dw <key> <energy_uj> <max_uj> <ms> -> PWR_RATE_DW
#
# Microjoules over milliseconds is milliwatts, so deciwatts is d/(ms*100).
# Kept separate from delta_rate because of the wrap: with a known register width
# a backwards step is a rollover and the true delta is (max - prev) + cur.
PWR_RATE_DW=0
power_energy_rate_dw() {
  local key=$1 cur=$2 max=$3 ms=$4 prev d
  PWR_RATE_DW=''
  prev=${_PWR_PREV[$key]:-}
  _PWR_PREV[$key]=$cur
  [[ -z $prev ]] && return 1
  ((ms <= 0)) && return 1
  d=$((cur - prev))
  if ((d < 0)); then
    # Rolled over. Without a width to unwrap against there is no honest answer,
    # so say nothing rather than emit a spike or a zero.
    ((max > 0)) || return 1
    d=$((max - prev + cur))
    ((d < 0)) && return 1
  fi
  PWR_RATE_DW=$((d / (ms * 100)))
  # A single interval cannot draw a megawatt. This catches a driver resetting
  # its counter to something arbitrary, which reads as an enormous delta.
  ((PWR_RATE_DW > 100000)) && { PWR_RATE_DW=''; return 1; }
  return 0
}

# power_read <interval-ms>
power_read() {
  local ms=${1:-0}
  PWR_CPU_DW='' PWR_DRAM_DW='' PWR_INPUT_DW='' PWR_INPUT_SRC=''
  PWR_AC='' PWR_BAT_PCT='' PWR_BAT_STATUS='' PWR_BAT_DW=''
  PWR_RAILS=()
  cfg_on power_track || return 1

  local d name v label f chip
  # --- RAPL: counters, so they need the interval ------------------------------
  for d in "${PWR_RAPL[@]}"; do
    readval v "$d/energy_uj" || continue
    [[ $v =~ ^[0-9]+$ ]] || continue
    power_energy_rate_dw "rapl:$d" "$v" "${PWR_RAPL_MAX[$d]:-0}" "$ms" || continue
    name=${PWR_RAPL_NAME[$d]:-${d##*/}}
    PWR_RAILS[$name]=$PWR_RATE_DW
    case $name in
      package*)
        # Sum the packages: a two-socket box has two, and one of them alone is
        # not the machine's CPU power.
        PWR_CPU_DW=$((${PWR_CPU_DW:-0} + PWR_RATE_DW)) ;;
      dram) PWR_DRAM_DW=$((${PWR_DRAM_DW:-0} + PWR_RATE_DW)) ;;
      psys)
        # psys ("platform") is the whole SoC package power where the firmware
        # exposes it, which is much closer to chassis input than the CPU package
        # alone. Preferred over RAPL package below, still beaten by a real PSU.
        PWR_INPUT_DW=$PWR_RATE_DW PWR_INPUT_SRC='rapl-psys' ;;
    esac
  done

  # --- hwmon: instantaneous readings ------------------------------------------
  for f in "${PWR_HWMON[@]}"; do
    readval v "$f" || continue
    [[ $v =~ ^[0-9]+$ ]] || continue
    # Microwatts to deciwatts. A 20 kW reading is a broken driver, not a server.
    v=$((v / 100000))
    ((v < 0 || v > 200000)) && continue
    d=${f%/*}
    readval chip "$d/name" || chip=${d##*/}
    label=''
    readval label "${f%_input}_label" 2>/dev/null || label=''
    [[ -n $label ]] || label=${f##*/}
    [[ -n $label ]] && label="$chip $label"
    PWR_RAILS[$label]=$v
    # A rail the firmware calls "input" is the number this whole feature is
    # about, and it outranks anything derived from a counter.
    case ${label,,} in
      *input*)
        if [[ $PWR_INPUT_SRC != hwmon-input ]] || ((v > ${PWR_INPUT_DW:-0})); then
          PWR_INPUT_DW=$v PWR_INPUT_SRC='hwmon-input'
        fi ;;
    esac
  done

  # --- mains, battery, UPS ----------------------------------------------------
  local ps type online cap st
  for ps in "$HYN_SYS/class/power_supply"/*; do
    [[ -d $ps ]] || continue
    readval type "$ps/type" || continue
    case $type in
      Mains | USB | UPS)
        if readval online "$ps/online" && [[ $online =~ ^[01]$ ]]; then
          # Any live source counts as mains present: a box with two PSUs has two
          # entries and one of them being offline is not a power cut.
          [[ $online == 1 ]] && PWR_AC=1 || PWR_AC=${PWR_AC:-0}
        fi ;;
    esac
    case $type in
      Battery | UPS)
        readval cap "$ps/capacity" && [[ $cap =~ ^[0-9]+$ ]] && ((cap <= 100)) && PWR_BAT_PCT=$cap
        readval st "$ps/status" && [[ -n $st ]] && PWR_BAT_STATUS=$st
        if readval v "$ps/power_now" && [[ $v =~ ^-?[0-9]+$ ]]; then
          ((v < 0)) && v=$((-v))
          PWR_BAT_DW=$((v / 100000))
        fi ;;
    esac
  done

  # Last resort for "input": the CPU package plus DRAM is not chassis power, and
  # must not be presented as if it were -- hence the source label travelling with
  # the number everywhere it is displayed or sent.
  if [[ -z $PWR_INPUT_DW && -n $PWR_CPU_DW ]]; then
    PWR_INPUT_DW=$((PWR_CPU_DW + ${PWR_DRAM_DW:-0}))
    PWR_INPUT_SRC='rapl-cpu'
  fi
  [[ -n $PWR_INPUT_DW || -n $PWR_CPU_DW || -n $PWR_AC || -n $PWR_BAT_PCT ]]
}

# Deciwatts to a decimal watt string, for anything that leaves this process --
# JSON, the portal, the daily report. An empty input stays empty so the caller's
# null handling takes over: 0 W is a claim about the machine that no absent
# sensor entitles us to make.
power_watts() {
  local dw=${1:-}
  [[ $dw =~ ^-?[0-9]+$ ]] || { printf ''; return 1; }
  fmt_fixed_v "$dw" 10 1
  printf '%s' "$FMT_OUT"
  return 0
}

# What the number means, in the two words a panel header has room for. Presented
# next to every reading because "118 W" from a PSU and "42 W" from a CPU counter
# are not the same claim about a machine.
power_src_label() {
  case ${1:-} in
    hwmon-input) printf 'psu' ;;
    rapl-psys) printf 'platform' ;;
    rapl-cpu) printf 'cpu+dram' ;;
    *) printf '' ;;
  esac
}

# Total process count. /proc/loadavg's fourth field is running/total, which is
# one small read -- counting /proc/<pid> directories would be hundreds of stats.
PROC_TOTAL=''
proc_count_read() {
  PROC_TOTAL=''
  [[ -r $HYN_PROC/loadavg ]] || return 1
  local -a f=()
  # shellcheck disable=SC2207
  f=($(<"$HYN_PROC/loadavg")) 2>/dev/null || return 1
  local pair=${f[3]:-}
  [[ $pair == */* ]] || return 1
  PROC_TOTAL=${pair#*/}
  [[ $PROC_TOTAL =~ ^[0-9]+$ ]] || { PROC_TOTAL=''; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# pressure stall information
# ---------------------------------------------------------------------------
# avg10, as an integer percent x100. PSI is the honest contention metric: it
# reports time tasks spent stalled, so 0 means healthy regardless of load.
declare -A PSI=()
psi_sample() {
  local res kind rest tok k v
  local -a f=()
  PSI=()
  for res in cpu memory io; do
    [[ -r $HYN_PROC/pressure/$res ]] || continue
    while read -r kind rest; do
      f=($rest)
      for tok in "${f[@]}"; do
        k=${tok%%=*} v=${tok#*=}
        [[ $k == avg10 ]] || continue
        parse_fixed3_v "$v"
        PSI[$res.$kind]=$((FIX3 / 10))
      done
    done <"$HYN_PROC/pressure/$res"
  done
  return 0
}

# ---------------------------------------------------------------------------
# memory
# ---------------------------------------------------------------------------
MEM_TOTAL=0 MEM_AVAIL=0 MEM_USED=0 MEM_PCT=0 MEM_CACHE=0 MEM_BUF=0
SWAP_TOTAL=0 SWAP_USED=0 SWAP_PCT=0 MEM_DIRTY=0 MEM_SHMEM=0 MEM_SRECL=0
MEM_COMMIT=0
declare -a MEM_HIST=()
mem_sample() {
  local line key val free=0 cached=0 swapfree=0
  while IFS= read -r line; do
    key=${line%%:*}
    val=${line#*:}
    val=${val// /}
    val=${val%kB}
    [[ $val =~ ^[0-9]+$ ]] || continue
    case $key in
      MemTotal) MEM_TOTAL=$((val * 1024)) ;;
      MemFree) free=$((val * 1024)) ;;
      MemAvailable) MEM_AVAIL=$((val * 1024)) ;;
      Buffers) MEM_BUF=$((val * 1024)) ;;
      Cached) cached=$((val * 1024)) ;;
      SReclaimable) MEM_SRECL=$((val * 1024)) ;;
      Shmem) MEM_SHMEM=$((val * 1024)) ;;
      Dirty) MEM_DIRTY=$((val * 1024)) ;;
      SwapTotal) SWAP_TOTAL=$((val * 1024)) ;;
      SwapFree) swapfree=$((val * 1024)) ;;
      Committed_AS) MEM_COMMIT=$((val * 1024)) ;;
    esac
  done <"$HYN_PROC/meminfo"
  # MemAvailable is the kernel's own estimate and the only honest basis for
  # "used". MemTotal-MemFree counts reclaimable page cache as consumed, which
  # makes a healthy server look like it is out of memory.
  ((MEM_AVAIL == 0)) && MEM_AVAIL=$((free + MEM_BUF + cached))
  MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
  ((MEM_USED < 0)) && MEM_USED=0
  MEM_CACHE=$((cached + MEM_SRECL - MEM_SHMEM))
  ((MEM_CACHE < 0)) && MEM_CACHE=0
  MEM_PCT=0
  ((MEM_TOTAL > 0)) && MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
  SWAP_USED=$((SWAP_TOTAL - swapfree))
  ((SWAP_USED < 0)) && SWAP_USED=0
  SWAP_PCT=0
  ((SWAP_TOTAL > 0)) && SWAP_PCT=$((SWAP_USED * 100 / SWAP_TOTAL))
  ring_push MEM_HIST "$MEM_PCT"
  return 0
}

# ---------------------------------------------------------------------------
# disk i/o + usage
# ---------------------------------------------------------------------------
declare -a DISKS=()
declare -A DISK_RD=() DISK_WR=() DISK_UTIL=() DISK_INFLIGHT=()
declare -A DISK_AWAIT=()

# Whole devices only: /sys/block/<name> exists for disks but not partitions, so
# this filters sda1/loop/dm noise without a hardcoded name blacklist.
disk_sample() {
  local ms=$1 line name rest
  local -a f=()
  DISKS=()
  while IFS= read -r line; do
    f=($line)
    ((${#f[@]} < 14)) && continue
    name=${f[2]}
    [[ -d $HYN_SYS/block/$name ]] || continue
    case $name in loop* | ram* | zram*) continue ;; esac
    DISKS+=("$name")
    delta_rate "drd:$name" $((${f[5]} * 512)) "$ms"; DISK_RD[$name]=$DELTA_RATE
    delta_rate "dwr:$name" $((${f[9]} * 512)) "$ms"; DISK_WR[$name]=$DELTA_RATE
    delta_rate "dio:$name" "${f[12]}" "$ms"
    local util=0
    ((ms > 0)) && util=$((DELTA_RAW * 100 / ms))
    ((util > 100)) && util=100
    DISK_UTIL[$name]=$util
    DISK_INFLIGHT[$name]=${f[11]}
    # Mean service time: total ms spent on reads+writes over ops completed.
    delta_rate "dms:$name" $((${f[6]} + ${f[10]})) "$ms"
    local msd=$DELTA_RAW
    delta_rate "dop:$name" $((${f[3]} + ${f[7]})) "$ms"
    if ((DELTA_RAW > 0)); then DISK_AWAIT[$name]=$((msd * 100 / DELTA_RAW)); else DISK_AWAIT[$name]=0; fi
  done <"$HYN_PROC/diskstats"
  return 0
}

# Free space has no /proc source -- statfs is a syscall bash cannot make. One
# `df` on a slow cadence is the honest cost; cached between refreshes.
#
# The filtering matters more than it looks. A stock Ubuntu server mounts every
# installed snap as a read-only squashfs loop device at /snap/..., and squashfs
# is *always* 100% full by definition. Without this filter a box with twenty
# snaps shows twenty filesystems on the dashboard and fires twenty critical
# "disk full" alerts that can never be cleared. /proc/mounts is the authority on
# type and options, so pair it with df rather than trying to guess from df alone.
declare -a MOUNTS=()
declare -A MP_PCT=() MP_USED=() MP_SIZE=() MP_AVAIL=() MP_FSTYPE=()
DF_LAST=0

# Filesystems that represent real, writable storage someone can run out of.
_FS_REAL=' ext2 ext3 ext4 xfs btrfs zfs f2fs jfs reiserfs ufs vfat exfat ntfs ntfs3 nfs nfs4 cifs smbfs virtiofs apfs hfs '

# Builds the allowlist of mount points worth reporting, in _MP_OK.
declare -A _MP_OK=()
_disk_scan_mounts() {
  local dev mp fstype opts rest pat skip
  _MP_OK=()
  [[ -r $HYN_PROC/mounts ]] || return 1
  while read -r dev mp fstype opts rest; do
    [[ -n $mp && -n $fstype ]] || continue
    [[ $_FS_REAL == *" $fstype "* ]] || continue
    # Read-only means nothing can fill it up. That is every snap.
    case ,$opts, in
      *,ro,*) continue ;;
    esac
    skip=0
    local IFS=,
    for pat in ${CFG[hide_mount]}; do
      [[ -z $pat ]] && continue
      [[ $mp == "$pat" || $mp == "$pat"* ]] && { skip=1; break; }
    done
    unset IFS
    ((skip)) && continue
    # /proc/mounts escapes spaces and friends as octal; decode so the key
    # matches what df reports.
    mp=${mp//\\040/ }
    mp=${mp//\\011/	}
    _MP_OK[$mp]=$fstype
  done <"$HYN_PROC/mounts"
  return 0
}

disk_usage() {
  local force=${1:-0} now
  now=${EPOCHSECONDS:-0}
  ((force == 0 && DF_LAST > 0 && now - DF_LAST < 30)) && return 0
  DF_LAST=$now
  have df || return 1
  _disk_scan_mounts
  local have_filter=$((${#_MP_OK[@]} > 0))
  MOUNTS=() MP_PCT=() MP_USED=() MP_SIZE=() MP_AVAIL=() MP_FSTYPE=()
  local src size used avail pct mp
  while read -r src size used avail pct mp; do
    [[ $src == Filesystem || -z $mp ]] && continue
    if ((have_filter)); then
      # /proc/mounts was readable, so trust it completely.
      [[ -v _MP_OK[$mp] ]] || continue
      MP_FSTYPE[$mp]=${_MP_OK[$mp]}
    else
      # No /proc/mounts (not Linux, or restricted): fall back to judging by the
      # device path, which at least keeps tmpfs and overlays out.
      case $src in
        /dev/loop*) continue ;;
        /dev/* | zfs* | *:/*) ;;
        *) continue ;;
      esac
      case $mp in
        /snap/* | /var/lib/snapd/*) continue ;;
      esac
    fi
    pct=${pct%\%}
    [[ $pct =~ ^[0-9]+$ ]] || continue
    MOUNTS+=("$mp")
    MP_PCT[$mp]=$pct
    MP_USED[$mp]=$((used * 1024))
    MP_SIZE[$mp]=$((size * 1024))
    MP_AVAIL[$mp]=$((avail * 1024))
  done < <(df -kP 2>/dev/null)
  return 0
}

# ---------------------------------------------------------------------------
# processes
# ---------------------------------------------------------------------------
declare -a P_PID=() P_NAME=() P_CPU=() P_RSS=() P_THR=() P_STATE=() P_USER=()
declare -A _P_PREV=()
PROC_TOTAL=0 PROC_THREADS=0
declare -A _UIDNAME=()

UID_NAME=''
_uid_name_v() {
  local uid=$1 u x id
  if [[ -v _UIDNAME[$uid] ]]; then UID_NAME=${_UIDNAME[$uid]}; return 0; fi
  UID_NAME=$uid
  # /etc/passwd directly first: `id -nu` would be a fork per distinct uid, per
  # tick, and the file covers every local account.
  while IFS=: read -r u x id _; do
    [[ $id == "$uid" ]] && { UID_NAME=$u; break; }
  done </etc/passwd 2>/dev/null
  # Still unresolved means the account is not local: LDAP, SSSD, AD or macOS
  # Directory Services. getent goes through NSS and finds those. One fork, cached
  # for the life of the process, and only for uids the file did not answer.
  if [[ $UID_NAME == "$uid" ]] && have getent; then
    local line
    line=$(getent passwd "$uid" 2>/dev/null) && [[ -n $line ]] && UID_NAME=${line%%:*}
  fi
  _UIDNAME[$uid]=$UID_NAME
  return 0
}

# proc_state_rank_v <stat-char> -- maps /proc/<pid>/stat's state letter onto the
# four-tier sequence the process panel displays in: active, paused, stopped,
# inactive. Kept as one small pure function rather than inlined in two places
# (the sort above and the colour choice in panel_proc) so the mapping cannot
# drift between "what order" and "what colour".
PROC_STATE_RANK=3
proc_state_rank_v() {
  case $1 in
    R) PROC_STATE_RANK=0 ;;                 # active   -- on a CPU right now
    S | I) PROC_STATE_RANK=1 ;;             # paused   -- idle/sleeping, waiting on something
    D) PROC_STATE_RANK=1 ;;                 # paused   -- waiting on uninterruptible I/O
    T | t) PROC_STATE_RANK=2 ;;             # stopped  -- job-control stop, not running
    Z | X) PROC_STATE_RANK=3 ;;             # inactive -- zombie / dead, nothing left to run
    *) PROC_STATE_RANK=3 ;;
  esac
  return 0
}

# Top-K by insertion rather than a full sort: an 800-process box costs 800*K
# integer compares and zero forks, where `ps | sort | head` costs three
# processes and a pipeline every tick.
# ponytail: the "find weakest kept entry" scan makes this O(n*K). Fine for
# K<=25 (the UI cannot show more), but if K ever becomes large, swap the K-array
# for a real heap rather than widening this loop.
proc_sample() {
  local ms=$1 want=$2 sortby=${3:-cpu}
  local d pid line rest comm tail utime stime rss thr st total key dt cpu
  local -a f=()
  local -a kp=() kn=() kc=() kr=() kt=() ks=()
  local i j n=0 metric
  PROC_TOTAL=0 PROC_THREADS=0
  ((want < 1)) && want=1

  for d in "$HYN_PROC"/[0-9]*; do
    pid=${d##*/}
    # 2>/dev/null BEFORE the input redirection, deliberately. Redirections are
    # applied left to right, so with the file first bash reports a failed open on
    # the *original* stderr before fd 2 has been replaced -- and a process that
    # exits between the glob and this read is completely normal, so every
    # snapshot on a busy box printed "/proc/<pid>/stat: No such file".
    read -r line 2>/dev/null <"$d/stat" || continue
    ((PROC_TOTAL++))
    # comm sits between the first '(' and the LAST ')', and may contain both
    # spaces and parens -- "(sd-pam)" and "((sd-pam))" are real process names.
    # The parens must be escaped: with extglob on, an unescaped "*(" is read as
    # the start of an extglob group and the match silently does nothing.
    rest=${line#*\(}
    comm=${rest%\)*}
    tail=${rest##*\)}
    f=($tail)
    ((${#f[@]} < 22)) && continue
    st=${f[0]}
    utime=${f[11]} stime=${f[12]}
    thr=${f[17]}
    rss=$((${f[21]} * PAGE_SIZE))
    ((PROC_THREADS += thr))
    total=$((utime + stime))
    # Key on pid+starttime so a recycled pid cannot inherit the old process's
    # CPU counter and render as a momentary 100% spike.
    key=$pid:${f[19]}
    dt=$((total - ${_P_PREV[$key]:-total}))
    _P_PREV[$key]=$total
    ((dt < 0)) && dt=0
    # CPU in tenths of a percent of one core, so the panel can show one decimal.
    # A relay node idling at 0.4% and one idling at 0.0% are different stories.
    if ((ms > 0)); then cpu=$((dt * 1000000 / (CLK_TCK * ms))); else cpu=0; fi

    if [[ $sortby == mem ]]; then metric=$rss; else metric=$cpu; fi
    if ((n < want)); then
      i=$n
      ((n++))
    else
      local worst=0 wi=-1 mv
      for ((j = 0; j < n; j++)); do
        if [[ $sortby == mem ]]; then mv=${kr[j]}; else mv=${kc[j]}; fi
        if ((wi < 0 || mv < worst)); then worst=$mv wi=$j; fi
      done
      if ((metric > worst)); then i=$wi; else continue; fi
    fi
    kp[i]=$pid kn[i]=$comm kc[i]=$cpu kr[i]=$rss kt[i]=$thr ks[i]=$st
  done

  # Order the K survivors. Primary key is the state sequence the process panel
  # wants on screen -- active, paused, stopped, inactive -- so the coloured
  # groups land together instead of being interleaved by whoever happens to be
  # busiest; the chosen sort metric (cpu or mem) only breaks ties inside a
  # group. Selection sort on single digits to low tens is smaller and cheaper
  # than reaching for an external sort.
  local -a idx=() rank=()
  for ((i = 0; i < n; i++)); do idx+=("$i"); proc_state_rank_v "${ks[i]}"; rank[i]=$PROC_STATE_RANK; done
  for ((i = 0; i < n; i++)); do
    local best=$i ra rb a b t
    for ((j = i + 1; j < n; j++)); do
      ra=${rank[idx[j]]} rb=${rank[idx[best]]}
      if [[ $sortby == mem ]]; then a=${kr[idx[j]]} b=${kr[idx[best]]}; else a=${kc[idx[j]]} b=${kc[idx[best]]}; fi
      if ((ra < rb || (ra == rb && a > b))); then best=$j; fi
    done
    t=${idx[i]}; idx[i]=${idx[best]}; idx[best]=$t
  done

  P_PID=() P_NAME=() P_CPU=() P_RSS=() P_THR=() P_STATE=() P_USER=()
  for ((i = 0; i < n; i++)); do
    j=${idx[i]}
    P_PID+=("${kp[j]}") P_NAME+=("${kn[j]}") P_CPU+=("${kc[j]}")
    P_RSS+=("${kr[j]}") P_THR+=("${kt[j]}") P_STATE+=("${ks[j]}")
    # Owner is resolved only for rows we will actually draw: K status reads
    # instead of one per process on the box.
    local sline ouid=0
    if [[ -r $HYN_PROC/${kp[j]}/status ]]; then
      while IFS= read -r sline; do
        [[ $sline == Uid:* ]] || continue
        local -a uf=(${sline#*:})
        ouid=${uf[0]}
        break
      done <"$HYN_PROC/${kp[j]}/status"
    fi
    _uid_name_v "$ouid"
    P_USER+=("$UID_NAME")
  done

  # Reap CPU baselines for pids that have exited, or _P_PREV grows unbounded on
  # a box that churns processes (which a build server or a node runner does).
  if ((${#_P_PREV[@]} > 4096)); then _P_PREV=(); fi
  return 0
}

# ---------------------------------------------------------------------------
# system
# ---------------------------------------------------------------------------
UPTIME_S=0 ENTROPY='' FD_USED='' FD_MAX='' SESSIONS=0 REBOOT_REQ=0 UPDATES=''
sys_sample() {
  local v
  read -r v _ <"$HYN_PROC/uptime" 2>/dev/null && UPTIME_S=${v%%.*}
  readval ENTROPY "$HYN_PROC/sys/kernel/random/entropy_avail"
  if readval v "$HYN_PROC/sys/fs/file-nr"; then
    local -a f=($v)
    FD_USED=${f[0]} FD_MAX=${f[2]}
  fi
  # Session count by glob, not `who`: no fork, and it counts systemd's view.
  SESSIONS=0
  local s
  for s in /run/systemd/sessions/*; do [[ -f $s ]] && ((SESSIONS++)); done
  [[ -f /var/run/reboot-required || -f /run/reboot-required ]] && REBOOT_REQ=1 || REBOOT_REQ=0
  UPDATES=''
  if [[ -r /var/lib/update-notifier/updates-available ]]; then
    local line
    while IFS= read -r line; do
      case $line in
        *update*can*be*applied* | *packages*can*be*updated*)
          UPDATES=${line%% *}
          [[ $UPDATES =~ ^[0-9]+$ ]] || UPDATES=''
          break ;;
      esac
    done </var/lib/update-notifier/updates-available
  fi
  return 0
}

# Failed systemd units, on a slow cadence. Read-only; this tool never changes
# unit state.
declare -a FAILED_UNITS=()
FAILED_LAST=0
sys_failed_units() {
  local now=${EPOCHSECONDS:-0}
  ((FAILED_LAST > 0 && now - FAILED_LAST < 15)) && return 0
  FAILED_LAST=$now
  have systemctl || return 1
  FAILED_UNITS=()
  local unit rest
  while read -r unit rest; do
    [[ $unit == *.service || $unit == *.socket || $unit == *.timer || $unit == *.mount ]] || continue
    FAILED_UNITS+=("$unit")
  done < <(systemctl list-units --state=failed --no-legend --plain --no-pager 2>/dev/null)
  return 0
}


# ---------------------------------------------------------------------------
# accounts and access
# ---------------------------------------------------------------------------
# Who the tool is running as, and who is logged into the box. On a server that
# runs unattended, "an ssh session from an address I do not recognise" is a more
# useful line in a report than most performance numbers.
RUN_AS='' RUN_UID='' LOGIN_USER=''
declare -a SESS_USER=() SESS_TTY=() SESS_FROM=() SESS_WHEN=()
SESS_LAST=0
FAILED_LOGINS=0 FAILED_LOGIN_TOP=''

# Resolved from /etc/passwd via the cache proc_sample already uses, so this costs
# no fork at all.
sys_whoami() {
  RUN_UID=${EUID:-0}
  _uid_name_v "$RUN_UID"
  RUN_AS=$UID_NAME
  # If neither /etc/passwd nor NSS resolved it, ask the kernel about the current
  # process specifically. Deliberately `id -un` and not $USER or $LOGNAME: those
  # can survive into a sudo shell still naming the original human while EUID is
  # 0, which would make the report claim it ran as someone it did not.
  if [[ $RUN_AS == "$RUN_UID" ]] && have id; then
    local n
    n=$(id -un 2>/dev/null) && [[ -n $n ]] && RUN_AS=$n
  fi
  # SUDO_USER is the right way to name the human, and it is unambiguous: it only
  # exists because sudo set it.
  LOGIN_USER=${SUDO_USER:-}
  return 0
}

# Active login sessions. `who` reads utmp, is POSIX, and gives the remote host in
# one fork -- loginctl would need a fork per session, and systemd's own session
# files carry a "do not parse" warning.
sys_sessions() {
  local force=${1:-0} now=${EPOCHSECONDS:-0}
  ((force == 0 && SESS_LAST > 0 && now - SESS_LAST < 60)) && return 0
  SESS_LAST=$now
  SESS_USER=() SESS_TTY=() SESS_FROM=() SESS_WHEN=()
  have who || return 1
  local u tty d t rest host
  while read -r u tty d t rest; do
    [[ -n $u && -n $tty ]] || continue
    # A remote host is reported in parentheses at the end of the line; a local
    # console session has none.
    host='local'
    if [[ $rest == *'('*')'* ]]; then
      host=${rest#*\(}
      host=${host%%\)*}
    fi
    [[ -z $host ]] && host='local'
    SESS_USER+=("$u") SESS_TTY+=("$tty") SESS_FROM+=("$host") SESS_WHEN+=("$d $t")
  done < <(who 2>/dev/null)
  return 0
}

# Rejected authentication attempts in the window. On an internet-facing box this
# is never zero, so the number only means something as a trend -- a jump from
# hundreds to tens of thousands is the signal.
sys_failed_logins() {
  local hours=${1:-24}
  FAILED_LOGINS=0 FAILED_LOGIN_TOP=''
  have journalctl || return 1
  local line ip
  declare -A tally=()
  while IFS= read -r line; do
    case $line in
      *'Failed password'* | *'Invalid user'* | *'authentication failure'* | *'Failed publickey'*)
        ((FAILED_LOGINS++))
        # "from 1.2.3.4 port 5678" -- pull the address to name the worst offender.
        if [[ $line == *' from '* ]]; then
          ip=${line#* from }
          ip=${ip%% *}
          [[ -n $ip ]] && ((tally[$ip]++))
        fi
        ;;
    esac
  done < <(journalctl -u ssh -u sshd --since "-${hours}h" --no-pager -o cat 2>/dev/null)
  local k best=0
  for k in "${!tally[@]}"; do
    ((tally[$k] > best)) && { best=${tally[$k]}; FAILED_LOGIN_TOP="$k (${tally[$k]}x)"; }
  done
  return 0
}
