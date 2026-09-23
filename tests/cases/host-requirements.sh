#!/usr/bin/env bash

test_unsupported_os_is_rejected() {
  # Given: valid inputs on an unsupported Alpine host.
  write_bootstrap_double
  cat >"$OS_RELEASE" <<'EOF'
ID=alpine
VERSION_ID=3.22
EOF

  # When: the installer checks the host OS through its private test seam.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: it fails before repository or bootstrap work.
  assert_failure && assert_file_empty "$COMMAND_LOG"
}

test_non_root_is_rejected() {
  # Given: a supported host running the installer as a non-root user.
  write_bootstrap_double
  CLUB_TEST_EUID=1000
  export CLUB_TEST_EUID

  # When: the installer checks how privileged operations can run.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: it fails before touching the repository or bootstrap, even if sudo exists.
  assert_failure && assert_file_empty "$COMMAND_LOG"
}

TESTS+=(
  "unsupported OS is rejected|test_unsupported_os_is_rejected"
  "non-root execution is rejected|test_non_root_is_rejected"
)
