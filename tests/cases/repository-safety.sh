#!/usr/bin/env bash

test_source_is_fixed_and_target_git_is_ignored() {
  # Given: a marked target with hostile Git metadata and public source overrides.
  write_bootstrap_double
  mark_existing_target
  mkdir -p "$TARGET_DIR/.git"
  printf 'hostile\n' >"$TARGET_DIR/.git/config"
  printf 'hostile-index\n' >"$TARGET_DIR/.git/index"
  export REPOSITORY_URL="https://attacker.invalid/repository.git"
  export COMMIT_SHA="ffffffffffffffffffffffffffffffffffffffff"

  # When: installation refreshes the application source.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: Git uses only fixed coordinates and never addresses the old target.
  assert_success &&
    assert_file_contains "$COMMAND_LOG" "$EXPECTED_REPOSITORY" &&
    assert_file_contains "$COMMAND_LOG" "$EXPECTED_COMMIT" &&
    assert_file_excludes "$COMMAND_LOG" "$TARGET_DIR" &&
    assert_file_excludes "$COMMAND_LOG" "$REPOSITORY_URL" &&
    [[ ! -e "$TARGET_DIR/.git/config" ]]
}

test_dirty_old_worktree_is_replaced_without_git_inspection() {
  # Given: a marked target with a dirty-looking old worktree and Git index.
  write_bootstrap_double
  mark_existing_target
  mkdir -p "$TARGET_DIR/.git" "$TARGET_DIR/packages/api/src"
  printf 'hostile-index\n' >"$TARGET_DIR/.git/index"
  printf 'local changes\n' >"$TARGET_DIR/packages/api/src/app.ts"

  # When: installation refreshes from independent trusted staging.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: no Git command addresses old target and its old worktree is replaced.
  assert_success && assert_file_excludes "$COMMAND_LOG" "$TARGET_DIR" &&
    [[ ! -e "$TARGET_DIR/packages/api/src/app.ts" && ! -e "$TARGET_DIR/.git" ]]
}

test_unrelated_non_empty_target_is_refused() {
  # Given: a target containing unrelated data and no installer marker.
  write_bootstrap_double
  printf 'must survive\n' >"$TARGET_DIR/unrelated.txt"

  # When: installation targets that directory.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: it refuses the target without invoking Git or bootstrap.
  assert_failure && assert_file_empty "$COMMAND_LOG" &&
    assert_file_contains "$TARGET_DIR/unrelated.txt" "must survive"
}

test_symlink_target_is_refused() {
  # Given: the configured target path is a symlink to another directory.
  write_bootstrap_double
  rmdir "$TARGET_DIR"
  mkdir "$TEST_ROOT/elsewhere"
  ln -s "$TEST_ROOT/elsewhere" "$TARGET_DIR"

  # When: installation validates filesystem state.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: it fails without following the symlink or invoking Git.
  assert_failure && assert_file_empty "$COMMAND_LOG"
}

test_persistent_artifacts_survive_source_replacement() {
  # Given: a marked install with runtime artifacts and untrusted old source.
  write_bootstrap_double
  mark_existing_target
  mkdir -p "$TARGET_DIR/secrets"
  printf 'runtime-env\n' >"$TARGET_DIR/.env"
  printf 'secret\n' >"$TARGET_DIR/secrets/key"
  printf 'garage\n' >"$TARGET_DIR/garage.toml"
  printf 'old source\n' >"$TARGET_DIR/untrusted.txt"
  target_inode="$(stat -c %i "$TARGET_DIR")"

  # When: trusted staged source replaces the old tree.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: artifacts and marker remain while old source is gone.
  assert_success &&
    assert_file_contains "$TARGET_DIR/.env" "runtime-env" &&
    assert_file_contains "$TARGET_DIR/secrets/key" "secret" &&
    assert_file_contains "$TARGET_DIR/garage.toml" "garage" &&
    assert_file_contains "$TARGET_DIR/.community-club-installer" "$INSTALLER_MARKER" &&
    [[ "$(stat -c %i "$TARGET_DIR")" == "$target_inode" ]] &&
    [[ ! -e "$TARGET_DIR/untrusted.txt" ]]
}

test_symlink_artifact_is_refused() {
  # Given: a marked install whose .env points outside the target.
  write_bootstrap_double
  mark_existing_target
  printf 'outside\n' >"$TEST_ROOT/outside-env"
  ln -s "$TEST_ROOT/outside-env" "$TARGET_DIR/.env"

  # When: installation validates preserved artifacts.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: it fails before Git and leaves the external file unchanged.
  assert_failure && assert_file_empty "$COMMAND_LOG" &&
    assert_file_contains "$TEST_ROOT/outside-env" "outside"
}

test_symlink_secrets_directory_is_refused() {
  # Given: a marked install whose secrets directory points outside the target.
  write_bootstrap_double
  mark_existing_target
  mkdir "$TEST_ROOT/outside-secrets"
  ln -s "$TEST_ROOT/outside-secrets" "$TARGET_DIR/secrets"

  # When: installation validates preserved artifacts.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: it fails before Git without following the secrets symlink.
  assert_failure && assert_file_empty "$COMMAND_LOG"
}

test_symlink_garage_config_is_refused() {
  # Given: a marked install whose Garage config points outside the target.
  write_bootstrap_double
  mark_existing_target
  printf 'outside\n' >"$TEST_ROOT/outside-garage.toml"
  ln -s "$TEST_ROOT/outside-garage.toml" "$TARGET_DIR/garage.toml"

  # When: installation validates preserved artifacts.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: it fails before Git and leaves the external config unchanged.
  assert_failure && assert_file_empty "$COMMAND_LOG" &&
    assert_file_contains "$TEST_ROOT/outside-garage.toml" "outside"
}

test_nested_symlink_in_secrets_is_refused() {
  # Given: a marked install with a symlink nested inside secrets.
  write_bootstrap_double
  mark_existing_target
  mkdir "$TARGET_DIR/secrets"
  printf 'outside\n' >"$TEST_ROOT/outside-secret"
  ln -s "$TEST_ROOT/outside-secret" "$TARGET_DIR/secrets/key"

  # When: installation recursively validates the secrets artifact.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: it fails before Git and leaves the external secret unchanged.
  assert_failure && assert_file_empty "$COMMAND_LOG" &&
    assert_file_contains "$TEST_ROOT/outside-secret" "outside"
}

test_verified_head_mismatch_is_rejected() {
  # Given: a fresh staging checkout reports a different HEAD.
  write_bootstrap_double
  set_fake_head "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  # When: installation verifies staged HEAD.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: it fails before replacing the target or invoking bootstrap.
  assert_failure && assert_file_contains "$COMMAND_LOG" "rev-parse" &&
    [[ ! -e "$BOOTSTRAP_LOG" ]]
}

TESTS+=(
  "fixed source ignores target Git|test_source_is_fixed_and_target_git_is_ignored"
  "dirty old worktree is replaced without Git inspection|test_dirty_old_worktree_is_replaced_without_git_inspection"
  "unrelated non-empty target is refused|test_unrelated_non_empty_target_is_refused"
  "symlink target is refused|test_symlink_target_is_refused"
  "runtime artifacts survive replacement|test_persistent_artifacts_survive_source_replacement"
  "symlink artifact is refused|test_symlink_artifact_is_refused"
  "symlink secrets directory is refused|test_symlink_secrets_directory_is_refused"
  "symlink Garage config is refused|test_symlink_garage_config_is_refused"
  "nested secrets symlink is refused|test_nested_symlink_in_secrets_is_refused"
  "verified staged HEAD mismatch is rejected|test_verified_head_mismatch_is_rejected"
)
