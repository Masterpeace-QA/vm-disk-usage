# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- MIT `LICENSE`.
- GitHub Actions workflow that runs ShellCheck and a few smoke tests on every push and pull request.
- Exit status for `diskwatch.sh`: `1` when usage is at or above the threshold, `2` for invalid usage.
- `.gitignore` and this changelog.
- README: exit status section, a CI badge and an example of the report output.

### Changed
- With `-p` set to a mountpoint other than `/`, only paths on that filesystem are analysed
  (the `/var`, known-consumers, `/var/log` and journal sections are skipped otherwise).
  Behaviour with the default `-p /` is unchanged. The Docker sections are still system-wide.
- Unknown options now print the help text to stderr and exit `2` instead of exiting `0`.

### Fixed
- Quiet mode (`-q`) no longer prints the "not running as root" warning when usage is below the threshold.
- ANSI colour codes are only emitted when output goes to a terminal, so logs and cron mail stay clean.
- `-t`, `-n` and `-p` values are validated.
- Placeholder in the README clone URL.
