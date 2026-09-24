#!/usr/bin/env bash

set -u

TESTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TESTS_ROOT

# shellcheck source=tests/support/installer-test-support.sh
source "$TESTS_ROOT/support/installer-test-support.sh"

if [[ ! -f "$INSTALLER" ]]; then
  printf 'not ok 1 - system under test exists: scripts/club\n' >&2
  printf '# Expected installer at %s\n' "$INSTALLER" >&2
  exit 1
fi

declare -a TESTS=()

# shellcheck source=tests/cases/input-validation.sh
source "$TESTS_ROOT/cases/input-validation.sh"
# shellcheck source=tests/cases/host-requirements.sh
source "$TESTS_ROOT/cases/host-requirements.sh"
# shellcheck source=tests/cases/prerequisites-contract.sh
source "$TESTS_ROOT/cases/prerequisites-contract.sh"
# shellcheck source=tests/cases/repository-safety.sh
source "$TESTS_ROOT/cases/repository-safety.sh"
# shellcheck source=tests/cases/filesystem-hardening.sh
source "$TESTS_ROOT/cases/filesystem-hardening.sh"
# shellcheck source=tests/cases/bootstrap-contract.sh
source "$TESTS_ROOT/cases/bootstrap-contract.sh"
# shellcheck source=tests/cases/source-contract.sh
source "$TESTS_ROOT/cases/source-contract.sh"

run_all_tests
