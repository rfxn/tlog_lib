#!/usr/bin/env bats
# 03-tlog-standalone.bats — CLI wrapper tests for files/tlog
# Tests run the tlog script as a subprocess (not sourced functions).

load helpers/tlog-common

setup() {
	tlog_common_setup
	TLOG="${PROJECT_ROOT}/files/tlog"
	LOGFILE="$TEST_TMPDIR/test.log"
	printf 'line one\nline two\nline three\n' > "$LOGFILE"
	export BASERUN
}

teardown() {
	tlog_teardown
}

# ===================================================================
# Standalone CLI Wrapper (10 tests)
# ===================================================================

@test "tlog: missing arguments shows usage" {
	run "$TLOG"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"usage:"* ]]
}

@test "tlog: first run initializes cursor and outputs nothing" {
	run "$TLOG" "$LOGFILE" "testlog"
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
	[[ -f "$BASERUN/testlog" ]]
}

@test "tlog: growth outputs only new content" {
	"$TLOG" "$LOGFILE" "testlog" >/dev/null 2>&1
	printf 'line four\n' >> "$LOGFILE"
	run "$TLOG" "$LOGFILE" "testlog"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "line four" ]]
}

@test "tlog: no-change produces no output" {
	"$TLOG" "$LOGFILE" "testlog" >/dev/null 2>&1
	run "$TLOG" "$LOGFILE" "testlog"
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "tlog: multiple new lines all output" {
	"$TLOG" "$LOGFILE" "testlog" >/dev/null 2>&1
	printf 'line four\nline five\nline six\n' >> "$LOGFILE"
	run "$TLOG" "$LOGFILE" "testlog"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"line four"* ]]
	[[ "$output" == *"line five"* ]]
	[[ "$output" == *"line six"* ]]
}

@test "tlog: rotation outputs new file content" {
	"$TLOG" "$LOGFILE" "testlog" >/dev/null 2>&1
	printf 'line four\n' >> "$LOGFILE"
	cp "$LOGFILE" "${LOGFILE}.1"
	printf 'new file line one\n' > "$LOGFILE"
	run "$TLOG" "$LOGFILE" "testlog"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"new file line one"* ]]
}

@test "tlog: missing file exits with error" {
	run "$TLOG" "$TEST_TMPDIR/nonexistent.log" "testlog"
	[[ "$status" -eq 1 ]]
}

@test "tlog: mode argument selects lines mode" {
	run "$TLOG" "$LOGFILE" "testlog" "lines"
	[[ "$status" -eq 0 ]]
	local cursor
	read -r cursor < "$BASERUN/testlog"
	[[ "$cursor" == L:* ]]
}

@test "tlog: TLOG_MODE env selects lines mode when no arg" {
	TLOG_MODE="lines" run "$TLOG" "$LOGFILE" "testlog"
	[[ "$status" -eq 0 ]]
	local cursor
	read -r cursor < "$BASERUN/testlog"
	[[ "$cursor" == L:* ]]
}

@test "tlog: explicit mode argument overrides TLOG_MODE env" {
	TLOG_MODE="lines" run "$TLOG" "$LOGFILE" "testlog" "bytes"
	[[ "$status" -eq 0 ]]
	local cursor
	read -r cursor < "$BASERUN/testlog"
	# Explicit bytes overrides TLOG_MODE=lines — no L: prefix
	[[ "$cursor" != L:* ]]
	local numeric_pat='^[0-9]+$'
	[[ "$cursor" =~ $numeric_pat ]]
}
