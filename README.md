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
| `-t PERCENT` | Usage threshold that triggers the ALERT status | `80` |
| `-p MOUNTPOINT` | Filesystem to analyse in detail | `/` |
| `-n TOPN` | Number of top entries shown per section | `15` |
| `-q` | Quiet mode for cron: print nothing unless usage is at or above the threshold | off |
| `-h` | Show help | |

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

To get an email, make sure a mail transport is configured and set `MAILTO=you@example.com` at the top of the crontab (and drop the `>>` redirect).

## Sample output sections

```
== Filesystem usage ==
== Inode usage ==
== Largest top-level directories on / ==
== Largest directories under /var ==
== Known space consumers (summary) ==
== Largest log files in /var/log ==
== Systemd journal ==
== Docker: overall usage ==
== Docker: images by size ==
== Docker: container log files ==
== Largest files on / (>50 MB) ==
== Deleted files still held open by processes ==
== Suggested cleanup commands ==
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

Add a license of your choice (for example MIT) as a `LICENSE` file.
