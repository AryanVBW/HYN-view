#!/usr/bin/env bash
# Local-only cloud/VPS context. No metadata HTTP requests, instance IDs, serials,
# account names, credentials or raw DMI/cgroup paths leave this collector.
# Existing CPU/memory readings describe procfs; cgroup limits stay separate.
# Interfaces: https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html

CLOUD_PLATFORM_JSON='{}'
CLOUD_PLATFORM_READ=''
declare -A CLOUD_PLATFORM=()

_cloud_platform_read() {
  CLOUD_PLATFORM_READ=''
  [[ -r $1 ]] || return 1
  IFS= read -r -n 512 CLOUD_PLATFORM_READ <"$1" || [[ -n $CLOUD_PLATFORM_READ ]]
}

# Bound arithmetic and JSON numbers below the exact integer range of browsers.
_cloud_platform_uint() { [[ $1 =~ ^(0|[1-9][0-9]{0,14})$ ]]; }

_cloud_platform_provider() {
  case ${1,,} in
    *amazon*ec2* | *amazon*web*services*) CLOUD_PLATFORM[provider]=aws ;;
    *google*compute*) CLOUD_PLATFORM[provider]=gcp ;;
    *azure*) CLOUD_PLATFORM[provider]=azure ;;
    *oraclecloud* | *oracle*cloud* | *oracle*compute*) CLOUD_PLATFORM[provider]=oracle ;;
    *digitalocean*) CLOUD_PLATFORM[provider]=digitalocean ;;
    *hetzner*) CLOUD_PLATFORM[provider]=hetzner ;;
    *) return 1 ;;
  esac
  CLOUD_PLATFORM[provider_source]=$2
  CLOUD_PLATFORM[provider_confidence]=inferred
  return 0
}

_cloud_platform_virt() {
  case $1 in
    docker | podman | lxc | lxc-libvirt | containerd | openvz | systemd-nspawn)
      CLOUD_PLATFORM[virtualization]=$1; CLOUD_PLATFORM[environment]=container ;;
    kvm | qemu | xen | vmware | microsoft | oracle | bhyve | parallels | amazon | google)
      CLOUD_PLATFORM[virtualization]=$1; CLOUD_PLATFORM[environment]=vm ;;
    *) return 1 ;;
  esac
  return 0
}

_cloud_platform_cgroup_path() {
  # Refuse malformed membership instead of falling back to an unrelated host
  # cgroup. A missing/private mount is reported unavailable, never as zero.
  [[ $1 == /* && $1 != *'/../'* && $1 != */.. && $1 != *'/./'* && $1 != */. && $1 != *'//'* ]]
}

_cloud_platform_min() {
  local key=$1 value=$2
  _cloud_platform_uint "$value" || return 0
  if [[ ${CLOUD_PLATFORM[$key]:-null} == null ]] || ((value < CLOUD_PLATFORM[$key])); then
    CLOUD_PLATFORM[$key]=$value
  fi
  return 0
}

_cloud_platform_cpu_limit() {
  local quota=$1 period=$2 milli
  _cloud_platform_uint "$quota" && _cloud_platform_uint "$period" || return 0
  # Kernel periods are small; bounds also prevent overflowing quota * 1000.
  ((quota > 0 && period > 0 && period <= 1000000000)) || return 0
  # Split quotient/remainder to keep exact millicores without a large product.
  # shellcheck disable=SC2017
  milli=$((quota / period * 1000 + quota % period * 1000 / period))
  _cloud_platform_min cpu_limit_millicores "$milli"
}

_cloud_platform_cpuset() {
  local list=$1 part first last count=0 prev=-1
  local -a parts=()
  [[ $list =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ && ${#list} -le 512 ]] || return 0
  IFS=, read -r -a parts <<<"$list"
  for part in "${parts[@]}"; do
    first=${part%%-*}; last=${part##*-}
    [[ ${#first} -le 6 && ${#last} -le 6 ]] || return 0
    first=$((10#$first)); last=$((10#$last))
    ((first > prev && last >= first)) || return 0
    count=$((count + last - first + 1)); prev=$last
  done
  _cloud_platform_min cpu_limit_millicores "$((count * 1000))"
}

_cloud_platform_limits() {
  local base=$1 leaf=$2 version=$3 controller=$4 dir=$2 value quota period key depth=0
  # Limits are hierarchical. Inspect at most 64 visible ancestors; usage and
  # throttling are read from our own cgroup only, not from sibling workloads.
  while [[ $dir == "$base" || $dir == "$base/"* ]] && ((depth < 64)); do
    if [[ $version == 2 ]]; then
      if _cloud_platform_read "$dir/cpu.max"; then
        read -r quota period _ <<<"$CLOUD_PLATFORM_READ"
        _cloud_platform_cpu_limit "${quota:-}" "${period:-}"
      fi
      if _cloud_platform_read "$dir/memory.max"; then
        _cloud_platform_min memory_limit_bytes "$CLOUD_PLATFORM_READ"
      fi
      if _cloud_platform_read "$dir/cpuset.cpus.effective"; then
        _cloud_platform_cpuset "$CLOUD_PLATFORM_READ"
      fi
    elif [[ $controller == cpu ]]; then
      quota=''; period=''
      if _cloud_platform_read "$dir/cpu.cfs_quota_us"; then quota=$CLOUD_PLATFORM_READ; fi
      if _cloud_platform_read "$dir/cpu.cfs_period_us"; then period=$CLOUD_PLATFORM_READ; fi
      _cloud_platform_cpu_limit "$quota" "$period"
    elif [[ $controller == memory ]]; then
      if _cloud_platform_read "$dir/memory.limit_in_bytes"; then
        # v1's large unlimited sentinel fails the bounded integer check.
        _cloud_platform_min memory_limit_bytes "$CLOUD_PLATFORM_READ"
      fi
    elif [[ $controller == cpuset ]] && _cloud_platform_read "$dir/cpuset.cpus"; then
      _cloud_platform_cpuset "$CLOUD_PLATFORM_READ"
    fi
    [[ $dir == "$base" ]] && break
    dir=${dir%/*}; depth=$((depth + 1))
  done
  if [[ $version == 2 ]]; then value=memory.current; else value=memory.usage_in_bytes; fi
  if [[ $version == 2 || $controller == memory ]] && _cloud_platform_read "$leaf/$value"; then
    _cloud_platform_uint "$CLOUD_PLATFORM_READ" && CLOUD_PLATFORM[memory_current_bytes]=$CLOUD_PLATFORM_READ
  fi
  if [[ ( $version == 2 || $controller == cpu ) && -r $leaf/cpu.stat ]]; then
    while read -r key value _; do
      if [[ $key == throttled_time && ${value:-} =~ ^(0|[1-9][0-9]{0,19})$ ]]; then
        # v1 counts nanoseconds; divide as text first, before the safe JSON
        # integer check, so long-running VPS counters cannot overflow Bash.
        if ((${#value} > 3)); then value=${value:0:${#value}-3}; else value=0; fi
        _cloud_platform_uint "$value" && CLOUD_PLATFORM[cpu_throttled_usec]=$value
        continue
      fi
      _cloud_platform_uint "${value:-}" || continue
      case $key in
        nr_throttled) CLOUD_PLATFORM[cpu_throttled_periods]=$value ;;
        throttled_usec) CLOUD_PLATFORM[cpu_throttled_usec]=$value ;;
      esac
    done <"$leaf/cpu.stat"
  fi
  return 0
}

cloud_platform_collect() {
  local sys=${HYN_SYS:-/sys} proc=${HYN_PROC:-/proc} f value key rest cores=0
  local id controllers path base leaf controller virt='' dmi=''
  CLOUD_PLATFORM=([provider]=unknown [provider_source]=none [provider_confidence]=unknown
    [virtualization]=unknown [environment]=unknown [metrics_scope]=procfs
    [host_cpu_count]=null [host_memory_bytes]=null [cgroup_version]=null
    [cpu_limit_cores]=null [cpu_limit_millicores]=null [memory_limit_bytes]=null
    [memory_current_bytes]=null [cpu_throttled_usec]=null [cpu_throttled_periods]=null)
  for f in sys_vendor product_name board_vendor; do
    if _cloud_platform_read "$sys/class/dmi/id/$f"; then dmi+=" $CLOUD_PLATFORM_READ"; fi
  done
  _cloud_platform_provider "$dmi" dmi || true
  if [[ ${CLOUD_PLATFORM[provider]} == unknown ]] && _cloud_platform_read "$sys/firmware/devicetree/base/model"; then
    _cloud_platform_provider "$CLOUD_PLATFORM_READ" device-tree || true
  fi
  case ${dmi,,} in
    *kvm* | *qemu*) virt=kvm ;;
    *vmware*) virt=vmware ;;
    *xen*) virt=xen ;;
    *microsoft*virtual*machine*) virt=microsoft ;;
    *virtualbox*) virt=oracle ;;
  esac
  _cloud_platform_virt "$virt" || true
  # Fixture roots never invoke host commands. systemd-detect-virt reports the
  # innermost environment; Microsoft Hyper-V alone does not prove Azure.
  if [[ $sys == /sys && $proc == /proc ]] && command -v systemd-detect-virt >/dev/null 2>&1; then
    virt=$(systemd-detect-virt 2>/dev/null) || virt=''
    _cloud_platform_virt "$virt" || true
  fi
  if [[ -r $proc/stat ]]; then
    while read -r key rest; do [[ $key =~ ^cpu[0-9]+$ ]] && cores=$((cores + 1)); done <"$proc/stat"
    ((cores > 0)) && CLOUD_PLATFORM[host_cpu_count]=$cores
  fi
  if [[ -r $proc/meminfo ]]; then
    while read -r key value rest; do
      if [[ $key == MemTotal: && $rest == kB ]] && _cloud_platform_uint "${value:-}" && ((${#value} <= 12)); then
        CLOUD_PLATFORM[host_memory_bytes]=$((value * 1024)); break
      fi
    done <"$proc/meminfo"
  fi
  [[ -r $proc/self/cgroup ]] || return 0
  while IFS=: read -r id controllers path; do
    case $path in
      *docker*) _cloud_platform_virt docker ;;
      *libpod*) _cloud_platform_virt podman ;;
      *lxc*) _cloud_platform_virt lxc ;;
      *containerd*) _cloud_platform_virt containerd ;;
    esac
    _cloud_platform_cgroup_path "$path" || continue
    if [[ $id == 0 && -z $controllers ]]; then
      base="$sys/fs/cgroup"
      [[ -r $base/cgroup.controllers ]] || base="$sys/fs/cgroup/unified"
      [[ -r $base/cgroup.controllers ]] || continue
      leaf="$base${path%/}"
      [[ -d $leaf ]] || continue
      CLOUD_PLATFORM[cgroup_version]=2
      _cloud_platform_limits "$base" "$leaf" 2 all
    else
      for controller in cpu memory cpuset; do
        [[ ,$controllers, == *,$controller,* ]] || continue
        base="$sys/fs/cgroup/$controller"
        if [[ $controller == cpu && ! -d $base ]]; then
          base="$sys/fs/cgroup/cpu,cpuacct"
          [[ -d $base ]] || base="$sys/fs/cgroup/cpuacct,cpu"
        fi
        leaf="$base${path%/}"
        [[ -d $leaf ]] || continue
        [[ ${CLOUD_PLATFORM[cgroup_version]} == null ]] && CLOUD_PLATFORM[cgroup_version]=1
        _cloud_platform_limits "$base" "$leaf" 1 "$controller"
      done
    fi
  done <"$proc/self/cgroup"
  value=${CLOUD_PLATFORM[cpu_limit_millicores]}
  if [[ $value != null ]]; then
    printf -v 'CLOUD_PLATFORM[cpu_limit_cores]' '%d.%03d' "$((value / 1000))" "$((value % 1000))"
  fi
  return 0
}

cloud_platform_json_v() {
  local key sep=''
  CLOUD_PLATFORM_JSON='{'
  for key in provider provider_source provider_confidence virtualization environment metrics_scope; do
    CLOUD_PLATFORM_JSON+="$sep\"$key\":\"${CLOUD_PLATFORM[$key]:-unknown}\""; sep=,
  done
  for key in host_cpu_count host_memory_bytes cgroup_version cpu_limit_cores memory_limit_bytes memory_current_bytes cpu_throttled_usec cpu_throttled_periods; do
    CLOUD_PLATFORM_JSON+=",\"$key\":${CLOUD_PLATFORM[$key]:-null}"
  done
  CLOUD_PLATFORM_JSON+='}'
}
