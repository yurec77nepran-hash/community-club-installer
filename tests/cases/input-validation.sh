#!/usr/bin/env bash

test_missing_domain_is_rejected() {
  # Given: a supported host and only ADMIN_EMAIL.
  write_bootstrap_double

  # When: the installer starts without DOMAIN.
  invoke_installer "__UNSET__" "$VALID_ADMIN_EMAIL"

  # Then: validation fails before any host command runs.
  assert_failure && assert_file_empty "$COMMAND_LOG"
}

test_invalid_domain_is_rejected() {
  # Given: a DOMAIN containing a URL instead of a DNS hostname.
  write_bootstrap_double

  # When: the installer validates its canonical inputs.
  invoke_installer "https://club.example.com/path" "$VALID_ADMIN_EMAIL"

  # Then: validation fails before any host command runs.
  assert_failure && assert_file_empty "$COMMAND_LOG"
}

test_missing_admin_email_is_rejected() {
  # Given: a supported host, DOMAIN, and the unsupported INSTALL_EMAIL alias.
  write_bootstrap_double
  export INSTALL_EMAIL="$VALID_ADMIN_EMAIL"

  # When: the installer starts without ADMIN_EMAIL.
  invoke_installer "$VALID_DOMAIN" "__UNSET__"

  # Then: validation fails before any host command runs.
  assert_failure && assert_file_empty "$COMMAND_LOG"
}

test_invalid_admin_email_is_rejected() {
  # Given: an ADMIN_EMAIL without a valid mailbox domain.
  write_bootstrap_double

  # When: the installer validates its canonical inputs.
  invoke_installer "$VALID_DOMAIN" "admin-at-example"

  # Then: validation fails before any host command runs.
  assert_failure && assert_file_empty "$COMMAND_LOG"
}

TESTS+=(
  "missing DOMAIN is rejected|test_missing_domain_is_rejected"
  "invalid DOMAIN is rejected|test_invalid_domain_is_rejected"
  "missing ADMIN_EMAIL is rejected|test_missing_admin_email_is_rejected"
  "invalid ADMIN_EMAIL is rejected|test_invalid_admin_email_is_rejected"
)
