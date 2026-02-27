# tlog_lib — Incremental Log Reader for Bash

[![CI](https://github.com/rfxn/tlog_lib/actions/workflows/ci.yml/badge.svg)](https://github.com/rfxn/tlog_lib/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-2.0.1-blue.svg)](https://github.com/rfxn/tlog_lib)
[![Bash](https://img.shields.io/badge/bash-4.1%2B-green.svg)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-GPL%20v2-orange.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
[![Platform](https://img.shields.io/badge/platform-linux-lightgrey.svg)](https://github.com/rfxn/tlog_lib#platform-support)

A shared Bash library for reading new content from growing log files using
cursor-based position tracking. Source it into your script, call `tlog_read`,
and get only the lines written since the last invocation — with rotation
detection, atomic cursor writes, and optional locking built in.

```bash
source /opt/myapp/lib/tlog_lib.sh

# Read new lines from syslog since last call
tlog_read "/var/log/syslog" "syslog" "/opt/myapp/tmp"
```

## Features

- **Two tracking modes** — byte-offset (`tail -c`) for maximum throughput or
  line-count (`tail -n`) for guaranteed whole-line output
- **Log rotation aware** — detects `.1` and compressed variants (`.1.gz`,
  `.1.xz`, `.1.bz2`, `.1.zst`, `.1.lz4`) with runtime tool detection, outputs
  the remainder from the old file plus the new file, then resets the cursor;
  works with both `create` and `copytruncate` logrotate strategies
- **Atomic cursor writes** — `mktemp` + `mv -f` ensures cursors are never
  empty or half-written, even on crash or OOM kill
- **Optional flock locking** — prevents cursor corruption when multiple
  processes (cron + daemon) read the same log concurrently
- **Cursor validation** — corrupt or garbage cursor files are detected via
  regex and auto-reset with a warning, never propagated
- **Systemd journal support** — optional fallback to `journalctl` when the
  log file doesn't exist, with cursor and timestamp tracking
- **Stale cursor protection** — cursor mtime is touched on every read,
  preventing mtime-based cleanup from deleting active cursors
- **Structured exit codes** — callers can distinguish success, file errors,
  cursor corruption, journal unavailability, and lock contention
- **Zero external dependencies** — POSIX coreutils only (`stat`, `tail`, `wc`,
  `mktemp`, `mv`, `flock`); compression tools (`gzip`, `xz`, `bzip2`, `zstd`,
  `lz4`) detected at runtime and used opportunistically for rotated files

## Platform Support

tlog_lib targets deep legacy through current production distributions. All
functions use only POSIX/coreutils primitives available across this range:

| Distribution | Versions | Bash | Notes |
|---|---|---|---|
| CentOS | 6, 7 | 4.1, 4.2 | No systemd on 6; journal functions gracefully skip |
| Rocky Linux | 8, 9, 10 | 4.4, 5.1, 5.2 | Primary RHEL-family targets |
| Debian | 12 | 5.2 | Primary test target |
| Ubuntu | 12.04, 14.04, 20.04, 24.04 | 4.2–5.2 | No systemd on 12.04/14.04 |
| Slackware, Gentoo, FreeBSD | Various | 4.1+ | Functional where Bash is available |

**Minimum requirement: Bash 4.1** (ships with CentOS 6, released 2011). No
Bash 4.2+ features are used — no `${var,,}`, `mapfile -d`, `declare -n`, or
`$EPOCHSECONDS`. The `flock` command (util-linux) is required only when
`TLOG_FLOCK=1`; `journalctl` only for journal functions and is gracefully
skipped when absent.

## Quick Start

### As a Library (Recommended)

Source `tlog_lib.sh` into your Bash script and call functions directly. This
avoids fork/exec overhead — each call is a function invocation, not a subprocess.

```bash
#!/bin/bash
source /opt/myapp/lib/tlog_lib.sh

# Use a project-owned directory for cursors — never /tmp (see Security below)
CURSOR_DIR="/opt/myapp/tmp"
mkdir -p "$CURSOR_DIR"
chmod 750 "$CURSOR_DIR"
chown root:root "$CURSOR_DIR"

# Process new syslog entries since last run
new_lines=$(tlog_read "/var/log/syslog" "syslog" "$CURSOR_DIR")
if [[ -n "$new_lines" ]]; then
    echo "$new_lines" | grep "ERROR" | while IFS= read -r line; do
        # handle each error line
        echo "Alert: $line"
    done
fi
```

### As a Standalone Script

The `tlog` wrapper provides a CLI interface for use from cron jobs or scripts
that can't source the library. It supports the original positional interface
plus option flags and subcommands:

```bash
# Incremental read (positional — backward compatible)
tlog /var/log/auth.log auth_tracker
tlog /var/log/mail.log mail_tracker lines

# Incremental read with option flags
tlog -m lines /var/log/mail.log mail_tracker
tlog -f -b /opt/myapp/tmp /var/log/syslog syslog
tlog --first-run full /var/log/app.log app

# Pipe new entries to a processor
tlog /var/log/syslog syslog | grep "CRIT" | alert-handler

# Full file read (no cursor tracking)
tlog --full /var/log/syslog
tlog --full /var/log/syslog 500

# Check cursor state
tlog --status syslog
tlog --status syslog /var/log/syslog

# Reset tracking for a log
tlog --reset auth

# Adjust cursor after trimming bytes from top of log
tlog --adjust mylog 4096

# Help and version
tlog -h              # short usage
tlog --help          # detailed help with examples
tlog -v              # version banner
```

**Options:**

| Flag | Effect |
|------|--------|
| `-m, --mode MODE` | Set tracking mode (`bytes` or `lines`) |
| `-b, --baserun DIR` | Override cursor storage directory |
| `-f, --flock` | Enable flock-based cursor locking |
| `--first-run skip\|full` | First-run behavior (default: `skip`) |
| `-v, --version` | Show version banner and exit |
| `-h` | Show short usage and exit |
| `--help` | Show detailed help with examples and exit |

**Subcommands:**

| Subcommand | Description |
|------------|-------------|
| `--full <file> [max_lines]` | Read entire file without cursor tracking |
| `--status <name> [file]` | Display cursor state (read-only) |
| `--reset <name>` | Delete cursor and related files |
| `--adjust <name> <delta>` | Subtract delta from stored cursor |

## Securing Cursor Storage

Cursor files track where in a log file your application last read. An attacker
who can write to cursor files can cause your application to skip log entries
(hiding intrusion evidence) or re-process old entries (triggering false
alerts). The cursor directory must be treated as security-sensitive state.

**Rules:**

1. **Never use `/tmp` or any world-writable directory** for cursor storage.
   The source tree defaults `BASERUN` to `/tmp` for portability — your
   installer must replace this with a project-controlled path (see
   [Installation](#installation)).

2. **Own the directory as root** with restrictive permissions:
   ```bash
   mkdir -p /opt/myapp/tmp
   chown root:root /opt/myapp/tmp
   chmod 750 /opt/myapp/tmp
   ```

3. **Place cursors inside your application's install tree** (e.g.,
   `/opt/myapp/tmp/`, `/usr/local/myapp/tmp/`). This keeps cursor files
   under the same ownership and access controls as the application itself.

4. **The standalone `tlog` script validates `tlog_lib.sh` before sourcing**:
   it checks that the library is owned by root and not world-writable. This
   prevents a local privilege escalation where a tampered library is sourced
   by a root-owned cron job.

**What can go wrong with `/tmp`:**

| Attack | Impact |
|--------|--------|
| Symlink attack — attacker creates `$BASERUN/syslog` as symlink to `/etc/passwd` | Cursor write overwrites the target file |
| Cursor poisoning — attacker writes a crafted value to the cursor file | Application skips log data or re-reads old data |
| State leakage — cursor filenames reveal which logs your application monitors | Information disclosure to unprivileged local users |
| Race condition — attacker deletes cursor between read and write | Application falls back to first-run, potentially re-processing entire log |

## Tracking Modes

Every call to `tlog_read` operates in one of two modes:

| Mode | Cursor Unit | Reads Via | Best For |
|------|-------------|-----------|----------|
| `bytes` (default) | byte offset | `tail -c` | High throughput; output piped to `grep`/`awk` |
| `lines` | line count | `tail -n` | Email digests; any context requiring complete lines |

**Bytes mode** is the default and the better choice for most cases. It tracks
the exact byte position in the file and reads precisely from that offset.
Output may start mid-line after rotation or cursor reset, which is fine when
piping through pattern matching.

**Lines mode** guarantees every read starts and ends on a newline boundary.
Use it when output goes directly to humans or into reports where truncated
lines would be confusing.

### Setting the Mode

Mode is resolved in this order (first wins):

1. Explicit function argument: `tlog_read "$file" "$name" "$dir" "lines"`
2. Environment variable: `TLOG_MODE=lines`
3. Default: `bytes`

### Cursor File Format

Cursors are plain-text files in the `baserun` directory, named after the
`tlog_name` argument:

```
# Byte-mode cursor (bare number):
4096000

# Line-mode cursor (L: prefix):
L:52341
```

If a cursor was written in one mode and read in another, the library detects
the mismatch, resets the cursor to the current file position, and emits a
warning on stderr. This prevents unit confusion (e.g., interpreting a byte
count as a line count).

## API Reference

### tlog_read(file, tlog_name, baserun [, mode])

Core incremental reader. Outputs new content since the last call to stdout.

**Arguments:**
- `file` — path to the log file
- `tlog_name` — cursor identifier (becomes filename in `baserun`)
- `baserun` — directory for cursor storage (must be root-owned, not world-writable)
- `mode` — optional: `bytes` (default) or `lines`

**Behavior:**
- **First run** — records current file size/lines, outputs nothing (or entire
  file if `TLOG_FIRST_RUN=full`)
- **Growth** — outputs the delta between stored cursor and current size
- **Rotation** — detects file shrinkage, reads remainder from rotated file
  (`.1`, `.1.gz`, `.1.xz`, `.1.bz2`, `.1.zst`, `.1.lz4`), then reads all
  of the current file
- **No change** — outputs nothing, touches cursor mtime

**Returns:** 0 on success, 1 on invalid input (missing file, bad path,
invalid mode), 2 on cursor corruption (auto-reset), 3 if journal
unavailable, 4 if lock not acquired.

```bash
# Basic usage — cursor stored in project-owned directory
tlog_read "/var/log/auth.log" "auth" "/opt/myapp/tmp"

# Line mode for email digest
tlog_read "/var/log/app.log" "digest" "/opt/myapp/tmp" "lines" > /opt/myapp/tmp/.digest.txt

# With flock for concurrent access
TLOG_FLOCK=1 tlog_read "/var/log/syslog" "syslog" "/opt/myapp/tmp"
```

### tlog_read_full(file, max_lines)

Read an entire file without cursor tracking. Useful for one-shot scans.

```bash
# Entire file
tlog_read_full "/var/log/syslog"

# Last 500 lines
tlog_read_full "/var/log/syslog" 500
```

### tlog_adjust_cursor(tlog_name, baserun, delta_removed)

Subtract a value from a stored cursor after an in-place log trim. Detects
the cursor's mode automatically and uses the appropriate unit. Clamps to
zero if the subtraction would go negative.

```bash
# After trimming 100 lines from the top of a file:
bytes_removed=$(head -n 100 "$logfile" | wc -c)
# Trim the file (preserve inode for inotifywait / tail -f consumers)
tail -n +101 "$logfile" > "${logfile}.tmp" && mv -f "${logfile}.tmp" "$logfile"
# Adjust the byte-mode cursor
tlog_adjust_cursor "mylog" "/opt/myapp/tmp" "$bytes_removed"
```

### tlog_advance_cursors(baserun, log_pairs)

Fast-forward cursors for multiple files to their current positions without
reading content. Input is newline-separated `FILE|TAG` pairs.

```bash
pairs="/var/log/auth.log|auth
/var/log/syslog|syslog
/var/log/mail.log|mail"

tlog_advance_cursors "/opt/myapp/tmp" "$pairs"
```

### tlog_get_file_size(file) / tlog_get_line_count(file)

Utility functions that output byte size or line count on stdout.

```bash
size=$(tlog_get_file_size "/var/log/syslog")
lines=$(tlog_get_line_count "/var/log/syslog")
```

### Journal Functions

For systems using systemd journal instead of (or alongside) traditional log
files. Register your service mappings, then read from the journal the same
way you'd read from a file.

```bash
source /opt/myapp/lib/tlog_lib.sh

# Register service-to-journalctl filter mappings
tlog_journal_register "sshd" "SYSLOG_IDENTIFIER=sshd"
tlog_journal_register "postfix" "SYSLOG_IDENTIFIER=postfix"

# Incremental journal read (cursor-tracked)
tlog_journal_read "sshd" "/opt/myapp/tmp"

# Full journal read (no cursor, with timeout and line limit)
tlog_journal_read_full "postfix" 30 1000
```

**`tlog_journal_register(name, filter)`** — register a mapping from a
logical name to a journalctl filter string.

**`tlog_journal_filter(name)`** — look up the filter for a registered name.
Returns 1 for unregistered names.

**`tlog_journal_read(tlog_name, baserun)`** — cursor-based journal reader.
First run captures the cursor position and outputs nothing. Subsequent runs
output new entries since the stored cursor, with timestamp fallback.

**`tlog_journal_read_full(tlog_name, scan_timeout, max_lines)`** — full
journal read without cursor tracking. Supports timeout (via `timeout` command)
and line limits.

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `TLOG_MODE` | `bytes` | Default tracking mode when not passed as argument |
| `TLOG_FLOCK` | `0` | Set to `1` to enable flock-based cursor locking |
| `TLOG_FIRST_RUN` | `skip` | First-run behavior: `skip` (no output) or `full` (entire file) |
| `LOG_SOURCE` | — | Set to `file` to disable journal fallback when a file is missing |
| `SCAN_TIMEOUT` | `0` | Journal full-read timeout in seconds |
| `SCAN_MAX_LINES` | `0` | Journal full-read line limit |

## Exit Codes

| Code | Meaning | Recommended Action |
|------|---------|-------------------|
| 0 | Success (content output or no new content) | Continue normally |
| 1 | Invalid input (missing file, bad path, invalid mode, bad cursor name) | Check arguments |
| 2 | Cursor corrupt (auto-reset performed) | Log warning, continue |
| 3 | Journal unavailable (`journalctl` not found) | Fall back to file mode |
| 4 | Lock acquisition failed (`TLOG_FLOCK=1`) | Retry on next cycle |

## Examples

### Monitor a Log File from Cron

```bash
#!/bin/bash
# /etc/cron.d/check-errors — run every 5 minutes
source /opt/myapp/lib/tlog_lib.sh

# Cursor directory: project-owned, root:root 750
# Never use /tmp — cron runs as root and cursors become symlink targets
CURSOR_DIR="/opt/myapp/tmp"

errors=$(tlog_read "/var/log/myapp/error.log" "errors" "$CURSOR_DIR")
if [[ -n "$errors" ]]; then
    echo "$errors" | mail -s "New errors on $(hostname)" admin@example.com
fi
```

### Concurrent Daemon + Cron

When a long-running daemon and a cron job both read the same log, enable
flock to prevent cursor races. Both processes must use the same `baserun`
directory so they share the cursor file and its `.lock`:

```bash
# In the daemon loop:
export TLOG_FLOCK=1
while true; do
    new_data=$(tlog_read "/var/log/events.log" "events" "/opt/myapp/tmp")
    [[ -n "$new_data" ]] && process_events "$new_data"
    sleep 10
done

# In the cron job (same cursor directory, same flock):
export TLOG_FLOCK=1
tlog_read "/var/log/events.log" "events" "/opt/myapp/tmp" | generate_report
```

The flock uses `$baserun/${tlog_name}.lock` — a separate file from the cursor
itself. The lock is held only for the duration of the read-modify-write cycle,
not while processing output.

### Line-Mode Digest Email

```bash
#!/bin/bash
source /opt/myapp/lib/tlog_lib.sh

# Use line mode so the email body has complete lines
# Temporary output goes to a mktemp file, not a predictable /tmp path
digest_tmp=$(mktemp /opt/myapp/tmp/.digest.XXXXXX)

tlog_read "/var/log/auth.log" "daily-digest" "/opt/myapp/tmp" "lines" \
    > "$digest_tmp"

if [[ -s "$digest_tmp" ]]; then
    mail -s "Daily auth digest" admin@example.com < "$digest_tmp"
fi
rm -f "$digest_tmp"
```

### Handle Log Rotation Gracefully

No special handling needed — `tlog_read` detects rotation automatically:

```bash
# This works even when logrotate runs between calls.
# If /var/log/syslog was rotated to /var/log/syslog.1 (or .1.gz,
# .1.xz, .1.bz2, .1.zst, .1.lz4), tlog_read outputs the remainder
# from the rotated file, then the full content of the new file.
# Compressed rotated files are decompressed via pipe — never on disk.
# Works with both 'create' and 'copytruncate' logrotate strategies.
tlog_read "/var/log/syslog" "syslog" "/opt/myapp/tmp"
```

### Adjust Cursor After In-Place Trim

When you trim lines from the top of a log file (preserving the inode for
`inotifywait` or `tail -f` consumers), adjust the cursor so it doesn't
skip content or re-read old lines:

```bash
trim=1000  # lines to remove from top

# Calculate bytes being removed (for a byte-mode cursor)
bytes_removed=$(head -n "$trim" "$logfile" | wc -c)

# Trim the file (preserve inode via cat overwrite, not mv)
tail -n +"$((trim + 1))" "$logfile" > "${logfile}.tmp"
cat "${logfile}.tmp" > "$logfile"
rm -f "${logfile}.tmp"

# Adjust the cursor — mode-aware, clamps to 0 on over-subtraction
tlog_adjust_cursor "mylog" "/opt/myapp/tmp" "$bytes_removed"
```

### Journal Fallback

On journal-only systems (no persistent `/var/log/` files), register your
service mappings and `tlog_read` falls back to `journalctl` automatically
when the file argument doesn't exist. This covers CentOS 7+ and modern
distributions where syslog may not write traditional files:

```bash
source /opt/myapp/lib/tlog_lib.sh

tlog_journal_register "sshd" "SYSLOG_IDENTIFIER=sshd"
tlog_journal_register "nginx" "_SYSTEMD_UNIT=nginx.service"

# If /var/log/auth.log exists, reads the file.
# If it doesn't exist, reads from the journal.
# Journal cursors are stored in the same baserun directory.
tlog_read "/var/log/auth.log" "sshd" "/opt/myapp/tmp"

# Force file-only mode (no journal fallback)
LOG_SOURCE=file tlog_read "/var/log/auth.log" "sshd" "/opt/myapp/tmp"
```

On pre-systemd systems (CentOS 6, Ubuntu 12.04/14.04), journal functions
return exit code 3 and the caller can handle the fallback as needed.

## Installation

tlog_lib is designed to be embedded in your project, not installed globally.
Copy the two files into your project tree and lock down permissions:

```bash
# Copy library and wrapper into your project
cp files/tlog_lib.sh /opt/myapp/lib/
cp files/tlog /opt/myapp/lib/
chown root:root /opt/myapp/lib/tlog_lib.sh /opt/myapp/lib/tlog
chmod 750 /opt/myapp/lib/tlog_lib.sh /opt/myapp/lib/tlog

# Create a secure cursor directory inside your install tree
mkdir -p /opt/myapp/tmp
chown root:root /opt/myapp/tmp
chmod 750 /opt/myapp/tmp

# Replace the source-tree /tmp default with your project's cursor path.
# This is mandatory — the source tree uses /tmp as a portable placeholder;
# installed copies must never default to a world-writable directory.
sed -i 's|BASERUN="${BASERUN:-/tmp}"|BASERUN="${BASERUN:-/opt/myapp/tmp}"|' \
    /opt/myapp/lib/tlog
```

The `tlog_lib.sh` library itself has no hardcoded paths — cursor storage is
always passed explicitly via the `baserun` argument. The sed replacement only
applies to the standalone `tlog` wrapper, which needs a default when no
`BASERUN` environment variable is set.

## Testing

```bash
make -C tests test           # Debian 12 (primary)
make -C tests test-rocky9    # Rocky 9
make -C tests test-all       # Full 9-OS matrix
```

Tests run inside Docker containers via BATS. 133 tests cover both tracking
modes, rotation (including copytruncate and multi-format compression),
cursor validation and corruption, flock locking, atomic writes, journal
functions, and the standalone CLI wrapper (58 tests covering option
parsing, subcommands, help/version, false-positive verification, path
traversal rejection, and mode validation).

## License

Copyright (C) 2002-2026, [R-fx Networks](https://www.rfxn.com)
— Ryan MacDonald <ryan@rfxn.com>

GNU General Public License v2. See the source files for the full license text.
