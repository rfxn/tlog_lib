ARG BASE_IMAGE=tlog-base-debian12
FROM ${BASE_IMAGE}

# tlog_lib needs no additional packages — batsman base provides
# coreutils, util-linux (flock), gzip (zcat), and all POSIX primitives.

COPY files/ /opt/tlog_lib/files/
COPY tests/ /opt/tlog_lib/tests/

WORKDIR /opt/tlog_lib/tests
CMD ["bats", "--formatter", "tap", "/opt/tlog_lib/tests/"]
