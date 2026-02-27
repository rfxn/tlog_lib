.PHONY: test test-serial test-verbose test-debian12 \
       test-centos6 test-rocky9 test-all test-all-parallel

PARALLEL_JOBS := $(shell echo $$(( $$(nproc) * 2 )) | awk '{ print ($$1 < 1) ? 1 : $$1 }')

# Default: Debian 12, parallel
test:
	./run-tests.sh --parallel

# Sequential: single container, all files
test-serial:
	./run-tests.sh

# Verbose: parallel with pretty formatter
test-verbose:
	./run-tests.sh --formatter pretty

# Explicit Debian 12 target (same as default but named)
test-debian12:
	./run-tests.sh --os debian12 --parallel

# Individual OS targets (parallel within OS)
test-centos6:
	./run-tests.sh --os centos6 --parallel

test-rocky9:
	./run-tests.sh --os rocky9 --parallel

# Full matrix (all targets) — sequential across OS
test-all:
	./run-tests.sh --os debian12 --parallel
	./run-tests.sh --os rocky9 --parallel
	./run-tests.sh --os centos6 --parallel

# Parallel cross-OS
test-all-parallel:
	printf '%s\n' debian12 rocky9 centos6 | \
	  xargs -P $(PARALLEL_JOBS) -I{} ./run-tests.sh --os {} --parallel
