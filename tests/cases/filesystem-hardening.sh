#!/usr/bin/env bash

test_non_root_owned_target_is_refused() {
  # Given: a non-empty marked target owned by a non-root account.
  write_bootstrap_double
  mark_existing_target
  chown -R 65534:65534 "$TARGET_DIR"

  # When: the root installer validates the existing target.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: it refuses the target before source download or bootstrap execution.
  assert_failure && assert_file_empty "$COMMAND_LOG" && [[ ! -e "$BOOTSTRAP_LOG" ]]
}

test_group_writable_target_is_refused() {
  # Given: a root-owned marked target writable by its group.
  write_bootstrap_double
  mark_existing_target
  chmod 0775 "$TARGET_DIR"

  # When: the installer validates target permissions.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: it refuses the unsafe target before source download.
  assert_failure && assert_file_empty "$COMMAND_LOG"
}

test_marker_must_be_root_owned_mode_0600() {
  # Given: a valid marker with group-readable mode.
  write_bootstrap_double
  mark_existing_target
  chmod 0640 "$TARGET_DIR/.community-club-installer"

  # When: the installer validates the marker as its trust signal.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: it refuses the marker before source download.
  assert_failure && assert_file_empty "$COMMAND_LOG"
}

test_bootstrap_group_write_is_refused() {
  # Given: staged source whose bootstrap is group/world writable.
  write_bootstrap_double
  touch "$TEST_ROOT/unsafe-bootstrap-mode"

  # When: the installer re-checks bootstrap immediately before execution.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: root never executes the unsafe bootstrap.
  assert_failure && [[ ! -e "$BOOTSTRAP_LOG" ]]
}

test_bootstrap_symlink_is_refused() {
  # Given: an authenticated archive whose bootstrap entry is a symlink.
  write_bootstrap_double
  touch "$TEST_ROOT/symlink-bootstrap"

  # When: the installer checks extracted bootstrap type immediately before replacement.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: root never follows or executes the symlink bootstrap.
  assert_failure && [[ ! -e "$BOOTSTRAP_LOG" ]]
}

test_fresh_install_receives_tracked_garage_default() {
  # Given: an empty root-owned target and the tracked Garage default.
  write_bootstrap_double

  # When: a fresh installation completes.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: Garage and generated marker exist before real bootstrap creates runtime state.
  assert_success &&
    assert_file_contains "$TARGET_DIR/garage.toml" "staged-garage" &&
    assert_file_contains "$TARGET_DIR/.community-club-installer" "$INSTALLER_MARKER" &&
    [[ ! -e "$TARGET_DIR/.env" && ! -e "$TARGET_DIR/secrets" ]]
}

test_copy_failure_preserves_marker_and_runtime_state() {
  # Given: a marked install with runtime state and an injected source-copy failure.
  write_bootstrap_double
  mark_existing_target
  mkdir "$TARGET_DIR/secrets"
  printf 'runtime-env\n' >"$TARGET_DIR/.env"
  printf 'runtime-secret\n' >"$TARGET_DIR/secrets/key"
  printf 'runtime-garage\n' >"$TARGET_DIR/garage.toml"
  touch "$TEST_ROOT/fail-source-copy"

  # When: source copy fails after cleanup begins.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: exact failure status, marker, and runtime state remain retryable.
  assert_status 73 &&
    assert_file_contains "$TARGET_DIR/.community-club-installer" "$INSTALLER_MARKER" &&
    [[ "$(stat -c '%u:%a' "$TARGET_DIR/.community-club-installer")" == '0:600' ]] &&
    assert_file_contains "$TARGET_DIR/.env" "runtime-env" &&
    assert_file_contains "$TARGET_DIR/secrets/key" "runtime-secret" &&
    assert_file_contains "$TARGET_DIR/garage.toml" "runtime-garage"
}

test_retry_after_copy_failure_succeeds() {
  # Given: a marked install left retryable by one injected copy failure.
  write_bootstrap_double
  mark_existing_target
  printf 'runtime-garage\n' >"$TARGET_DIR/garage.toml"
  touch "$TEST_ROOT/fail-source-copy"
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"
  [[ "$INSTALLER_STATUS" -eq 73 ]] || return 1
  rm "$TEST_ROOT/fail-source-copy"

  # When: the same installation is retried without the fault.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: bootstrap succeeds and preserved runtime state remains unchanged.
  assert_success && assert_file_contains "$BOOTSTRAP_LOG" "DOMAIN=$VALID_DOMAIN" &&
    assert_file_contains "$TARGET_DIR/garage.toml" "runtime-garage"
}

TESTS+=(
  "non-root-owned target is refused|test_non_root_owned_target_is_refused"
  "group-writable target is refused|test_group_writable_target_is_refused"
  "marker requires root ownership and mode 0600|test_marker_must_be_root_owned_mode_0600"
  "writable bootstrap is refused|test_bootstrap_group_write_is_refused"
  "symlink bootstrap is refused|test_bootstrap_symlink_is_refused"
  "fresh install receives tracked Garage default|test_fresh_install_receives_tracked_garage_default"
  "copy failure preserves retry state|test_copy_failure_preserves_marker_and_runtime_state"
  "retry after copy failure succeeds|test_retry_after_copy_failure_succeeds"
)
