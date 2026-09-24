#!/usr/bin/env bash

test_apt_get_uses_default_lock_timeout() {
  # Given: a clean host that needs one prerequisite package.
  write_bootstrap_double
  export CLUB_INSTALLER_TEST_FORCE_MISSING_CURL=1

  # When: the installer obtains prerequisites with its default configuration.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: both apt-get operations receive the bounded native lock timeout.
  assert_success &&
    assert_file_contains "$COMMAND_LOG" 'apt-get|-o DPkg::Lock::Timeout=300 update ' &&
    assert_file_contains "$COMMAND_LOG" 'apt-get|-o DPkg::Lock::Timeout=300 install -y --no-install-recommends curl '
}

test_apt_get_lock_timeout_accepts_override() {
  # Given: a clean host and an explicit bounded timeout.
  write_bootstrap_double
  export CLUB_INSTALLER_TEST_FORCE_MISSING_CURL=1
  export CLUB_APT_LOCK_TIMEOUT='45'

  # When: the installer obtains prerequisites.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: every apt-get operation receives the configured timeout.
  assert_success &&
    assert_file_contains "$COMMAND_LOG" 'apt-get|-o DPkg::Lock::Timeout=45 update ' &&
    assert_file_contains "$COMMAND_LOG" 'apt-get|-o DPkg::Lock::Timeout=45 install -y --no-install-recommends curl ' &&
    assert_file_excludes "$BOOTSTRAP_LOG" 'CLUB_APT_LOCK_TIMEOUT='
}

test_invalid_apt_get_lock_timeout_is_rejected() {
  # Given: otherwise valid inputs with a non-numeric apt lock timeout.
  write_bootstrap_double
  export CLUB_INSTALLER_TEST_FORCE_MISSING_CURL=1
  export CLUB_APT_LOCK_TIMEOUT='forever'

  # When: the installer validates caller-controlled configuration.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: it fails before any host command executes.
  assert_failure && assert_file_empty "$COMMAND_LOG"
}

TESTS+=(
  "apt-get uses default lock timeout|test_apt_get_uses_default_lock_timeout"
  "apt-get lock timeout accepts override|test_apt_get_lock_timeout_accepts_override"
  "invalid apt-get lock timeout is rejected|test_invalid_apt_get_lock_timeout_is_rejected"
)
