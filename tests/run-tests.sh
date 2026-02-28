#!/bin/bash
#
# tlog_lib Test Runner — batsman integration wrapper
# Usage: ./tests/run-tests.sh [--os OS] [--parallel [N]] [bats args...]
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Variables consumed by sourced run-tests-core.sh
# shellcheck disable=SC2034
BATSMAN_PROJECT="tlog"
# shellcheck disable=SC2034
BATSMAN_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC2034
BATSMAN_TESTS_DIR="$SCRIPT_DIR"
BATSMAN_INFRA_DIR="$SCRIPT_DIR/infra"
# shellcheck disable=SC2034
BATSMAN_DOCKER_FLAGS=""
# shellcheck disable=SC2034
BATSMAN_DEFAULT_OS="debian12"
# shellcheck disable=SC2034
BATSMAN_CONTAINER_TEST_PATH="/opt/tests"
# shellcheck disable=SC2034
BATSMAN_SUPPORTED_OS="debian12 centos6 centos7 rocky8 rocky9 rocky10 ubuntu1204 ubuntu2004 ubuntu2404"

# shellcheck source=/dev/null
source "$BATSMAN_INFRA_DIR/lib/run-tests-core.sh"
batsman_run "$@"
