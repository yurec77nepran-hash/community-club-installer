#!/usr/bin/env bash

test_source_coordinates_do_not_drift() {
  # Given: every file that publishes or verifies the selected application archive.
  # When: the source contract is parsed with Python's standard library.
  # Then: commit, immutable URL, SHA-256, and byte size agree everywhere.
  python3 - "$PROJECT_ROOT" <<'PY'
import json
import hashlib
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
source = json.loads((root / "config/source.json").read_text())
commit = source["commit"]
archive_path = source["archivePath"]
archive_url = source["archiveUrl"]
archive_sha256 = source["sha256"]
archive_size = source["size"]

if re.fullmatch(r"[0-9a-f]{40}", commit) is None:
    raise SystemExit("config/source.json commit is not a full lowercase SHA")
if archive_path != f"/artifacts/community-club-{commit}.tar":
    raise SystemExit("config/source.json archive path is not content-addressed")
if archive_url != f"https://shablon-clud.nepran-yuri.ru{archive_path}":
    raise SystemExit("config/source.json archive URL does not match public HTTPS path")
if re.fullmatch(r"[0-9a-f]{64}", archive_sha256) is None or not isinstance(archive_size, int):
    raise SystemExit("config/source.json archive identity is invalid")

installer = (root / "scripts/club").read_text()
support = (root / "tests/support/installer-test-support.sh").read_text()
smoke = (root / "tests/container-smoke.sh").read_text()
caddy = (root / "Caddyfile").read_text()
compose = (root / "compose.yaml").read_text()
dockerfile = (root / "Dockerfile").read_text()
generator = (root / "scripts/generate-source-archive.sh").read_text()
artifact = root / archive_path.removeprefix("/")

expected_literals = {
    "scripts/club commit": f"readonly COMMIT='{commit}'",
    "scripts/club archive URL": f"readonly ARCHIVE_URL='{archive_url}'",
    "scripts/club archive SHA-256": f"readonly ARCHIVE_SHA256='{archive_sha256}'",
    "scripts/club archive size": f"readonly ARCHIVE_SIZE='{archive_size}'",
    "test support commit": f'readonly EXPECTED_COMMIT="{commit}"',
    "test support archive SHA-256": f'readonly EXPECTED_ARCHIVE_SHA256="{archive_sha256}"',
    "test support archive size": f'readonly EXPECTED_ARCHIVE_SIZE="{archive_size}"',
    "container smoke commit": f'readonly EXPECTED_SHA="{commit}"',
    "container smoke archive SHA-256": f'readonly EXPECTED_ARCHIVE_SHA256="{archive_sha256}"',
    "container smoke archive size": f'readonly EXPECTED_ARCHIVE_SIZE="{archive_size}"',
}
files = {
    "scripts/club commit": installer,
    "scripts/club archive URL": installer,
    "scripts/club archive SHA-256": installer,
    "scripts/club archive size": installer,
    "test support commit": support,
    "test support archive SHA-256": support,
    "test support archive size": support,
    "container smoke commit": smoke,
    "container smoke archive SHA-256": smoke,
    "container smoke archive size": smoke,
}
for label, literal in expected_literals.items():
    if literal not in files[label]:
        raise SystemExit(f"source drift: {label}")

if artifact.stat().st_size != archive_size:
    raise SystemExit("packaged archive size does not match source contract")
if hashlib.sha256(artifact.read_bytes()).hexdigest() != archive_sha256:
    raise SystemExit("packaged archive SHA-256 does not match source contract")

generator_literals = (
    f"readonly COMMIT='{commit}'",
    f"readonly EXPECTED_SHA256='{archive_sha256}'",
    f"readonly EXPECTED_SIZE='{archive_size}'",
    "archive --format=tar --prefix=",
)
for literal in generator_literals:
    if literal not in generator:
        raise SystemExit(f"release generator contract drift: {literal}")
for forbidden in (" fetch ", " clone ", "credential", "GIT_ASKPASS", "https://"):
    if forbidden in generator:
        raise SystemExit(f"release generator must remain local-only: {forbidden}")

health_commits = re.findall(r'\\"commit\\":\\"([0-9a-f]{40})\\"', caddy)
if health_commits != [commit]:
    raise SystemExit("source drift: Caddy health commit")

required_container_contract = {
    "Caddy HTTP listener": (":8080 {", caddy),
    "loopback-only Compose port": ('"127.0.0.1:${HTTP_PORT:-3980}:8080"', compose),
    "Docker HTTP port": ("EXPOSE 8080", dockerfile),
    "archive image copy": ("COPY --chmod=0444 artifacts/community-club-", dockerfile),
    "read-only filesystem": ("read_only: true", compose),
    "capability drop": ("cap_drop:\n      - ALL", compose),
    "no new privileges": ("no-new-privileges:true", compose),
}
for label, (literal, contents) in required_container_contract.items():
    if literal not in contents:
        raise SystemExit(f"container contract drift: {label}")

for obsolete in ("https_port", "8443", "tls "):
    if obsolete in caddy:
        raise SystemExit(f"container Caddy must not configure TLS: {obsolete}")
for obsolete in ("8443", "caddy_data", "caddy_config", "protocol: udp"):
    if obsolete in compose:
        raise SystemExit(f"Compose must not retain TLS state: {obsolete}")
if "8443" in dockerfile or "udp" in dockerfile.lower():
    raise SystemExit("Dockerfile must expose only HTTP port 8080")

required_archive_install = (
    "curl --disable --fail --silent --show-error --proto '=https'",
    "--max-filesize \"$VERIFIED_ARCHIVE_SIZE\"",
    "sha256sum --check --status",
    "tar --extract --file=\"$archive\"",
    "--strip-components=1 --no-same-owner --no-same-permissions",
)
for literal in required_archive_install:
    if literal not in installer:
        raise SystemExit(f"archive installation contract drift: {literal}")
sanitized_tar = re.compile(
    r'env -i PATH="\$EXEC_PATH" HOME=/root LANG=C LC_ALL=C\s+\\\s+tar --extract'
)
if sanitized_tar.search(installer) is None:
    raise SystemExit("archive extraction must run under sanitized env")
replacement_order = re.compile(r'prepare_staging\s+validate_target\s+replace_source')
if replacement_order.search(installer) is None:
    raise SystemExit("target must be revalidated after staging and immediately before replacement")
for forbidden in ("git fetch", "git checkout", "GIT_TERMINAL_PROMPT", "readonly REPOSITORY="):
    if forbidden in installer:
        raise SystemExit(f"installer retains target-side Git acquisition: {forbidden}")
curl_command = re.search(r'curl --disable[\s\S]*?"\$ARCHIVE_URL"', installer)
if curl_command is None:
    raise SystemExit("installer curl command is missing")
for redirect_option in ("--location", "--proto-redir", " -L "):
    if redirect_option in curl_command.group():
        raise SystemExit(f"installer must not follow archive redirects: {redirect_option}")
PY
}

TESTS+=(
  "source coordinates do not drift|test_source_coordinates_do_not_drift"
)
