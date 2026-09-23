#!/usr/bin/env bash

test_bootstrap_receives_only_canonical_environment() {
  # Given: valid inputs plus dangerous caller-controlled environment variables.
  write_bootstrap_double
  export ADMIN_PASSWORD="caller-secret"
  export COMPOSE_FILE="attacker-compose.yaml"
  export DOCKER_HOST="tcp://attacker.invalid:2375"
  export BASH_ENV="$TEST_ROOT/bash-env"
  export ENV="$TEST_ROOT/sh-env"
  export CDPATH="$TEST_ROOT"
  export GIT_DIR="$TEST_ROOT/hostile-git"
  export GIT_WORK_TREE="$TEST_ROOT/hostile-worktree"

  # When: installation invokes bootstrap from trusted staged source.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: only canonical inputs and the fixed execution environment arrive.
  assert_success &&
    assert_file_contains "$BOOTSTRAP_LOG" "DOMAIN=$VALID_DOMAIN" &&
    assert_file_contains "$BOOTSTRAP_LOG" "ADMIN_EMAIL=$VALID_ADMIN_EMAIL" &&
    assert_file_contains "$BOOTSTRAP_LOG" "HOME=/root" &&
    assert_file_contains "$BOOTSTRAP_LOG" "LC_ALL=C" &&
    assert_file_contains "$BOOTSTRAP_LOG" "argc=0" &&
    assert_file_excludes "$BOOTSTRAP_LOG" "ADMIN_PASSWORD=" &&
    assert_file_excludes "$BOOTSTRAP_LOG" "COMPOSE_FILE=" &&
    assert_file_excludes "$BOOTSTRAP_LOG" "DOCKER_HOST=" &&
    assert_file_excludes "$BOOTSTRAP_LOG" "BASH_ENV=" &&
    assert_file_excludes "$BOOTSTRAP_LOG" "GIT_DIR="
}

test_bootstrap_runs_while_installer_lock_is_held() {
  # Given: a successful bootstrap that probes the installation lock.
  write_bootstrap_double

  # When: installation invokes bootstrap.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: another process cannot acquire the lock during bootstrap.
  assert_success && assert_file_contains "$BOOTSTRAP_LOG" "installer_lock=held"
}

test_bootstrap_failure_preserves_status_and_artifacts() {
  # Given: a marked install with runtime data and bootstrap exit status 37.
  write_bootstrap_double 37
  mark_existing_target
  mkdir -p "$TARGET_DIR/secrets"
  printf 'runtime-env\n' >"$TARGET_DIR/.env"
  printf 'secret\n' >"$TARGET_DIR/secrets/key"
  printf 'garage\n' >"$TARGET_DIR/garage.toml"

  # When: refreshed source bootstrap fails.
  invoke_installer "$VALID_DOMAIN" "$VALID_ADMIN_EMAIL"

  # Then: installer returns exactly 37 and runtime artifacts remain in place.
  assert_status 37 &&
    assert_file_contains "$TARGET_DIR/.env" "runtime-env" &&
    assert_file_contains "$TARGET_DIR/secrets/key" "secret" &&
    assert_file_contains "$TARGET_DIR/garage.toml" "garage"
}

test_stream_truncated_after_main_token_has_no_side_effects() {
  local prefix truncation_status

  # Given: a curl-like stream cut immediately after the final main token.
  write_bootstrap_double
  prefix="$TEST_ROOT/truncated-club"
  python3 - "$INSTALLER" "$prefix" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
cut = source.rfind("main") + len("main")
pathlib.Path(sys.argv[2]).write_text(source[:cut])
PY

  # When: Bash parses the syntactically incomplete prefix.
  if PATH="$FAKE_BIN:/usr/bin:/bin" DOMAIN="$VALID_DOMAIN" ADMIN_EMAIL="$VALID_ADMIN_EMAIL" \
    CLUB_INSTALLER_TEST_MODE=1 CLUB_INSTALLER_TEST_TARGET_DIR="$TARGET_DIR" \
    CLUB_INSTALLER_TEST_OS_RELEASE="$OS_RELEASE" CLUB_INSTALLER_TEST_EUID=0 \
    CLUB_INSTALLER_TEST_LOCK_FILE="$LOCK_FILE" "$BASH_BIN" "$prefix"; then
    truncation_status=0
  else
    truncation_status=$?
  fi

  # Then: no host, Git, target, or bootstrap side effect occurs.
  [[ "$truncation_status" -ne 0 ]] && assert_file_empty "$COMMAND_LOG" &&
    [[ ! -e "$BOOTSTRAP_LOG" && ! -e "$TARGET_DIR/.community-club-installer" ]]
}

TESTS+=(
  "bootstrap environment is sanitized|test_bootstrap_receives_only_canonical_environment"
  "lock is held through bootstrap|test_bootstrap_runs_while_installer_lock_is_held"
  "bootstrap status and artifacts survive failure|test_bootstrap_failure_preserves_status_and_artifacts"
  "stream truncated after main token has no side effects|test_stream_truncated_after_main_token_has_no_side_effects"
)
