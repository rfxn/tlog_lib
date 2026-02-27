#!/bin/bash
# tlog-common.bash — shared BATS helper for tlog_lib tests
# Sources tlog_lib.sh and provides setup/teardown functions.

PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
export PROJECT_ROOT

# Source library under test
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/files/tlog_lib.sh"

# Load bats-support and bats-assert if available
if [[ -d /usr/local/lib/bats/bats-support ]]; then
	# shellcheck disable=SC1091
	source /usr/local/lib/bats/bats-support/load.bash
	# shellcheck disable=SC1091
	source /usr/local/lib/bats/bats-assert/load.bash
fi

tlog_common_setup() {
	TEST_TMPDIR=$(mktemp -d)
	export BASERUN="$TEST_TMPDIR/tracking"
	mkdir -p "$BASERUN"
	export TLOG_FLOCK="0"
	export TLOG_FIRST_RUN="skip"
	export TLOG_MODE="bytes"
	export LOG_SOURCE="file"  # Prevent accidental journal dispatch
}

tlog_teardown() {
	# Kill any background flock holders from this test
	if [[ -n "${FLOCK_PID:-}" ]] && kill -0 "$FLOCK_PID" 2>/dev/null; then
		kill "$FLOCK_PID" 2>/dev/null
		wait "$FLOCK_PID" 2>/dev/null || true
	fi
	rm -rf "$TEST_TMPDIR"
}
