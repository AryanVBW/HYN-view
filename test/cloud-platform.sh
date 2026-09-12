#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/hyn-platform-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export HYN_PROC="$WORK/proc" HYN_SYS="$WORK/sys"
mkdir -p "$HYN_PROC/self" "$HYN_SYS/class/dmi/id"
source "$ROOT/lib/cloud-platform.sh"
checks=0
check() { [[ $2 == "$3" ]] || { printf 'FAIL %s: expected %s, got %s\n' "$1" "$2" "$3"; exit 1; }; checks=$((checks + 1)); }
# Collection must never escape fixture roots to run host discovery or HTTP.
systemd-detect-virt() { printf 'unexpected host discovery\n' >&2; exit 91; }
curl() { printf 'unexpected network call\n' >&2; exit 92; }
cloud_platform_collect
cloud_platform_json_v
check 'missing platform files are unknown' unknown "${CLOUD_PLATFORM[provider]}"
check 'missing host memory stays unavailable' null "${CLOUD_PLATFORM[host_memory_bytes]}"
check 'missing limits stay unavailable' null "${CLOUD_PLATFORM[memory_limit_bytes]}"
python3 - "$CLOUD_PLATFORM_JSON" <<'PY'
import json,sys
p=json.loads(sys.argv[1])
assert p['host_cpu_count'] is None and p['provider_confidence']=='unknown'
assert 'serial' not in p and 'instance_id' not in p
PY

for pair in 'aws:Amazon EC2' 'gcp:Google Compute Engine' 'azure:Microsoft Azure' \
  'oracle:OracleCloud Compute' 'digitalocean:DigitalOcean' 'hetzner:Hetzner'; do
  printf '%s\n' "${pair#*:}" >"$HYN_SYS/class/dmi/id/product_name"
  cloud_platform_collect
  check "${pair%%:*} local provider signal" "${pair%%:*}" "${CLOUD_PLATFORM[provider]}"
  check 'provider claim is explicitly inferred' inferred "${CLOUD_PLATFORM[provider_confidence]}"
done
printf 'Microsoft Corporation\n' >"$HYN_SYS/class/dmi/id/sys_vendor"
printf 'Virtual Machine\n' >"$HYN_SYS/class/dmi/id/product_name"
cloud_platform_collect
check 'generic Hyper-V does not prove Azure' unknown "${CLOUD_PLATFORM[provider]}"
check 'generic Hyper-V remains useful virtualization evidence' microsoft "${CLOUD_PLATFORM[virtualization]}"
printf 'Generic\n' >"$HYN_SYS/class/dmi/id/sys_vendor"
printf 'QEMU Virtual Machine\n' >"$HYN_SYS/class/dmi/id/product_name"
cloud_platform_collect
check 'generic VPS stays provider unknown' unknown "${CLOUD_PLATFORM[provider]}"
check 'generic KVM recognized' kvm "${CLOUD_PLATFORM[virtualization]}"
printf 'Google Chromebook\n' >"$HYN_SYS/class/dmi/id/product_name"
cloud_platform_collect
check 'Google hardware alone does not prove GCP' unknown "${CLOUD_PLATFORM[provider]}"
mkdir -p "$HYN_SYS/firmware/devicetree/base"
printf 'Google Compute Engine\0' >"$HYN_SYS/firmware/devicetree/base/model"
cloud_platform_collect
check 'ARM device-tree provider signal recognized' gcp "${CLOUD_PLATFORM[provider]}"
check 'ARM provider evidence names device-tree' device-tree "${CLOUD_PLATFORM[provider_source]}"
: >"$HYN_SYS/firmware/devicetree/base/model"

printf 'cpu 1 2 3 4\ncpu0 1 2 3 4\ncpu1 1 2 3 4\ncpu2 1 2 3 4\ncpu3 1 2 3 4\n' >"$HYN_PROC/stat"
printf 'MemTotal: 8388608 kB\nMemFree: 4000000 kB\n' >"$HYN_PROC/meminfo"
CG="$HYN_SYS/fs/cgroup"
mkdir -p "$CG/docker/hyn"
printf 'cpu memory cpuset\n' >"$CG/cgroup.controllers"
printf '0::/docker/hyn\n' >"$HYN_PROC/self/cgroup"
printf '250000 100000\n' >"$CG/docker/hyn/cpu.max"
printf '150000 100000\n' >"$CG/docker/cpu.max"
printf 'max 100000\n' >"$CG/cpu.max"
printf '0-3\n' >"$CG/docker/hyn/cpuset.cpus.effective"
printf '2147483648\n' >"$CG/docker/hyn/memory.max"
printf '1073741824\n' >"$CG/docker/memory.max"
printf 'max\n' >"$CG/memory.max"
printf '123456789\n' >"$CG/docker/hyn/memory.current"
printf 'nr_periods 20\nnr_throttled 3\nthrottled_usec 90000\n' >"$CG/docker/hyn/cpu.stat"
cloud_platform_collect
cloud_platform_json_v
check 'nested cgroup v2 recognized' 2 "${CLOUD_PLATFORM[cgroup_version]}"
check 'container context recognized' container "${CLOUD_PLATFORM[environment]}"
check 'host CPU remains separate from quota' 4 "${CLOUD_PLATFORM[host_cpu_count]}"
check 'host memory remains separate from limit' 8589934592 "${CLOUD_PLATFORM[host_memory_bytes]}"
check 'effective quota respects parent' 1.500 "${CLOUD_PLATFORM[cpu_limit_cores]}"
check 'effective memory respects parent' 1073741824 "${CLOUD_PLATFORM[memory_limit_bytes]}"
check 'memory consumption belongs to current cgroup' 123456789 "${CLOUD_PLATFORM[memory_current_bytes]}"
check 'throttling count retained' 3 "${CLOUD_PLATFORM[cpu_throttled_periods]}"
check 'v2 throttling uses microseconds' 90000 "${CLOUD_PLATFORM[cpu_throttled_usec]}"
python3 - "$CLOUD_PLATFORM_JSON" <<'PY'
import json,sys
p=json.loads(sys.argv[1])
assert p['cpu_limit_cores']==1.5 and p['host_cpu_count']==4
assert p['metrics_scope']=='procfs'
assert '/docker/' not in sys.argv[1]
PY
printf '0\n' >"$CG/docker/hyn/cpuset.cpus.effective"
cloud_platform_collect
check 'cpuset can further constrain CPU quota' 1.000 "${CLOUD_PLATFORM[cpu_limit_cores]}"
printf '0::/../../private\n' >"$HYN_PROC/self/cgroup"
cloud_platform_collect
check 'malformed membership cannot traverse fixture root' null "${CLOUD_PLATFORM[cgroup_version]}"

mkdir -p "$CG/cpu,cpuacct/app" "$CG/memory/app" "$CG/cpuset/app"
printf '2:cpu,cpuacct:/app\n3:memory:/app\n4:cpuset:/app\n' >"$HYN_PROC/self/cgroup"
printf '50000\n' >"$CG/cpu,cpuacct/app/cpu.cfs_quota_us"
printf '100000\n' >"$CG/cpu,cpuacct/app/cpu.cfs_period_us"
printf -- '-1\n' >"$CG/cpu,cpuacct/cpu.cfs_quota_us"
printf '100000\n' >"$CG/cpu,cpuacct/cpu.cfs_period_us"
printf 'nr_throttled 2\nthrottled_time 12000000\n' >"$CG/cpu,cpuacct/app/cpu.stat"
printf '536870912\n' >"$CG/memory/app/memory.limit_in_bytes"
printf '9223372036854771712\n' >"$CG/memory/memory.limit_in_bytes"
printf '1048576\n' >"$CG/memory/app/memory.usage_in_bytes"
printf '0-1\n' >"$CG/cpuset/app/cpuset.cpus"
cloud_platform_collect
check 'v1 combined controller mount recognized' 1 "${CLOUD_PLATFORM[cgroup_version]}"
check 'v1 fractional CPU quota retained' 0.500 "${CLOUD_PLATFORM[cpu_limit_cores]}"
check 'v1 unlimited parent does not overflow' 536870912 "${CLOUD_PLATFORM[memory_limit_bytes]}"
check 'v1 usage belongs to own cgroup' 1048576 "${CLOUD_PLATFORM[memory_current_bytes]}"
check 'v1 nanoseconds converted to microseconds' 12000 "${CLOUD_PLATFORM[cpu_throttled_usec]}"
printf 'throttled_time 123456789012345678\n' >"$CG/cpu,cpuacct/app/cpu.stat"
cloud_platform_collect
check 'long-running v1 counter converted before numeric bounds' 123456789012345 "${CLOUD_PLATFORM[cpu_throttled_usec]}"

printf '0::/\n' >"$HYN_PROC/self/cgroup"
cloud_platform_collect
check 'namespaced v2 root is readable' 2 "${CLOUD_PLATFORM[cgroup_version]}"
check 'unlimited memory is unavailable, not zero' null "${CLOUD_PLATFORM[memory_limit_bytes]}"
check 'unlimited CPU is unavailable, not zero' null "${CLOUD_PLATFORM[cpu_limit_cores]}"
check 'recollection clears previous throttling value' null "${CLOUD_PLATFORM[cpu_throttled_usec]}"
printf '0-1,4,6-7\n' >"$CG/cpuset.cpus.effective"
cloud_platform_collect
check 'noncontiguous cpuset parsed' 5.000 "${CLOUD_PLATFORM[cpu_limit_cores]}"
printf '0-2,1-4\n' >"$CG/cpuset.cpus.effective"
printf 'not-a-number\n' >"$CG/memory.max"
printf '0 0\n' >"$CG/cpu.max"
cloud_platform_collect
check 'overlapping cpuset rejected' null "${CLOUD_PLATFORM[cpu_limit_cores]}"
check 'invalid limit rejected' null "${CLOUD_PLATFORM[memory_limit_bytes]}"
cloud_platform_json_v
python3 - "$CLOUD_PLATFORM_JSON" <<'PY'
import json,sys
assert json.loads(sys.argv[1])['cpu_limit_cores'] is None
PY
printf '%s platform checks passed\n' "$checks"
