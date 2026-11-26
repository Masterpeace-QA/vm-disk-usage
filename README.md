# vm-disk-usage

A single-file Bash script that checks free disk space on an Ubuntu server and shows **where the space is going**: logs, journald, APT caches, snaps, Docker images, Docker container logs, volumes, large files and more.

The script is read-only. It never deletes anything; it only prints suggested cleanup commands for you to review.

Tested target: **Ubuntu 24.04 LTS** (should work on other Debian/Ubuntu releases).

## Features

- Filesystem and inode usage with an OK/ALERT status against a configurable threshold
- Largest top-level directories and a deeper breakdown of `/var`
- Ranked summary of known space consumers (logs, journald, APT, snap, Docker, databases, `/tmp`, crash dumps, old kernels, home directories, web root)
- Largest files in `/var/log` and journald disk usage
- Docker report (if installed):
  - `docker system df` overview
  - images by size and dangling images
  - container writable layers and volumes
  - per-container `*-json.log` sizes with container names resolved
  - warning when no log rotation (`max-size`) is configured
- Files over 50 MB on the target filesystem
- Deleted-but-still-open files (space not freed until the process restarts)
- Printed cleanup hints (never executed)

## Requirements

- Bash 4+, GNU coreutils, `find`, `awk` (all present on a default Ubuntu install)
- `root` or `sudo` for complete results (without it, `/var/lib/docker` and parts of `/var/log` are unreadable)
- Optional: `docker` for the Docker sections, `lsof` for the deleted-but-open files check (`sudo apt install lsof`)

## Installation

```bash
git clone https://github.com/Masterpeace-QA/vm-disk-usage.git
cd vm-disk-usage
sudo install -m 755 diskwatch.sh /usr/local/bin/diskwatch.sh
```

Or run it directly from the cloned folder:

```bash
sudo bash diskwatch.sh
```

## Usage

```
sudo diskwatch.sh [-t PERCENT] [-p MOUNTPOINT] [-n TOPN] [-q]
```

| Option | Description | Default |
|--------|-------------|---------|
| `-t PERCENT` | Usage threshold (1-100) that triggers the ALERT status | `80` |
| `-p MOUNTPOINT` | Filesystem to analyse in detail (see note below) | `/` |
| `-n TOPN` | Number of top entries shown per section | `15` |
| `-q` | Quiet mode for cron: print nothing unless usage is at or above the threshold | off |
| `-h` | Show help | |

With `-p` set to a mountpoint other than `/`, only paths that live on that filesystem are analysed, so the `/var`, known-consumers, `/var/log` and journal sections are skipped unless they are on that mount. The Docker sections always cover the whole system.

### Exit status

| Code | Meaning |
|------|---------|
| `0` | Usage is below the threshold |
| `1` | Usage is at or above the threshold |
| `2` | Invalid options or arguments |

### Examples

```bash
# Full report
sudo diskwatch.sh

# Alert at 85%, show top 20 entries per section
sudo diskwatch.sh -t 85 -n 20

# Analyse a separate data volume
sudo diskwatch.sh -p /data
```

## Running from cron

Quiet mode only produces output when the threshold is reached, so cron mail or a log file stays empty while everything is healthy:

```cron
0 * * * * /usr/local/bin/diskwatch.sh -q -t 85 >> /var/log/diskwatch.log 2>&1
```

Colour codes are only printed when output goes to a terminal, so the log file and cron mail stay plain text.

To get an email, make sure a mail transport is configured and set `MAILTO=you@example.com` at the top of the crontab (and drop the `>>` redirect).

## Example output

Abridged and illustrative; the values on your server will differ.

```
Disk report for web-01 - 2026-01-15 10:00:01 UTC

== Filesystem usage ==
Filesystem     Type  Size  Used Avail Use% Mounted on
/dev/sda1      ext4   50G   44G  3.9G  92% /

ALERT: / is 92% full (threshold 85%)

== Known space consumers (summary) ==
         21GB  Docker data root               /var/lib/docker
        9.8GB  System logs                    /var/log
        3.1GB  Snap packages                  /var/lib/snapd
        1.2GB  APT package cache              /var/cache/apt

== Docker: container log files (json-file driver) - often the hidden culprit ==
    8421.3 MB  app-backend                    /var/lib/docker/containers/<id>/<id>-json.log

Default logging driver: json-file
NOTE: no log rotation (max-size) configured in /etc/docker/daemon.json - container logs can grow unbounded.

== Suggested cleanup commands (review before running) ==
  ...
```

## Common fixes

These are printed by the script as hints. Review before running.

```bash
# Journald
sudo journalctl --vacuum-size=500M

# APT
sudo apt clean && sudo apt autoremove --purge

# Docker unused data (removes ALL unused images and volumes!)
docker system prune -a --volumes
docker builder prune
```

### Stop Docker logs from growing forever

Add log rotation to `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

Then `sudo systemctl restart docker`. The setting applies to newly created containers; recreate existing ones to pick it up.

## Notes

- `du` is run with `-x`, so the scan stays on one filesystem and ignores other mounts.
- On large filesystems the full scan can take a while. Use `-p` to target a specific mount.
- Docker and containerd paths are read directly, so run the script as root.

## License

Released under the [MIT License](LICENSE).
