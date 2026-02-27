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
# Standalone CLI Wrapper — backward-compatible positional (10 tests)
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

# ===================================================================
# Help & Version (6 tests)
# ===================================================================

@test "tlog: -v shows version and exits 0" {
	run "$TLOG" -v
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"tlog 2.0.1"* ]]
}

@test "tlog: --version shows version and exits 0" {
	run "$TLOG" --version
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"tlog 2.0.1"* ]]
	[[ "$output" == *"Copyright"* ]]
}

@test "tlog: -h shows short usage and exits 0" {
	run "$TLOG" -h
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"usage:"* ]]
	[[ "$output" == *"--full"* ]]
	[[ "$output" == *"--status"* ]]
}

@test "tlog: --help shows long help with examples and exits 0" {
	run "$TLOG" --help
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"EXAMPLES"* ]]
	[[ "$output" == *"DESCRIPTION"* ]]
	[[ "$output" == *"ENVIRONMENT"* ]]
}

@test "tlog: no args shows usage to stderr and exits 1" {
	run "$TLOG"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"usage:"* ]]
}

@test "tlog: -v works even when library is renamed" {
	local lib_path="${TLOG%/*}/tlog_lib.sh"
	local lib_backup="${lib_path}.bak"
	cp "$lib_path" "$lib_backup"
	mv "$lib_path" "${lib_path}.hidden"
	run "$TLOG" -v
	mv "${lib_path}.hidden" "$lib_path"
	rm -f "$lib_backup"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"tlog 2.0.1"* ]]
}

# ===================================================================
# Option Flags (7 tests)
# ===================================================================

@test "tlog: -m lines creates L: cursor" {
	run "$TLOG" -m lines "$LOGFILE" "testlog"
	[[ "$status" -eq 0 ]]
	local cursor
	read -r cursor < "$BASERUN/testlog"
	[[ "$cursor" == L:* ]]
}

@test "tlog: --mode bytes creates bare-number cursor" {
	run "$TLOG" --mode bytes "$LOGFILE" "testlog"
	[[ "$status" -eq 0 ]]
	local cursor
	read -r cursor < "$BASERUN/testlog"
	local numeric_pat='^[0-9]+$'
	[[ "$cursor" =~ $numeric_pat ]]
}

@test "tlog: -b DIR uses alternate baserun" {
	local alt_baserun="$TEST_TMPDIR/alt_tracking"
	mkdir -p "$alt_baserun"
	run "$TLOG" -b "$alt_baserun" "$LOGFILE" "testlog"
	[[ "$status" -eq 0 ]]
	[[ -f "$alt_baserun/testlog" ]]
	# Must not create cursor in default BASERUN
	[[ ! -f "$BASERUN/testlog" ]]
}

@test "tlog: -f creates .lock file during read" {
	run "$TLOG" -f "$LOGFILE" "testlog"
	[[ "$status" -eq 0 ]]
	# After read completes, .lock file should exist (created by flock)
	[[ -f "$BASERUN/testlog.lock" ]]
}

@test "tlog: --flock creates .lock file during read" {
	run "$TLOG" --flock "$LOGFILE" "testlog"
	[[ "$status" -eq 0 ]]
	[[ -f "$BASERUN/testlog.lock" ]]
}

@test "tlog: --first-run full outputs entire file on first run" {
	run "$TLOG" --first-run full "$LOGFILE" "testlog"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"line one"* ]]
	[[ "$output" == *"line two"* ]]
	[[ "$output" == *"line three"* ]]
}

@test "tlog: -m flag overridden by 3rd positional arg" {
	# -m lines sets TLOG_MODE, but positional 'bytes' should win
	run "$TLOG" -m lines "$LOGFILE" "testlog" "bytes"
	[[ "$status" -eq 0 ]]
	local cursor
	read -r cursor < "$BASERUN/testlog"
	# Positional bytes wins — no L: prefix
	[[ "$cursor" != L:* ]]
	local numeric_pat='^[0-9]+$'
	[[ "$cursor" =~ $numeric_pat ]]
}

# ===================================================================
# --full Subcommand (4 tests)
# ===================================================================

@test "tlog: --full outputs entire file" {
	run "$TLOG" --full "$LOGFILE"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"line one"* ]]
	[[ "$output" == *"line two"* ]]
	[[ "$output" == *"line three"* ]]
}

@test "tlog: --full with max_lines limits output" {
	printf 'line four\nline five\n' >> "$LOGFILE"
	run "$TLOG" --full "$LOGFILE" 2
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"line four"* ]]
	[[ "$output" == *"line five"* ]]
	[[ "$output" != *"line one"* ]]
}

@test "tlog: --full with missing file exits 1" {
	run "$TLOG" --full "$TEST_TMPDIR/nonexistent.log"
	[[ "$status" -eq 1 ]]
}

@test "tlog: FP --full does not create cursor files" {
	run "$TLOG" --full "$LOGFILE"
	[[ "$status" -eq 0 ]]
	# No cursor files should be created
	local count
	count=$(find "$BASERUN" -type f | wc -l)
	[[ "$count" -eq 0 ]]
}

# ===================================================================
# --status Subcommand (6 tests)
# ===================================================================

@test "tlog: --status with bytes cursor shows value" {
	"$TLOG" "$LOGFILE" "testlog" >/dev/null 2>&1
	run "$TLOG" --status "testlog"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"mode:   bytes"* ]]
	[[ "$output" == *"value:"* ]]
	[[ "$output" == *"state:  valid"* ]]
}

@test "tlog: --status with lines cursor shows mode" {
	"$TLOG" "$LOGFILE" "testlog" "lines" >/dev/null 2>&1
	run "$TLOG" --status "testlog"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"mode:   lines"* ]]
}

@test "tlog: --status with no cursor shows not initialized" {
	run "$TLOG" --status "testlog"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"not initialized"* ]]
}

@test "tlog: --status with file arg shows delta" {
	"$TLOG" "$LOGFILE" "testlog" >/dev/null 2>&1
	printf 'line four\n' >> "$LOGFILE"
	run "$TLOG" --status "testlog" "$LOGFILE"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"delta:"* ]]
	[[ "$output" == *"pending"* ]]
}

@test "tlog: --status missing name exits 1" {
	run "$TLOG" --status
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"requires"* ]]
}

@test "tlog: FP --status does not modify cursor" {
	"$TLOG" "$LOGFILE" "testlog" >/dev/null 2>&1
	local before after
	read -r before < "$BASERUN/testlog"
	"$TLOG" --status "testlog" >/dev/null 2>&1
	read -r after < "$BASERUN/testlog"
	[[ "$before" == "$after" ]]
}

# ===================================================================
# --reset Subcommand (5 tests)
# ===================================================================

@test "tlog: --reset deletes cursor file" {
	"$TLOG" "$LOGFILE" "testlog" >/dev/null 2>&1
	[[ -f "$BASERUN/testlog" ]]
	run "$TLOG" --reset "testlog"
	[[ "$status" -eq 0 ]]
	[[ ! -f "$BASERUN/testlog" ]]
	[[ "$output" == *"removed:"* ]]
}

@test "tlog: --reset deletes .jts and .lock when present" {
	"$TLOG" "$LOGFILE" "testlog" >/dev/null 2>&1
	touch "$BASERUN/testlog.jts"
	touch "$BASERUN/testlog.lock"
	run "$TLOG" --reset "testlog"
	[[ "$status" -eq 0 ]]
	[[ ! -f "$BASERUN/testlog" ]]
	[[ ! -f "$BASERUN/testlog.jts" ]]
	[[ ! -f "$BASERUN/testlog.lock" ]]
}

@test "tlog: --reset cleans orphaned temp files" {
	"$TLOG" "$LOGFILE" "testlog" >/dev/null 2>&1
	# Simulate orphaned mktemp files
	touch "$BASERUN/.testlog.aB3xYz"
	touch "$BASERUN/.testlog.Qw9rTp"
	run "$TLOG" --reset "testlog"
	[[ "$status" -eq 0 ]]
	[[ ! -f "$BASERUN/.testlog.aB3xYz" ]]
	[[ ! -f "$BASERUN/.testlog.Qw9rTp" ]]
}

@test "tlog: --reset with no cursor reports nothing found" {
	run "$TLOG" --reset "nonexistent"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"no cursor files found"* ]]
}

@test "tlog: FP --reset does not create files" {
	run "$TLOG" --reset "nonexistent"
	[[ "$status" -eq 0 ]]
	local count
	count=$(find "$BASERUN" -type f | wc -l)
	[[ "$count" -eq 0 ]]
}

# ===================================================================
# --adjust Subcommand (4 tests)
# ===================================================================

@test "tlog: --adjust subtracts from bytes cursor" {
	"$TLOG" "$LOGFILE" "testlog" >/dev/null 2>&1
	local before
	read -r before < "$BASERUN/testlog"
	run "$TLOG" --adjust "testlog" 10
	[[ "$status" -eq 0 ]]
	local after
	read -r after < "$BASERUN/testlog"
	[[ "$after" -eq $((before - 10)) ]]
}

@test "tlog: --adjust subtracts from lines cursor and preserves L: prefix" {
	"$TLOG" "$LOGFILE" "testlog" "lines" >/dev/null 2>&1
	local before_raw
	read -r before_raw < "$BASERUN/testlog"
	local before_val="${before_raw#L:}"
	run "$TLOG" --adjust "testlog" 1
	[[ "$status" -eq 0 ]]
	local after_raw
	read -r after_raw < "$BASERUN/testlog"
	[[ "$after_raw" == L:* ]]
	local after_val="${after_raw#L:}"
	[[ "$after_val" -eq $((before_val - 1)) ]]
}

@test "tlog: --adjust with -b uses alternate baserun" {
	local alt_baserun="$TEST_TMPDIR/alt_tracking"
	mkdir -p "$alt_baserun"
	BASERUN="$alt_baserun" "$TLOG" "$LOGFILE" "testlog" >/dev/null 2>&1
	run "$TLOG" --adjust -b "$alt_baserun" "testlog" 5
	[[ "$status" -eq 0 ]]
}

@test "tlog: --adjust missing args exits 1" {
	run "$TLOG" --adjust "testlog"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"requires"* ]]
}

# ===================================================================
# Error Handling (5 tests)
# ===================================================================

@test "tlog: unknown option shows error and exits 1" {
	run "$TLOG" --unknown-opt "$LOGFILE" "testlog"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown option"* ]]
}

@test "tlog: -m without value exits 1" {
	run "$TLOG" -m
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"requires"* ]]
}

@test "tlog: -b without value exits 1" {
	run "$TLOG" -b
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"requires"* ]]
}

@test "tlog: --first-run without value exits 1" {
	run "$TLOG" --first-run
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"requires"* ]]
}

@test "tlog: BASERUN missing for --status exits 1" {
	run env BASERUN="/nonexistent/path" "$TLOG" --status "testlog"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"baserun directory not found"* ]]
}

# ===================================================================
# False-Positive Tests (3 tests)
# ===================================================================

@test "tlog: FP --full ignores -f (no .lock created)" {
	run "$TLOG" -f --full "$LOGFILE"
	[[ "$status" -eq 0 ]]
	# --full does not use cursors or flock
	local count
	count=$(find "$BASERUN" -type f -name "*.lock" | wc -l)
	[[ "$count" -eq 0 ]]
}

@test "tlog: FP -h output goes to stdout not stderr" {
	local stdout_file="$TEST_TMPDIR/stdout"
	local stderr_file="$TEST_TMPDIR/stderr"
	"$TLOG" -h > "$stdout_file" 2> "$stderr_file"
	# stdout should have content
	[[ -s "$stdout_file" ]]
	# stderr should be empty
	[[ ! -s "$stderr_file" ]]
}

@test "tlog: FP --reset nonexistent cursor does not create cursor" {
	run "$TLOG" --reset "ghost"
	[[ "$status" -eq 0 ]]
	[[ ! -f "$BASERUN/ghost" ]]
}
