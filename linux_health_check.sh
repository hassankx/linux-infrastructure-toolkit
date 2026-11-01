#!/usr/bin/env bash
# linux_health_check.sh - read-only health assessment for a Linux host.
#
# Prints a short report with PASS / WARN / INFO lines so you can see at a
# glance what needs attention. Nothing on the host is changed.
#
# Usage: ./linux_health_check.sh [--disk-warn PCT] [--load-warn RATIO]
set -uo pipefail

DISK_WARN=85     # warn when a filesystem is at or above this % used
LOAD_WARN=1.5    # warn when 5-min load / CPU count exceeds this ratio
WARNINGS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk-warn) DISK_WARN="$2"; shift 2 ;;
    --load-warn) LOAD_WARN="$2"; shift 2 ;;
    -h|--help)   sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

section() { printf '\n== %s ==\n' "$1"; }
pass()    { printf '  [PASS] %s\n' "$1"; }
info()    { printf '  [INFO] %s\n' "$1"; }
warn()    { printf '  [WARN] %s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }
have()    { command -v "$1" >/dev/null 2>&1; }

section "System"
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  info "OS: ${PRETTY_NAME:-unknown}"
fi
info "Kernel: $(uname -r)"
info "Hostname: $(hostname)"
if [[ -r /proc/uptime ]]; then
  up_days=$(awk '{printf "%d", $1/86400}' /proc/uptime)
  info "Uptime: ${up_days} day(s)"
  if (( up_days > 180 )); then
    warn "Up for more than 180 days; check that kernel patches are being applied"
  fi
fi

section "CPU load"
cpus=$(nproc 2>/dev/null || echo 1)
load5=$(awk '{print $2}' /proc/loadavg 2>/dev/null || echo 0)
ratio=$(awk -v l="$load5" -v c="$cpus" 'BEGIN {printf "%.2f", l/c}')
if awk -v r="$ratio" -v w="$LOAD_WARN" 'BEGIN {exit !(r > w)}'; then
  warn "5-min load ${load5} on ${cpus} CPU(s) (ratio ${ratio})"
else
  pass "5-min load ${load5} on ${cpus} CPU(s) (ratio ${ratio})"
fi

section "Memory"
if [[ -r /proc/meminfo ]]; then
  read -r total avail swap_total swap_free < <(awk '
    /^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2}
    /^SwapTotal:/ {st=$2} /^SwapFree:/ {sf=$2}
    END {print t, a, st, sf}' /proc/meminfo)
  avail_pct=$(( avail * 100 / total ))
  if (( avail_pct < 10 )); then
    warn "Only ${avail_pct}% of memory available"
  else
    pass "${avail_pct}% of memory available"
  fi
  if (( swap_total > 0 )); then
    swap_used_pct=$(( (swap_total - swap_free) * 100 / swap_total ))
    if (( swap_used_pct > 50 )); then
      warn "Swap ${swap_used_pct}% used"
    else
      info "Swap ${swap_used_pct}% used"
    fi
  else
    info "No swap configured"
  fi
fi

section "Filesystems"
while read -r pct inode_mount; do
  [[ -z "$pct" ]] && continue
  if (( pct >= DISK_WARN )); then
    warn "${inode_mount} is ${pct}% full"
  fi
done < <(df -P -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null \
          | awk 'NR > 1 {gsub("%", "", $5); print $5, $6}')
while read -r ipct mnt; do
  [[ -z "$ipct" || "$ipct" == "-" ]] && continue
  if (( ipct >= DISK_WARN )); then
    warn "${mnt} has used ${ipct}% of its inodes"
  fi
done < <(df -Pi -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null \
          | awk 'NR > 1 {gsub("%", "", $5); print $5, $6}')
if [[ -r /proc/mounts ]]; then
  while read -r dev mnt _ opts _; do
    if [[ ",${opts}," == *",ro,"* && "$dev" == /dev/* ]]; then
      warn "${mnt} is mounted read-only (${dev})"
    fi
  done < /proc/mounts
fi
info "Disk threshold: ${DISK_WARN}%"

section "Services"
if have systemctl && [[ -d /run/systemd/system ]]; then
  failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')
  if [[ -n "$failed" ]]; then
    while read -r unit; do warn "Failed unit: ${unit}"; done <<< "$failed"
  else
    pass "No failed systemd units"
  fi
else
  info "systemd not available; skipped"
fi

section "Time sync"
if have timedatectl && timedatectl show >/dev/null 2>&1; then
  if [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" == "yes" ]]; then
    pass "Clock is synchronized"
  else
    warn "Clock is not synchronized (check chronyd or systemd-timesyncd)"
  fi
elif have chronyc; then
  chronyc tracking 2>/dev/null | grep -E 'Leap status|System time' | sed 's/^/  [INFO] /'
else
  info "No time sync tool found to query"
fi

section "Security posture"
if have getenforce; then
  mode=$(getenforce 2>/dev/null)
  if [[ "$mode" == "Enforcing" ]]; then pass "SELinux: ${mode}"; else warn "SELinux: ${mode}"; fi
elif have aa-status && aa-status --enabled 2>/dev/null; then
  pass "AppArmor is enabled"
else
  info "No SELinux or AppArmor status available"
fi
if [[ -r /etc/ssh/sshd_config ]]; then
  if grep -Eiq '^\s*PermitRootLogin\s+yes' /etc/ssh/sshd_config; then
    warn "sshd allows direct root login"
  else
    pass "sshd does not explicitly allow root login"
  fi
  if grep -Eiq '^\s*PasswordAuthentication\s+yes' /etc/ssh/sshd_config; then
    warn "sshd allows password authentication"
  fi
fi

section "Network"
if have ip; then
  default_route=$(ip route show default 2>/dev/null | head -1)
  if [[ -n "$default_route" ]]; then pass "Default route: ${default_route}"; else warn "No default route"; fi
fi
if [[ -r /etc/resolv.conf ]]; then
  ns=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf | paste -sd, -)
  if [[ -n "$ns" ]]; then info "DNS servers: ${ns}"; else warn "No nameservers in /etc/resolv.conf"; fi
fi
if have ss; then
  info "Listening TCP sockets: $(ss -Htln 2>/dev/null | wc -l)"
fi

section "Kernel messages"
if have journalctl; then
  errs=$(journalctl -k -p err -b --no-pager -q 2>/dev/null | wc -l)
  if (( errs > 0 )); then
    warn "${errs} kernel error line(s) since boot (journalctl -k -p err -b)"
  else
    pass "No kernel errors logged since boot"
  fi
else
  info "journalctl not available; skipped"
fi

printf '\n== Summary ==\n'
if (( WARNINGS > 0 )); then
  echo "  ${WARNINGS} warning(s) found. Review the [WARN] lines above."
  exit 1
fi
echo "  No warnings."
exit 0
