#!/usr/bin/env bash
#
# diskwatch.sh - Report free disk space and show where space is being consumed.
# Target: Ubuntu 24.04 (works on most Debian/Ubuntu systems). Read-only: it never deletes anything.
#
# Usage:
#   sudo ./diskwatch.sh [-t PERCENT] [-p MOUNTPOINT] [-n TOPN] [-q]
#
#   -t PERCENT     Usage warning threshold (default: 80)
#   -p MOUNTPOINT  Filesystem to analyse in detail (default: /)
#   -n TOPN        How many top entries to show per section (default: 15)
#   -q             Quiet mode for cron: print nothing unless usage >= threshold
#
# Cron example (hourly, mail/log only when above threshold):
#   0 * * * * /usr/local/bin/diskwatch.sh -q -t 85 >> /var/log/diskwatch.log 2>&1

set -uo pipefail

THRESHOLD=80
MOUNT="/"
TOPN=15
QUIET=0

while getopts "t:p:n:qh" opt; do
  case "$opt" in
    t) THRESHOLD="$OPTARG" ;;
    p) MOUNT="$OPTARG" ;;
    n) TOPN="$OPTARG" ;;
    q) QUIET=1 ;;
    h|*) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "WARNING: not running as root - results will be incomplete (permission denied on many paths)." >&2
  echo "         Re-run with: sudo $0 $*" >&2
  echo >&2
fi

# ---------- helpers ----------
hr()      { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
have()    { command -v "$1" >/dev/null 2>&1; }
human()   { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "${1}B"; }

# Size (in bytes) + path, largest first, staying on one filesystem (-x)
top_dirs() {
  local path="$1" depth="${2:-1}"
  du -xb --max-depth="$depth" "$path" 2>/dev/null \
    | sort -rn | head -n "$((TOPN + 1))" \
    | awk '{ s=$1; $1=""; sub(/^ /,""); printf "%10.1f MB  %s\n", s/1048576, $0 }'
}

# ---------- usage check ----------
USE_PCT=$(df --output=pcent "$MOUNT" 2>/dev/null | tail -1 | tr -dc '0-9')
USE_PCT=${USE_PCT:-0}

if [[ $QUIET -eq 1 && $USE_PCT -lt $THRESHOLD ]]; then
  exit 0
fi

echo "Disk report for $(hostname) - $(date '+%Y-%m-%d %H:%M:%S %Z')"

# ---------- 1. Overview ----------
hr "Filesystem usage"
df -hT -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null

if [[ $USE_PCT -ge $THRESHOLD ]]; then
  printf '\n\033[1;31mALERT: %s is %s%% full (threshold %s%%)\033[0m\n' "$MOUNT" "$USE_PCT" "$THRESHOLD"
else
  printf '\n\033[1;32mOK: %s is %s%% full (threshold %s%%)\033[0m\n' "$MOUNT" "$USE_PCT" "$THRESHOLD"
fi

hr "Inode usage (a full inode table also causes 'No space left on device')"
df -ih -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null

# ---------- 2. Top-level breakdown ----------
hr "Largest top-level directories on $MOUNT"
top_dirs "$MOUNT" 1

hr "Largest directories under /var (usually logs, docker, caches, databases)"
top_dirs /var 2

# ---------- 3. Known space hogs ----------
hr "Known space consumers (summary)"
declare -a SUMMARY=()
add() { # label, path
  local label="$1" path="$2" bytes
  [[ -e "$path" ]] || return
  bytes=$(du -xsb "$path" 2>/dev/null | awk '{print $1}')
  [[ -n "$bytes" ]] && SUMMARY+=("$bytes|$label|$path")
}

add "System logs"                    /var/log
add "Journald (binary logs)"         /var/log/journal
add "APT package cache"              /var/cache/apt
add "APT lists"                      /var/lib/apt/lists
add "Snap packages"                  /var/lib/snapd
add "Snap data (per-user)"           /root/snap
add "Docker data root"               /var/lib/docker
add "Containerd"                     /var/lib/containerd
add "Core dumps / crash reports"     /var/crash
add "Systemd coredumps"              /var/lib/systemd/coredump
add "Temp (/tmp)"                    /tmp
add "Temp (/var/tmp)"                /var/tmp
add "Home directories"               /home
add "Root home"                      /root
add "Old kernels / modules"          /usr/lib/modules
add "Kernel images in /boot"         /boot
add "MySQL/MariaDB"                  /var/lib/mysql
add "PostgreSQL"                     /var/lib/postgresql
add "MongoDB"                        /var/lib/mongodb
add "Redis"                          /var/lib/redis
add "Web root (/var/www)"            /var/www
add "Mail spool"                     /var/mail
add "LXD/LXC"                        /var/lib/lxd
add "Libvirt images"                 /var/lib/libvirt

if ((${#SUMMARY[@]})); then
  printf '%s\n' "${SUMMARY[@]}" | sort -t'|' -k1,1 -rn | while IFS='|' read -r bytes label path; do
    printf '%12s  %-30s %s\n' "$(human "$bytes")" "$label" "$path"
  done
fi

# ---------- 4. Logs ----------
hr "Largest log files in /var/log"
find /var/log -xdev -type f -printf '%s %p\n' 2>/dev/null \
  | sort -rn | head -n "$TOPN" \
  | awk '{ s=$1; $1=""; sub(/^ /,""); printf "%10.1f MB  %s\n", s/1048576, $0 }'

if have journalctl; then
  hr "Systemd journal"
  journalctl --disk-usage 2>/dev/null
fi

# ---------- 5. Docker ----------
if have docker && docker info >/dev/null 2>&1; then
  hr "Docker: overall usage (images, containers, volumes, build cache)"
  docker system df 2>/dev/null

  hr "Docker: images by size"
  docker images --format '{{.Size}}\t{{.Repository}}:{{.Tag}}\t({{.ID}})' 2>/dev/null \
    | sort -rh | head -n "$TOPN"

  hr "Docker: dangling (untagged) images"
  DANGLING=$(docker images -f dangling=true -q 2>/dev/null | wc -l)
  echo "$DANGLING dangling image(s)"

  hr "Docker: container writable layers (size of data inside each container)"
  docker ps -a --size --format '{{.Size}}\t{{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null \
    | sort -rh | head -n "$TOPN"

  hr "Docker: volumes by size"
  docker system df -v 2>/dev/null | awk '/^Local Volumes space usage:/{f=1;next} /^Build cache usage:/{f=0} f' \
    | sed '/^$/d' | head -n "$((TOPN + 1))"

  DOCKER_ROOT=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)
  DOCKER_ROOT=${DOCKER_ROOT:-/var/lib/docker}

  hr "Docker: container log files (json-file driver) - often the hidden culprit"
  if [[ -d "$DOCKER_ROOT/containers" ]]; then
    find "$DOCKER_ROOT/containers" -maxdepth 2 -name '*-json.log*' -type f -printf '%s %p\n' 2>/dev/null \
      | sort -rn | head -n "$TOPN" \
      | while read -r size file; do
          cid=$(basename "$(dirname "$file")")
          name=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##')
          printf '%10.1f MB  %-30s %s\n' "$(awk "BEGIN{print $size/1048576}")" "${name:-unknown}" "$file"
        done
  else
    echo "No container log directory found at $DOCKER_ROOT/containers (or no permission)."
  fi

  LOG_DRIVER=$(docker info --format '{{.LoggingDriver}}' 2>/dev/null)
  echo
  echo "Default logging driver: ${LOG_DRIVER:-unknown}"
  if [[ ! -f /etc/docker/daemon.json ]] || ! grep -q 'max-size' /etc/docker/daemon.json 2>/dev/null; then
    echo "NOTE: no log rotation (max-size) configured in /etc/docker/daemon.json - container logs can grow unbounded."
  fi
else
  hr "Docker"
  echo "Docker not installed, not running, or no permission to talk to the daemon."
fi

# ---------- 6. Biggest files overall ----------
hr "Largest files on $MOUNT (>50 MB)"
find "$MOUNT" -xdev -type f -size +50M -printf '%s %p\n' 2>/dev/null \
  | sort -rn | head -n "$TOPN" \
  | awk '{ s=$1; $1=""; sub(/^ /,""); printf "%10.1f MB  %s\n", s/1048576, $0 }'

# ---------- 7. Deleted-but-still-open files ----------
if have lsof; then
  hr "Deleted files still held open by processes (space is NOT freed until the process restarts)"
  lsof -nP +L1 2>/dev/null | awk 'NR==1 || $7+0 > 10485760' | head -n "$((TOPN + 1))"
else
  hr "Deleted-but-open files"
  echo "lsof not installed (sudo apt install lsof) - skipping."
fi

# ---------- 8. Cleanup hints (nothing is executed) ----------
hr "Suggested cleanup commands (review before running)"
cat <<'EOF'
  Journal:        sudo journalctl --vacuum-size=500M      (or --vacuum-time=14d)
  APT cache:      sudo apt clean && sudo apt autoremove --purge
  Old snaps:      snap list --all | awk '/disabled/{print $1, $3}' | while read n r; do sudo snap remove "$n" --revision="$r"; done
  Docker prune:   docker system prune -a --volumes        (removes ALL unused images/volumes - check first!)
  Docker build:   docker builder prune
  Docker logs:    truncate -s 0 /var/lib/docker/containers/<id>/<id>-json.log
                  and set rotation in /etc/docker/daemon.json:
                    { "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" } }
                  then: sudo systemctl restart docker (applies to newly created containers)
  Rotated logs:   sudo logrotate -f /etc/logrotate.conf
  Core dumps:     sudo rm -f /var/crash/* ; sudo coredumpctl --no-pager list
  Deleted+open:   restart the process holding the file (see lsof section above)
EOF

echo
exit 0
