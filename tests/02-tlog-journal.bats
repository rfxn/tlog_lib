#!/usr/bin/env bats
# 02-tlog-journal.bats — Journal function tests for tlog_lib.sh
# Tests: filter mapping registry, journal read, journal dispatch via tlog_read,
# journal read full.

load helpers/tlog-common

setup() {
	tlog_common_setup

	# Register test journal mappings via the library's API
	tlog_journal_register "sshd" "SYSLOG_IDENTIFIER=sshd"
	tlog_journal_register "courier" "SYSLOG_IDENTIFIER=couriertcpd"
	tlog_journal_register "sendmail" "SYSLOG_IDENTIFIER=sm-mta"
	tlog_journal_register "exim_authfail" "SYSLOG_IDENTIFIER=exim4 + SYSLOG_IDENTIFIER=exim"

	# Create mock journalctl
	MOCK_BIN="$TEST_TMPDIR/mock_bin"
	mkdir -p "$MOCK_BIN"

	cat > "$MOCK_BIN/journalctl" <<'MOCKEOF'
#!/bin/bash
# Mock journalctl for tlog_lib tests
# Behavior dispatch based on arguments

ARGS="$*"

# --show-cursor (first run / cursor capture)
if [[ "$ARGS" == *"--show-cursor"* ]]; then
	echo "-- cursor: s=test_cursor_abc123"
	exit 0
fi

# --after-cursor=INVALID_CURSOR (invalid cursor)
if [[ "$ARGS" == *"--after-cursor=INVALID"* ]]; then
	exit 1
fi

# --after-cursor= (subsequent read)
if [[ "$ARGS" == *"--after-cursor="* ]]; then
	echo "Feb 26 12:00:01 testhost sshd[1234]: mock journal line one"
	echo "Feb 26 12:00:02 testhost sshd[1235]: mock journal line two"
	exit 0
fi

# --since=@ (timestamp fallback)
if [[ "$ARGS" == *"--since=@"* ]]; then
	echo "Feb 26 12:00:03 testhost sshd[1236]: mock journal fallback line"
	exit 0
fi

# Default: output some lines
echo "Feb 26 12:00:00 testhost sshd[1230]: mock default output"
exit 0
MOCKEOF
	chmod +x "$MOCK_BIN/journalctl"

	# Allow journal dispatch
	export LOG_SOURCE=""
	export PATH="$MOCK_BIN:$PATH"
}

teardown() {
	tlog_teardown
}

# ===================================================================
# Filter Mappings (5 tests)
# ===================================================================

@test "tlog_journal_filter: sshd maps to SYSLOG_IDENTIFIER=sshd" {
	local result
	result=$(tlog_journal_filter "sshd")
	[[ "$result" == "SYSLOG_IDENTIFIER=sshd" ]]
}

@test "tlog_journal_filter: courier maps to couriertcpd" {
	local result
	result=$(tlog_journal_filter "courier")
	[[ "$result" == "SYSLOG_IDENTIFIER=couriertcpd" ]]
}

@test "tlog_journal_filter: sendmail maps to sm-mta" {
	local result
	result=$(tlog_journal_filter "sendmail")
	[[ "$result" == "SYSLOG_IDENTIFIER=sm-mta" ]]
}

@test "tlog_journal_filter: exim_authfail maps to dual exim identifiers" {
	local result
	result=$(tlog_journal_filter "exim_authfail")
	[[ "$result" == "SYSLOG_IDENTIFIER=exim4 + SYSLOG_IDENTIFIER=exim" ]]
}

@test "tlog_journal_filter: unknown identifier returns exit 1" {
	run tlog_journal_filter "completely_unknown_service"
	[[ "$status" -eq 1 ]]
}

# ===================================================================
# Journal Read (7 tests)
# ===================================================================

@test "tlog_journal_read: first run outputs nothing and creates cursor" {
	run tlog_journal_read "sshd" "$BASERUN"
	[[ "$status" -eq 0 ]]
	# First run: output nothing
	[[ -z "$output" ]]
	# Cursor file created
	[[ -f "$BASERUN/sshd" ]]
	local cursor
	read -r cursor < "$BASERUN/sshd"
	[[ -n "$cursor" ]]
}

@test "tlog_journal_read: second run outputs new lines" {
	# First run
	tlog_journal_read "sshd" "$BASERUN" >/dev/null 2>&1
	# Second run
	run tlog_journal_read "sshd" "$BASERUN"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"mock journal line one"* ]]
	[[ "$output" == *"mock journal line two"* ]]
}

@test "tlog_journal_read: cursor updated on subsequent read" {
	tlog_journal_read "sshd" "$BASERUN" >/dev/null 2>&1
	local cursor_first
	read -r cursor_first < "$BASERUN/sshd"
	tlog_journal_read "sshd" "$BASERUN" >/dev/null 2>&1
	local cursor_second
	read -r cursor_second < "$BASERUN/sshd"
	# Cursor should be set (both are from mock --show-cursor)
	[[ -n "$cursor_second" ]]
}

@test "tlog_journal_read: timestamp file contains epoch integer" {
	tlog_journal_read "sshd" "$BASERUN" >/dev/null 2>&1
	[[ -f "$BASERUN/sshd.jts" ]]
	local jts
	read -r jts < "$BASERUN/sshd.jts"
	local numeric_pat='^[0-9]+$'
	[[ "$jts" =~ $numeric_pat ]]
}

@test "tlog_journal_read: invalid cursor falls back to timestamp" {
	# Write invalid cursor
	printf 'INVALID_CURSOR_DATA\n' > "$BASERUN/sshd"
	# Write valid timestamp
	printf '%s\n' "$(date +%s)" > "$BASERUN/sshd.jts"
	run tlog_journal_read "sshd" "$BASERUN"
	[[ "$status" -eq 0 ]]
	# Mock returns "mock journal fallback line" for --since=@
	[[ "$output" == *"mock journal fallback line"* ]]
}

@test "tlog_journal_read: unknown service returns exit 1" {
	run tlog_journal_read "unknown_service" "$BASERUN"
	[[ "$status" -eq 1 ]]
}

@test "tlog_journal_read: no journalctl returns exit 3" {
	# Run in a subshell with nonexistent PATH to ensure journalctl is unavailable
	run bash -c '
		unset _TLOG_LIB_LOADED
		export PATH="/nonexistent"
		source "'"${PROJECT_ROOT}"'/files/tlog_lib.sh"
		tlog_journal_register "sshd" "SYSLOG_IDENTIFIER=sshd"
		tlog_journal_read "sshd" "'"$BASERUN"'"
	'
	[[ "$status" -eq 3 ]]
}

# ===================================================================
# Journal Dispatch via tlog_read (4 tests)
# ===================================================================

@test "tlog_read: file exists uses file mode not journal" {
	local logfile="$TEST_TMPDIR/existing.log"
	printf 'real file content\n' > "$logfile"
	LOG_SOURCE=""
	tlog_read "$logfile" "sshd" "$BASERUN" "bytes" >/dev/null 2>&1
	# FP: should create file-mode cursor, NOT .jts file
	[[ -f "$BASERUN/sshd" ]]
	[[ ! -f "$BASERUN/sshd.jts" ]]
	# Cursor should be numeric (file size), not journal cursor string
	local cursor
	read -r cursor < "$BASERUN/sshd"
	local numeric_pat='^[0-9]+$'
	[[ "$cursor" =~ $numeric_pat ]]
}

@test "tlog_read: file missing + journal dispatches to journal" {
	LOG_SOURCE=""
	run tlog_read "$TEST_TMPDIR/nonexistent.log" "sshd" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	# Journal cursor should be created
	[[ -f "$BASERUN/sshd" ]]
}

@test "tlog_read: file missing + unknown service returns exit 1" {
	LOG_SOURCE=""
	run tlog_read "$TEST_TMPDIR/nonexistent.log" "unknown_service" "$BASERUN" "bytes"
	[[ "$status" -eq 1 ]]
}

@test "tlog_read: LOG_SOURCE=file never attempts journal" {
	LOG_SOURCE="file"
	run tlog_read "$TEST_TMPDIR/nonexistent.log" "sshd" "$BASERUN" "bytes"
	[[ "$status" -eq 1 ]]
	# FP: no .jts file created
	[[ ! -f "$BASERUN/sshd.jts" ]]
}

# ===================================================================
# Journal Read Full (2 tests)
# ===================================================================

@test "tlog_journal_read_full: outputs lines for known service" {
	run tlog_journal_read_full "sshd" 0 10
	[[ "$status" -eq 0 ]]
	[[ -n "$output" ]]
}

@test "tlog_journal_read_full: unknown service returns exit 1" {
	run tlog_journal_read_full "unknown_service" 0 10
	[[ "$status" -eq 1 ]]
}

# ===================================================================
# tlog_advance_cursors journal branch (7 tests)
# ===================================================================

@test "tlog_advance_cursors: journal cursor created for missing file with registered tag" {
	# File does not exist, but sshd is registered → journal dispatch
	local pairs
	pairs=$(printf '/nonexistent/fake.log|sshd')
	tlog_advance_cursors "$BASERUN" "$pairs"
	# Cursor file should contain journal cursor from mock
	[[ -f "$BASERUN/sshd" ]]
	local cursor
	read -r cursor < "$BASERUN/sshd"
	[[ "$cursor" == "s=test_cursor_abc123" ]]
}

@test "tlog_advance_cursors: jts timestamp created for journal tag" {
	local pairs
	pairs=$(printf '/nonexistent/fake.log|sshd')
	tlog_advance_cursors "$BASERUN" "$pairs"
	# .jts file should exist with epoch timestamp
	[[ -f "$BASERUN/sshd.jts" ]]
	local jts
	read -r jts < "$BASERUN/sshd.jts"
	local numeric_pat='^[0-9]+$'
	[[ "$jts" =~ $numeric_pat ]]
}

@test "tlog_advance_cursors: unregistered tag skipped silently" {
	local pairs
	pairs=$(printf '/nonexistent/fake.log|unknown_service_xyz')
	tlog_advance_cursors "$BASERUN" "$pairs"
	# No cursor file for unregistered tag
	[[ ! -f "$BASERUN/unknown_service_xyz" ]]
}

@test "tlog_advance_cursors: mixed file and journal pairs" {
	# Create a real file for the file-cursor half of the test
	local logfile="$TEST_TMPDIR/mixed.log"
	printf 'line one\nline two\nline three\n' > "$logfile"
	# log1 exists (file cursor), sshd does not exist (journal cursor)
	local pairs
	pairs=$(printf '%s|log1\n/nonexistent/fake.log|sshd' "$logfile")
	tlog_advance_cursors "$BASERUN" "$pairs"
	# File cursor: byte size
	local c1
	read -r c1 < "$BASERUN/log1"
	local s1
	s1=$(stat -c %s "$logfile")
	[[ "$c1" == "$s1" ]]
	# Journal cursor: mock cursor string
	local c2
	read -r c2 < "$BASERUN/sshd"
	[[ "$c2" == "s=test_cursor_abc123" ]]
}

@test "tlog_advance_cursors: invalid mode returns exit 1" {
	local pairs
	pairs=$(printf '%s|log1' "$LOGFILE")
	TLOG_MODE="garbage" run tlog_advance_cursors "$BASERUN" "$pairs"
	[[ "$status" -eq 1 ]]
}

@test "tlog_advance_cursors: no journalctl skips journal tags silently" {
	run bash -c '
		unset _TLOG_LIB_LOADED
		export PATH="/nonexistent"
		source "'"${PROJECT_ROOT}"'/files/tlog_lib.sh"
		tlog_journal_register "sshd" "SYSLOG_IDENTIFIER=sshd"
		pairs=$(printf "/nonexistent/fake.log|sshd")
		tlog_advance_cursors "'"$BASERUN"'" "$pairs"
	'
	[[ "$status" -eq 0 ]]
	# No cursor created when journalctl unavailable
	[[ ! -f "$BASERUN/sshd" ]]
}

@test "tlog_advance_cursors: empty tag skipped" {
	local pairs
	pairs=$(printf '/some/file|')
	run tlog_advance_cursors "$BASERUN" "$pairs"
	[[ "$status" -eq 0 ]]
}

# ===================================================================
# Name Validation — Journal Functions (2 tests)
# ===================================================================

@test "tlog_journal_read rejects ../escape name" {
	run tlog_journal_read "../escape" "$BASERUN"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"invalid tlog_name"* ]]
}

@test "tlog_journal_read_full rejects ../escape name" {
	run tlog_journal_read_full "../escape" 0 10
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"invalid tlog_name"* ]]
}

# ===================================================================
# Journal Content Validation (4 tests)
# ===================================================================

@test "corrupt journal cursor with shell metacharacters resets to timestamp fallback" {
	# Write cursor with shell injection attempt
	printf '$(whoami)\n' > "$BASERUN/sshd"
	# Write valid timestamp
	printf '%s\n' "$(date +%s)" > "$BASERUN/sshd.jts"
	run tlog_journal_read "sshd" "$BASERUN"
	[[ "$status" -eq 0 ]]
	# Should warn about corrupt cursor
	[[ "$output" == *"corrupt journal cursor"* ]]
	# Mock returns "mock journal fallback line" for --since=@
	[[ "$output" == *"mock journal fallback line"* ]]
}

@test "corrupt journal timestamp with non-numeric resets" {
	# Write valid cursor
	printf 's=test_cursor_abc123\n' > "$BASERUN/sshd"
	# Write corrupt timestamp
	printf 'not-a-number\n' > "$BASERUN/sshd.jts"
	run tlog_journal_read "sshd" "$BASERUN"
	[[ "$status" -eq 0 ]]
	# Should warn about corrupt timestamp
	[[ "$output" == *"corrupt journal timestamp"* ]]
}

@test "valid cursor format accepted without corrupt warning" {
	# Write a valid systemd-style cursor
	printf 's=abc123def;i=1;b=deadbeef;m=cafe;t=12345;x=99\n' > "$BASERUN/sshd"
	printf '%s\n' "$(date +%s)" > "$BASERUN/sshd.jts"
	run tlog_journal_read "sshd" "$BASERUN"
	[[ "$status" -eq 0 ]]
	# FP: no corrupt warning
	[[ "$output" != *"corrupt journal cursor"* ]]
}

@test "both cursor and jts corrupt triggers first-run behavior" {
	# Write corrupt cursor
	printf '$(rm -rf /)\n' > "$BASERUN/sshd"
	# Write corrupt timestamp
	printf '$(date)\n' > "$BASERUN/sshd.jts"
	run tlog_journal_read "sshd" "$BASERUN"
	[[ "$status" -eq 0 ]]
	# Both cleared → first-run path: no content output (only warnings + first-run capture)
	# Filter out tlog: warning lines — remaining should be empty
	local content_lines
	content_lines=$(printf '%s\n' "$output" | grep -v '^tlog:' | grep -v '^$' || true)
	[[ -z "$content_lines" ]]
}
