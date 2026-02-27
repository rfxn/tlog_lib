#!/usr/bin/env bats
# 01-tlog.bats — Core library tests for tlog_lib.sh
# Tests: version, utility functions, both tracking modes, rotation,
# cursor validation, flock, atomic writes, stale protection.

load helpers/tlog-common

setup() {
	tlog_common_setup
	# Create a standard test log file
	LOGFILE="$TEST_TMPDIR/test.log"
	printf 'line one\nline two\nline three\n' > "$LOGFILE"
}

teardown() {
	tlog_teardown
}

# ===================================================================
# Version & Source Guard (2 tests)
# ===================================================================

@test "TLOG_LIB_VERSION is set and matches 2.0.1" {
	[[ "$TLOG_LIB_VERSION" == "2.0.1" ]]
}

@test "source guard prevents double-sourcing side effects" {
	# Sourcing again should be harmless (source guard returns 0)
	source "${PROJECT_ROOT}/files/tlog_lib.sh"
	[[ "$TLOG_LIB_VERSION" == "2.0.1" ]]
}

# ===================================================================
# Utility Functions (4 tests)
# ===================================================================

@test "tlog_get_file_size: returns byte size" {
	local size
	size=$(tlog_get_file_size "$LOGFILE")
	local expected
	expected=$(stat -c %s "$LOGFILE")
	[[ "$size" == "$expected" ]]
}

@test "tlog_get_file_size: missing file returns exit 1" {
	run tlog_get_file_size "$TEST_TMPDIR/nonexistent"
	[[ "$status" -eq 1 ]]
}

@test "tlog_get_line_count: returns line count" {
	local count
	count=$(tlog_get_line_count "$LOGFILE")
	[[ "$count" == "3" ]]
}

@test "tlog_get_line_count: missing file returns exit 1" {
	run tlog_get_line_count "$TEST_TMPDIR/nonexistent"
	[[ "$status" -eq 1 ]]
}

# ===================================================================
# First Run — Bytes Mode (3 tests)
# ===================================================================

@test "tlog_read bytes: first run initializes cursor and outputs nothing" {
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	# FP: skip outputs nothing
	[[ -z "$output" ]]
	# Cursor file exists with correct value
	[[ -f "$BASERUN/testlog" ]]
	local cursor
	read -r cursor < "$BASERUN/testlog"
	local expected
	expected=$(stat -c %s "$LOGFILE")
	[[ "$cursor" == "$expected" ]]
}

@test "tlog_read bytes: first run TLOG_FIRST_RUN=full outputs entire file" {
	TLOG_FIRST_RUN="full"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$(cat "$LOGFILE")" ]]
}

@test "tlog_read bytes: first run does not create .lock when TLOG_FLOCK=0" {
	TLOG_FLOCK="0"
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	# FP: no lock file
	[[ ! -f "$BASERUN/testlog.lock" ]]
}

# ===================================================================
# First Run — Lines Mode (2 tests)
# ===================================================================

@test "tlog_read lines: first run initializes L: prefixed cursor" {
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "lines"
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
	local cursor
	read -r cursor < "$BASERUN/testlog"
	[[ "$cursor" == "L:3" ]]
}

@test "tlog_read lines: first run TLOG_FIRST_RUN=full outputs entire file" {
	TLOG_FIRST_RUN="full"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "lines"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$(cat "$LOGFILE")" ]]
}

# ===================================================================
# Growth — Bytes Mode (3 tests)
# ===================================================================

@test "tlog_read bytes: growth outputs only new content" {
	# First run
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	# Append new content
	printf 'line four\n' >> "$LOGFILE"
	# Second run
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "line four" ]]
}

@test "tlog_read bytes: multiple appended lines all output" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	printf 'line four\nline five\nline six\n' >> "$LOGFILE"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	local expected
	expected=$(printf 'line four\nline five\nline six')
	[[ "$output" == "$expected" ]]
}

@test "tlog_read bytes: no-change produces no output and cursor unchanged" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	local cursor_before
	read -r cursor_before < "$BASERUN/testlog"
	# Second run with no changes
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	# FP: no output
	[[ -z "$output" ]]
	local cursor_after
	read -r cursor_after < "$BASERUN/testlog"
	[[ "$cursor_before" == "$cursor_after" ]]
}

# ===================================================================
# Growth — Lines Mode (2 tests)
# ===================================================================

@test "tlog_read lines: growth outputs only new lines" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "lines" >/dev/null 2>&1
	printf 'line four\nline five\n' >> "$LOGFILE"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "lines"
	[[ "$status" -eq 0 ]]
	local expected
	expected=$(printf 'line four\nline five')
	[[ "$output" == "$expected" ]]
}

@test "tlog_read lines: no-change produces no output" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "lines" >/dev/null 2>&1
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "lines"
	[[ "$status" -eq 0 ]]
	# FP: no output
	[[ -z "$output" ]]
}

# ===================================================================
# Mode Isolation (4 tests, all FP)
# ===================================================================

@test "bytes-mode cursor does not contain L: prefix" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	local cursor
	read -r cursor < "$BASERUN/testlog"
	# FP: no L: prefix
	[[ "$cursor" != L:* ]]
}

@test "lines-mode cursor contains L: prefix" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "lines" >/dev/null 2>&1
	local cursor
	read -r cursor < "$BASERUN/testlog"
	# Must have L: prefix
	[[ "$cursor" == L:* ]]
}

@test "mode mismatch resets cursor without output" {
	# Init in bytes mode
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	# Switch to lines mode — run captures both stdout and stderr
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "lines"
	# FP: no file content in output (stderr warning about mismatch is expected)
	# Strip the tlog: warning line and verify no file content remains
	local content_lines
	content_lines=$(printf '%s\n' "$output" | grep -v '^tlog:' | grep -v '^$' || true)
	[[ -z "$content_lines" ]]
	# Cursor now has L: prefix
	local cursor
	read -r cursor < "$BASERUN/testlog"
	[[ "$cursor" == L:* ]]
}

@test "mode mismatch: byte value not used as line count" {
	# Create a file where byte size >> line count
	local bigfile="$TEST_TMPDIR/bigfile.log"
	local i
	for i in $(seq 1 10); do
		printf 'This is a line with enough padding to make byte size large: %050d\n' "$i" >> "$bigfile"
	done
	# Init in bytes mode (cursor ≈ 710 bytes)
	tlog_read "$bigfile" "bigtest" "$BASERUN" "bytes" >/dev/null 2>&1
	local byte_cursor
	read -r byte_cursor < "$BASERUN/bigtest"
	# byte_cursor >> 10 (line count)
	[[ "$byte_cursor" -gt 100 ]]
	# Switch to lines mode — must reset (returns exit 2 for cursor corrupt)
	run tlog_read "$bigfile" "bigtest" "$BASERUN" "lines"
	[[ "$status" -eq 2 ]]
	local line_cursor
	read -r line_cursor < "$BASERUN/bigtest"
	# FP: must be L:10, NOT L:710
	[[ "$line_cursor" == "L:10" ]]
}

# ===================================================================
# Rotation — Bytes Mode (5 tests)
# ===================================================================

@test "tlog_read bytes: rotation with .1 file outputs rotated tail plus new file" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	# Simulate rotation: append more, copy to .1, start new file
	printf 'line four\n' >> "$LOGFILE"
	cp "$LOGFILE" "${LOGFILE}.1"
	printf 'new file line one\n' > "$LOGFILE"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	# Output should contain the rotated tail (line four) + new file content
	[[ "$output" == *"line four"* ]]
	[[ "$output" == *"new file line one"* ]]
}

@test "tlog_read bytes: rotation with .1.gz outputs via zcat" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	# Simulate rotation: append, compress to .1.gz, start new file
	printf 'line four\n' >> "$LOGFILE"
	cp "$LOGFILE" "${LOGFILE}.1.tmp"
	gzip -c "${LOGFILE}.1.tmp" > "${LOGFILE}.1.gz"
	rm -f "${LOGFILE}.1.tmp"
	printf 'new file line one\n' > "$LOGFILE"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"line four"* ]]
	[[ "$output" == *"new file line one"* ]]
}

@test "tlog_read bytes: .1.gz file still exists after read" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	printf 'line four\n' >> "$LOGFILE"
	cp "$LOGFILE" "${LOGFILE}.1.tmp"
	gzip -c "${LOGFILE}.1.tmp" > "${LOGFILE}.1.gz"
	rm -f "${LOGFILE}.1.tmp"
	printf 'new file line one\n' > "$LOGFILE"
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	# FP: .1.gz must still exist (no decompression on disk)
	[[ -f "${LOGFILE}.1.gz" ]]
}

@test "tlog_read bytes: rotated file smaller than cursor — no rotated content" {
	# Create a large initial file
	local i
	for i in $(seq 1 50); do
		printf 'padding line number %d with extra content\n' "$i" >> "$LOGFILE"
	done
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	# Simulate rotation: .1 file is SMALLER than cursor
	printf 'tiny\n' > "${LOGFILE}.1"
	printf 'new content\n' > "$LOGFILE"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	# FP: no rotated content — .1 is too small
	[[ "$output" != *"tiny"* ]]
	# But new file content is present
	[[ "$output" == *"new content"* ]]
}

@test "tlog_read bytes: no rotated file — no error, outputs current file" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	# Simulate rotation: no .1 file at all
	printf 'new content after rotation\n' > "$LOGFILE"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	# FP: no error
	[[ "$output" == *"new content after rotation"* ]]
}

# ===================================================================
# Rotation — Lines Mode + Growth FP (2 tests)
# ===================================================================

@test "tlog_read lines: rotation outputs new file content" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "lines" >/dev/null 2>&1
	# Simulate rotation
	printf 'line four\n' >> "$LOGFILE"
	cp "$LOGFILE" "${LOGFILE}.1"
	printf 'new line one\nnew line two\n' > "$LOGFILE"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "lines"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"new line one"* ]]
}

@test "tlog_read bytes: growth does not read from rotated files" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	# Growth path: append to current file
	printf 'appended content\n' >> "$LOGFILE"
	# Place a .1 file with distinctive content
	printf 'ROTATED CONTENT SHOULD NOT APPEAR\n' > "${LOGFILE}.1"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	# FP: rotated content must NOT appear in output
	[[ "$output" != *"ROTATED CONTENT SHOULD NOT APPEAR"* ]]
	[[ "$output" == *"appended content"* ]]
}

# ===================================================================
# Cursor Validation (4 tests)
# ===================================================================

@test "corrupt cursor: non-numeric resets with exit 2" {
	printf 'garbage!!!\n' > "$BASERUN/testlog"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 2 ]]
	# Cursor has been reset to valid value
	local cursor
	read -r cursor < "$BASERUN/testlog"
	local numeric_pat='^[0-9]+$'
	[[ "$cursor" =~ $numeric_pat ]]
}

@test "corrupt cursor: empty file triggers first-run" {
	touch "$BASERUN/testlog"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	# Treated as first-run: no output (skip mode)
	[[ -z "$output" ]]
	# Cursor now has valid value
	local cursor
	read -r cursor < "$BASERUN/testlog"
	local numeric_pat='^[0-9]+$'
	[[ "$cursor" =~ $numeric_pat ]]
}

@test "corrupt cursor: L: prefix with non-numeric resets" {
	printf 'L:not-a-number\n' > "$BASERUN/testlog"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "lines"
	[[ "$status" -eq 2 ]]
	# Cursor reset to valid L: value
	local cursor
	read -r cursor < "$BASERUN/testlog"
	[[ "$cursor" == L:* ]]
}

@test "corrupt cursor: does not cause arithmetic errors" {
	printf '!!!not-a-number!!!\n' > "$BASERUN/testlog"
	# FP: must not produce "syntax error" or "integer expression expected"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$output" != *"syntax error"* ]]
	[[ "$output" != *"integer expression expected"* ]]
	# stderr captured in output by run — check combined
	local combined
	combined="${output}${stderr:-}"
	[[ "$combined" != *"syntax error"* ]]
	[[ "$combined" != *"integer expression expected"* ]]
}

# ===================================================================
# Error Handling (3 tests)
# ===================================================================

@test "tlog_read: missing file with LOG_SOURCE=file returns exit 1" {
	LOG_SOURCE="file"
	run tlog_read "$TEST_TMPDIR/nonexistent" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 1 ]]
}

@test "tlog_read: missing baserun directory returns exit 1" {
	run tlog_read "$LOGFILE" "testlog" "$TEST_TMPDIR/nonexistent_dir" "bytes"
	[[ "$status" -eq 1 ]]
}

@test "tlog_read: invalid mode returns exit 1" {
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "line"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"invalid mode"* ]]
	# Must not create a cursor file
	[[ ! -f "$BASERUN/testlog" ]]
}

@test "tlog_read_full: missing file returns exit 1" {
	run tlog_read_full "$TEST_TMPDIR/nonexistent"
	[[ "$status" -eq 1 ]]
}

# ===================================================================
# tlog_read_full (2 tests)
# ===================================================================

@test "tlog_read_full: outputs entire file without cursor" {
	run tlog_read_full "$LOGFILE"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$(cat "$LOGFILE")" ]]
}

@test "tlog_read_full: max_lines limits output" {
	run tlog_read_full "$LOGFILE" 2
	[[ "$status" -eq 0 ]]
	local expected
	expected=$(printf 'line two\nline three')
	[[ "$output" == "$expected" ]]
}

# ===================================================================
# tlog_adjust_cursor (4 tests)
# ===================================================================

@test "tlog_adjust_cursor bytes: subtracts delta correctly" {
	_tlog_write_cursor "testlog" "$BASERUN" "1000" "bytes"
	tlog_adjust_cursor "testlog" "$BASERUN" "300"
	local cursor
	read -r cursor < "$BASERUN/testlog"
	[[ "$cursor" == "700" ]]
}

@test "tlog_adjust_cursor lines: subtracts delta and preserves L: prefix" {
	_tlog_write_cursor "testlog" "$BASERUN" "100" "lines"
	tlog_adjust_cursor "testlog" "$BASERUN" "25"
	local cursor
	read -r cursor < "$BASERUN/testlog"
	[[ "$cursor" == "L:75" ]]
}

@test "tlog_adjust_cursor: over-subtraction clamps to zero" {
	_tlog_write_cursor "testlog" "$BASERUN" "50" "bytes"
	tlog_adjust_cursor "testlog" "$BASERUN" "100"
	local cursor
	read -r cursor < "$BASERUN/testlog"
	[[ "$cursor" == "0" ]]
}

@test "tlog_adjust_cursor: no cursor file is no-op" {
	run tlog_adjust_cursor "testlog" "$BASERUN" "100"
	[[ "$status" -eq 0 ]]
	[[ ! -f "$BASERUN/testlog" ]]
}

# ===================================================================
# tlog_advance_cursors (1 test)
# ===================================================================

@test "tlog_advance_cursors: records current sizes for multiple files" {
	local log2="$TEST_TMPDIR/test2.log"
	printf 'log2 line one\nlog2 line two\n' > "$log2"
	local pairs
	pairs=$(printf '%s|log1\n%s|log2' "$LOGFILE" "$log2")
	tlog_advance_cursors "$BASERUN" "$pairs"
	# Both cursor files should exist with correct sizes
	local c1 c2
	read -r c1 < "$BASERUN/log1"
	read -r c2 < "$BASERUN/log2"
	local s1 s2
	s1=$(stat -c %s "$LOGFILE")
	s2=$(stat -c %s "$log2")
	[[ "$c1" == "$s1" ]]
	[[ "$c2" == "$s2" ]]
}

# ===================================================================
# Stale Protection (1 test)
# ===================================================================

@test "stale protection: cursor mtime updated even on no-change" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	local mtime_before
	mtime_before=$(stat -c %Y "$BASERUN/testlog")
	# Wait for filesystem mtime granularity
	sleep 1
	# Second run: no changes to file
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	local mtime_after
	mtime_after=$(stat -c %Y "$BASERUN/testlog")
	[[ "$mtime_after" -gt "$mtime_before" ]]
}

# ===================================================================
# Atomic Writes (1 test)
# ===================================================================

@test "atomic write: no orphaned temp files after cursor write" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	printf 'more content\n' >> "$LOGFILE"
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	# FP: no orphaned temp files
	local orphans
	orphans=$(ls "$BASERUN"/.testlog.* 2>/dev/null | wc -l)
	[[ "$orphans" -eq 0 ]]
}

# ===================================================================
# Flock (3 tests)
# ===================================================================

@test "TLOG_FLOCK=0: does not create .lock files" {
	TLOG_FLOCK="0"
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	# FP: no lock file
	[[ ! -f "$BASERUN/testlog.lock" ]]
}

@test "TLOG_FLOCK=1: lock held by another process returns exit 4" {
	TLOG_FLOCK="1"
	# First run to init cursor
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	# Hold lock in a separate background process
	flock -x "$BASERUN/testlog.lock" -c 'sleep 30' &
	FLOCK_PID=$!
	sleep 0.5
	# Attempt to read with lock held — should timeout and return exit 4
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 4 ]]
}

@test "TLOG_FLOCK=1: lock held does not modify cursor or output content" {
	TLOG_FLOCK="1"
	# First run to init cursor
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	local cursor_before
	read -r cursor_before < "$BASERUN/testlog"
	# Append content
	printf 'new content\n' >> "$LOGFILE"
	# Hold lock in background
	flock -x "$BASERUN/testlog.lock" -c 'sleep 30' &
	FLOCK_PID=$!
	sleep 0.5
	# Attempt read with lock held
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	# FP: no output
	[[ -z "$output" ]]
	# FP: cursor unchanged
	local cursor_after
	read -r cursor_after < "$BASERUN/testlog"
	[[ "$cursor_before" == "$cursor_after" ]]
}

# ===================================================================
# Copytruncate Rotation (3 tests)
# ===================================================================

@test "tlog_read bytes: copytruncate rotation outputs remainder from .1" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	# Simulate copytruncate: copy current file to .1, then truncate original
	printf 'line four\n' >> "$LOGFILE"
	cp "$LOGFILE" "${LOGFILE}.1"
	: > "$LOGFILE"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	# Output should contain the remainder from .1 (line four)
	[[ "$output" == *"line four"* ]]
}

@test "tlog_read lines: copytruncate rotation outputs remainder from .1" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "lines" >/dev/null 2>&1
	printf 'line four\nline five\n' >> "$LOGFILE"
	cp "$LOGFILE" "${LOGFILE}.1"
	: > "$LOGFILE"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "lines"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"line four"* ]]
	[[ "$output" == *"line five"* ]]
}

@test "tlog_read bytes: copytruncate with new writes after truncation" {
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	printf 'line four\n' >> "$LOGFILE"
	cp "$LOGFILE" "${LOGFILE}.1"
	: > "$LOGFILE"
	# New content written to truncated file
	printf 'fresh content\n' > "$LOGFILE"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	# Both remainder from .1 and new content should appear
	[[ "$output" == *"line four"* ]]
	[[ "$output" == *"fresh content"* ]]
}

# ===================================================================
# Multi-Format Compression Rotation (4 tests)
# ===================================================================

@test "tlog_read bytes: rotation with .1.xz" {
	command -v xz >/dev/null 2>&1 || skip "xz not available"
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	printf 'line four\n' >> "$LOGFILE"
	xz -c "$LOGFILE" > "${LOGFILE}.1.xz"
	printf 'new file line one\n' > "$LOGFILE"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"line four"* ]]
	[[ "$output" == *"new file line one"* ]]
}

@test "tlog_read bytes: rotation with .1.bz2" {
	command -v bzip2 >/dev/null 2>&1 || skip "bzip2 not available"
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	printf 'line four\n' >> "$LOGFILE"
	bzip2 -c "$LOGFILE" > "${LOGFILE}.1.bz2"
	printf 'new file line one\n' > "$LOGFILE"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"line four"* ]]
	[[ "$output" == *"new file line one"* ]]
}

@test "tlog_read bytes: rotation with .1.zst" {
	command -v zstd >/dev/null 2>&1 || skip "zstd not available"
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	printf 'line four\n' >> "$LOGFILE"
	zstd -c "$LOGFILE" > "${LOGFILE}.1.zst" 2>/dev/null
	printf 'new file line one\n' > "$LOGFILE"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"line four"* ]]
	[[ "$output" == *"new file line one"* ]]
}

@test "tlog_read bytes: compressed files still exist after read" {
	command -v xz >/dev/null 2>&1 || skip "xz not available"
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	printf 'line four\n' >> "$LOGFILE"
	xz -c "$LOGFILE" > "${LOGFILE}.1.xz"
	printf 'new file line one\n' > "$LOGFILE"
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	# FP: .1.xz must still exist (never decompressed on disk)
	[[ -f "${LOGFILE}.1.xz" ]]
}

# ===================================================================
# Compression False-Positive + Priority (3 tests)
# ===================================================================

@test "compressed rotated file skipped when tool unavailable" {
	# Create a .1.lz4 file — lz4 is not installed in test containers
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	printf 'line four\n' >> "$LOGFILE"
	# Write a fake .1.lz4 (content doesn't matter since lz4 is unavailable)
	printf 'fake lz4 content\n' > "${LOGFILE}.1.lz4"
	printf 'new file line one\n' > "$LOGFILE"
	if command -v lz4 >/dev/null 2>&1; then
		skip "lz4 is installed — cannot test tool-unavailable path"
	fi
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	# Graceful: no rotated content (tool missing), just current file
	[[ "$output" == *"new file line one"* ]]
	[[ "$output" != *"fake lz4 content"* ]]
}

@test "_tlog_find_rotated prefers .1 over .1.gz" {
	printf 'uncompressed rotated\n' > "${LOGFILE}.1"
	gzip -c "${LOGFILE}.1" > "${LOGFILE}.1.gz"
	run _tlog_find_rotated "$LOGFILE"
	[[ "$status" -eq 0 ]]
	# Must prefer uncompressed .1
	[[ "$output" == "${LOGFILE}.1" ]]
}

@test "tlog_read bytes: growth does not read from compressed rotated files" {
	command -v xz >/dev/null 2>&1 || skip "xz not available"
	tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes" >/dev/null 2>&1
	# Growth path: append to current file
	printf 'appended content\n' >> "$LOGFILE"
	# Place compressed rotated files with distinctive content
	printf 'XZ ROTATED SHOULD NOT APPEAR\n' | xz -c > "${LOGFILE}.1.xz"
	command -v bzip2 >/dev/null 2>&1 && \
		printf 'BZ2 ROTATED SHOULD NOT APPEAR\n' | bzip2 -c > "${LOGFILE}.1.bz2"
	run tlog_read "$LOGFILE" "testlog" "$BASERUN" "bytes"
	[[ "$status" -eq 0 ]]
	# FP: compressed rotated content must NOT appear in growth output
	[[ "$output" != *"XZ ROTATED SHOULD NOT APPEAR"* ]]
	[[ "$output" != *"BZ2 ROTATED SHOULD NOT APPEAR"* ]]
	[[ "$output" == *"appended content"* ]]
}
