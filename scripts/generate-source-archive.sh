#!/usr/bin/env bash

set -euo pipefail

readonly COMMIT='eba5585bf7651447ebd6f93ce0ddfb259ad49983'
readonly EXPECTED_SHA256='655340deb1ffddb8aa6094e378fe38ed2244e678b0608ccf5cc068cc8a33ef7e'
readonly EXPECTED_SIZE='12206080'
readonly PREFIX="community-club-$COMMIT/"
readonly SOURCE_REPOSITORY="${1:-}"
readonly OUTPUT="${2:-}"

die() {
  printf 'Source archive generator: %s\n' "$1" >&2
  exit 1
}

[[ -n "$SOURCE_REPOSITORY" && -n "$OUTPUT" ]] ||
  die 'usage: generate-source-archive.sh SOURCE_REPOSITORY OUTPUT'
[[ -d "$SOURCE_REPOSITORY/.git" ]] || die 'source repository must be a local Git worktree'
[[ -d "${OUTPUT%/*}" ]] || die 'output directory does not exist'
[[ ! -e "$OUTPUT" && ! -L "$OUTPUT" ]] || die 'output path already exists'

resolved_commit="$(git -C "$SOURCE_REPOSITORY" rev-parse --verify "$COMMIT^{commit}")"
[[ "$resolved_commit" == "$COMMIT" ]] || die 'source repository does not contain the exact pinned commit'

read -r bootstrap_mode bootstrap_type _bootstrap_object bootstrap_path < <(
  git -C "$SOURCE_REPOSITORY" ls-tree "$COMMIT" -- scripts/server-bootstrap.sh
)
[[ "$bootstrap_mode" == '100755' && "$bootstrap_type" == 'blob' &&
  "$bootstrap_path" == 'scripts/server-bootstrap.sh' ]] ||
  die 'pinned bootstrap must be a regular executable Git blob'

while IFS=$' \t' read -r mode type _object path; do
  [[ "$mode" != '120000' ]] || die "pinned source contains a symlink: $path"
  [[ "$mode" != '160000' && "$type" != 'commit' ]] || die "pinned source contains a submodule: $path"
done < <(git -C "$SOURCE_REPOSITORY" ls-tree -r "$COMMIT")

tracked_runtime="$(git -C "$SOURCE_REPOSITORY" ls-tree --name-only "$COMMIT" -- \
  .env secrets .community-club-installer)"
[[ -z "$tracked_runtime" ]] || die "pinned source tracks forbidden root runtime state: $tracked_runtime"

temporary_output="$(mktemp "${OUTPUT}.tmp.XXXXXX")"
trap 'rm -f "$temporary_output"' EXIT
git -C "$SOURCE_REPOSITORY" archive --format=tar --prefix="$PREFIX" "$COMMIT" >"$temporary_output"

actual_size="$(stat -c %s "$temporary_output")"
[[ "$actual_size" == "$EXPECTED_SIZE" ]] || die "archive size mismatch: $actual_size"
printf '%s  %s\n' "$EXPECTED_SHA256" "$temporary_output" | sha256sum --check --status ||
  die 'archive SHA-256 mismatch'

chmod 0444 "$temporary_output"
mv --no-clobber "$temporary_output" "$OUTPUT"
[[ ! -e "$temporary_output" ]] || die 'output path appeared during generation'
trap - EXIT
printf '%s  %s bytes  %s\n' "$EXPECTED_SHA256" "$EXPECTED_SIZE" "$OUTPUT"
