#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_ROOT
readonly SOURCE_REPOSITORY="${COMMUNITY_CLUB_SOURCE_REPOSITORY:-$PROJECT_ROOT/../community-club-source}"
readonly EXPECTED_COMMIT="eba5585bf7651447ebd6f93ce0ddfb259ad49983"
readonly EXPECTED_SHA256="655340deb1ffddb8aa6094e378fe38ed2244e678b0608ccf5cc068cc8a33ef7e"
readonly EXPECTED_SIZE="12206080"
readonly ARTIFACT="$PROJECT_ROOT/artifacts/community-club-$EXPECTED_COMMIT.tar"
TEMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Given: the trusted local application repository at the exact pinned commit.
generated="$TEMP_DIR/community-club-$EXPECTED_COMMIT.tar"

# When: the release generator creates the archive again from Git objects.
"$PROJECT_ROOT/scripts/generate-source-archive.sh" "$SOURCE_REPOSITORY" "$generated"

# Then: generated and packaged bytes have the exact trusted identity.
cmp "$ARTIFACT" "$generated"
[[ "$(stat -c %s "$ARTIFACT")" == "$EXPECTED_SIZE" ]]
printf '%s  %s\n' "$EXPECTED_SHA256" "$ARTIFACT" | sha256sum --check --status

# Given: the real packaged archive and a fresh extraction directory.
extracted="$TEMP_DIR/extracted"
mkdir "$extracted"
mapfile -t archive_prefixes < <(tar -tf "$ARTIFACT" | cut -d/ -f1 | sort -u)

# When: the artifact is extracted with the installer tar flags.
env -i PATH=/usr/bin:/bin HOME=/root LANG=C LC_ALL=C \
  tar --extract --file="$ARTIFACT" --directory="$extracted" \
  --strip-components=1 --no-same-owner --no-same-permissions

# Then: one expected root prefix exists and bootstrap is a regular executable file.
[[ "${#archive_prefixes[@]}" -eq 1 ]]
[[ "${archive_prefixes[0]}" == "community-club-$EXPECTED_COMMIT" ]]
bootstrap="$extracted/scripts/server-bootstrap.sh"
[[ -f "$bootstrap" && ! -L "$bootstrap" && -x "$bootstrap" ]]

# Given: the immutable output path already contains verified archive bytes.
before_sha256="$(sha256sum "$generated")"

# When: release generation targets the same existing path again.
if "$PROJECT_ROOT/scripts/generate-source-archive.sh" "$SOURCE_REPOSITORY" "$generated"; then
  printf 'Expected generation to refuse an existing output path\n' >&2
  exit 1
fi

# Then: generation fails and leaves the existing bytes unchanged.
[[ "$(sha256sum "$generated")" == "$before_sha256" ]]
cmp "$ARTIFACT" "$generated"

printf 'Release archive test passed\n'
