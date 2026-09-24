#!/usr/bin/env bash

PROJECT_ROOT="$(cd "$TESTS_ROOT/.." && pwd)"
readonly PROJECT_ROOT
readonly INSTALLER="$PROJECT_ROOT/scripts/club"
readonly EXPECTED_COMMIT="eba5585bf7651447ebd6f93ce0ddfb259ad49983"
readonly EXPECTED_ARCHIVE_SHA256="655340deb1ffddb8aa6094e378fe38ed2244e678b0608ccf5cc068cc8a33ef7e"
readonly EXPECTED_ARCHIVE_SIZE="12206080"
readonly EXPECTED_ARCHIVE_PATH="/artifacts/community-club-$EXPECTED_COMMIT.tar"
readonly EXPECTED_ARCHIVE_URL="https://shablon-clud.nepran-yuri.ru$EXPECTED_ARCHIVE_PATH"
readonly INSTALLER_MARKER="community-club-installer-v1"
readonly VALID_DOMAIN="club.example.com"
readonly VALID_ADMIN_EMAIL="admin@example.com"
BASH_BIN="$(command -v bash)"
readonly BASH_BIN

TEST_ROOT=""
FAKE_BIN=""
TARGET_DIR=""
COMMAND_LOG=""
BOOTSTRAP_LOG=""
OS_RELEASE=""
LOCK_FILE=""
INSTALLER_OUTPUT=""
INSTALLER_STATUS=0

setup() {
  unset CLUB_TEST_EUID INSTALL_EMAIL REPOSITORY_URL COMMIT_SHA ARCHIVE_URL
  unset CLUB_REPOSITORY_URL CLUB_COMMIT_SHA CLUB_ARCHIVE_URL ADMIN_PASSWORD COMPOSE_FILE
  unset DOCKER_HOST BASH_ENV ENV CDPATH GIT_DIR GIT_WORK_TREE TAR_OPTIONS

  TEST_ROOT="$(mktemp -d)"
  FAKE_BIN="$TEST_ROOT/bin"
  TARGET_DIR="$TEST_ROOT/community-club"
  COMMAND_LOG="$TEST_ROOT/commands.log"
  BOOTSTRAP_LOG="$TEST_ROOT/bootstrap.log"
  OS_RELEASE="$TEST_ROOT/os-release"
  LOCK_FILE="$TEST_ROOT/community-club-installer.lock"

  mkdir -p "$FAKE_BIN" "$TARGET_DIR"
  : >"$COMMAND_LOG"
  write_supported_os_release
  write_command_doubles
}

teardown() {
  rm -rf "$TEST_ROOT"
}

write_supported_os_release() {
  cat >"$OS_RELEASE" <<'EOF'
ID=ubuntu
VERSION_ID="24.04"
EOF
}

write_command_doubles() {
  cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
printf 'curl|' >>"$root/commands.log"
printf '%q ' "$@" >>"$root/commands.log"
printf '\n' >>"$root/commands.log"

output=""
max_filesize=""
previous=""
[[ "${1:-}" == '--disable' ]] || exit 65
for argument in "$@"; do
  [[ "$argument" != '--location' && "$argument" != '-L' ]] || exit 66
  if [[ "$previous" == '--output' ]]; then
    output="$argument"
  elif [[ "$previous" == '--max-filesize' ]]; then
    max_filesize="$argument"
  fi
  previous="$argument"
done

if [[ -f "$root/fail-download" ]]; then
  exit 22
fi
[[ -n "$output" ]] || exit 64
[[ "$max_filesize" == "$(stat -c %s "$root/source.tar")" ]] || exit 67
if [[ -f "$root/corrupt-download" ]]; then
  printf 'corrupt archive\n' >"$output"
else
  /bin/cp "$root/source.tar" "$output"
  if [[ -f "$root/corrupt-same-size-download" ]]; then
    printf 'X' | dd of="$output" bs=1 seek=0 conv=notrunc status=none
  fi
fi
EOF

  cat >"$FAKE_BIN/cp" <<'EOF'
#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$root/fail-source-copy" && "${2:-}" == */source/. ]]; then
  exit 73
fi
exec /bin/cp "$@"
EOF

  for command_name in apt-get docker systemctl chown; do
    cat >"$FAKE_BIN/$command_name" <<'EOF'
#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
printf '%s|' "${0##*/}" >>"$root/commands.log"
printf '%q ' "$@" >>"$root/commands.log"
printf '\n' >>"$root/commands.log"
exit 0
EOF
  done

  chmod +x "$FAKE_BIN"/*
}

build_source_archive() {
  local archive_root="$TEST_ROOT/archive/community-club-$EXPECTED_COMMIT"

  mkdir -p "$archive_root/scripts"
  cp "$TEST_ROOT/server-bootstrap.sh" "$archive_root/scripts/server-bootstrap.sh"
  chmod 0755 "$archive_root/scripts/server-bootstrap.sh"
  printf 'staged-garage\n' >"$archive_root/garage.toml"
  if [[ -f "$TEST_ROOT/unsafe-bootstrap-mode" ]]; then
    chmod 0644 "$archive_root/scripts/server-bootstrap.sh"
  fi
  if [[ -f "$TEST_ROOT/symlink-bootstrap" ]]; then
    rm "$archive_root/scripts/server-bootstrap.sh"
    ln -s /bin/true "$archive_root/scripts/server-bootstrap.sh"
  fi
  env -i PATH=/usr/bin:/bin tar -C "$TEST_ROOT/archive" -cf "$TEST_ROOT/source.tar" \
    "community-club-$EXPECTED_COMMIT"
}

write_bootstrap_double() {
  local exit_code="${1:-0}"

  cat >"$TEST_ROOT/server-bootstrap.sh" <<EOF
#!/usr/bin/env bash
set -u
env | sort >"$BOOTSTRAP_LOG"
printf 'argc=%s\n' "\$#" >>"$BOOTSTRAP_LOG"
if flock -n "$LOCK_FILE" true; then
  printf 'installer_lock=free\n' >>"$BOOTSTRAP_LOG"
else
  printf 'installer_lock=held\n' >>"$BOOTSTRAP_LOG"
fi
exit $exit_code
EOF
  chmod +x "$TEST_ROOT/server-bootstrap.sh"
}

mark_existing_target() {
  printf '%s\n' "$INSTALLER_MARKER" >"$TARGET_DIR/.community-club-installer"
  chmod 0600 "$TARGET_DIR/.community-club-installer"
}

invoke_installer() {
  local domain="$1"
  local admin_email="$2"

  build_source_archive
  local archive_sha256 archive_size
  archive_sha256="$(sha256sum "$TEST_ROOT/source.tar")"
  archive_sha256="${archive_sha256%% *}"
  archive_size="$(stat -c %s "$TEST_ROOT/source.tar")"

  set +e
  INSTALLER_OUTPUT="$({
    if [[ "$domain" == "__UNSET__" ]]; then
      unset DOMAIN
    else
      export DOMAIN="$domain"
    fi
    if [[ "$admin_email" == "__UNSET__" ]]; then
      unset ADMIN_EMAIL
    else
      export ADMIN_EMAIL="$admin_email"
    fi

    export PATH="$FAKE_BIN:/usr/bin:/bin"
    export CLUB_INSTALLER_TEST_MODE=1
    export CLUB_INSTALLER_TEST_OS_RELEASE="$OS_RELEASE"
    export CLUB_INSTALLER_TEST_EUID="${CLUB_TEST_EUID:-0}"
    export CLUB_INSTALLER_TEST_TARGET_DIR="$TARGET_DIR"
    export CLUB_INSTALLER_TEST_LOCK_FILE="$LOCK_FILE"
    export CLUB_INSTALLER_TEST_ARCHIVE_SHA256="$archive_sha256"
    export CLUB_INSTALLER_TEST_ARCHIVE_SIZE="$archive_size"
    "$BASH_BIN" "$INSTALLER"
  } 2>&1)"
  INSTALLER_STATUS=$?
}

assert_success() {
  [[ "$INSTALLER_STATUS" -eq 0 ]] || {
    printf 'expected exit 0, got %s; output: %s\n' "$INSTALLER_STATUS" "$INSTALLER_OUTPUT" >&2
    return 1
  }
}

assert_failure() {
  [[ "$INSTALLER_STATUS" -ne 0 ]] || {
    printf 'expected a non-zero exit; output: %s\n' "$INSTALLER_OUTPUT" >&2
    return 1
  }
}

assert_status() {
  local expected="$1"
  [[ "$INSTALLER_STATUS" -eq "$expected" ]] || {
    printf 'expected exit %s, got %s; output: %s\n' "$expected" "$INSTALLER_STATUS" "$INSTALLER_OUTPUT" >&2
    return 1
  }
}

assert_file_empty() {
  local path="$1"
  [[ ! -s "$path" ]] || {
    printf 'expected %s to be empty\n' "$path" >&2
    return 1
  }
}

assert_file_contains() {
  local path="$1"
  local expected="$2"
  if [[ ! -f "$path" ]] || ! grep -Fq -- "$expected" "$path"; then
    printf 'expected %s to contain: %s\n' "$path" "$expected" >&2
    return 1
  fi
}

assert_file_excludes() {
  local path="$1"
  local unexpected="$2"
  if [[ -f "$path" ]] && grep -Fq -- "$unexpected" "$path"; then
    printf 'expected %s not to contain: %s\n' "$path" "$unexpected" >&2
    return 1
  fi
}

run_test() {
  local name="$1"
  local test_function="$2"
  local status=0

  setup
  "$test_function" || status=$?
  teardown

  if [[ "$status" -eq 0 ]]; then
    printf 'ok - %s\n' "$name"
  else
    printf 'not ok - %s\n' "$name"
  fi
  return "$status"
}

run_all_tests() {
  local failures=0
  local test_case name test_function

  for test_case in "${TESTS[@]}"; do
    IFS='|' read -r name test_function <<<"$test_case"
    run_test "$name" "$test_function" || failures=$((failures + 1))
  done

  printf '\n%s tests, %s failures\n' "${#TESTS[@]}" "$failures"
  [[ "$failures" -eq 0 ]]
}
