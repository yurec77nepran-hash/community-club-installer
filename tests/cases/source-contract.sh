#!/usr/bin/env bash

test_source_coordinates_do_not_drift() {
  # Given: every file that publishes or verifies the selected application source.
  # When: the source contract is parsed with Python's standard library.
  # Then: repository and full SHA agree everywhere.
  python3 - "$PROJECT_ROOT" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
source = json.loads((root / "config/source.json").read_text())
repository = source["repository"]
commit = source["commit"]

if re.fullmatch(r"[0-9a-f]{40}", commit) is None:
    raise SystemExit("config/source.json commit is not a full lowercase SHA")

installer = (root / "scripts/club").read_text()
support = (root / "tests/support/installer-test-support.sh").read_text()
smoke = (root / "tests/container-smoke.sh").read_text()
caddy = (root / "Caddyfile").read_text()
compose = (root / "compose.yaml").read_text()
dockerfile = (root / "Dockerfile").read_text()

expected_literals = {
    "scripts/club repository": f"readonly REPOSITORY='{repository}'",
    "scripts/club commit": f"readonly COMMIT='{commit}'",
    "test support repository": f'readonly EXPECTED_REPOSITORY="{repository}"',
    "test support commit": f'readonly EXPECTED_COMMIT="{commit}"',
    "container smoke repository": f'readonly EXPECTED_REPOSITORY="{repository}"',
    "container smoke commit": f'readonly EXPECTED_SHA="{commit}"',
}
files = {
    "scripts/club repository": installer,
    "scripts/club commit": installer,
    "test support repository": support,
    "test support commit": support,
    "container smoke repository": smoke,
    "container smoke commit": smoke,
}
for label, literal in expected_literals.items():
    if literal not in files[label]:
        raise SystemExit(f"source drift: {label}")

health_commits = re.findall(r'\\"commit\\":\\"([0-9a-f]{40})\\"', caddy)
if health_commits != [commit]:
    raise SystemExit("source drift: Caddy health commit")

required_container_contract = {
    "Caddy HTTP listener": (":8080 {", caddy),
    "loopback-only Compose port": ('"127.0.0.1:${HTTP_PORT:-3980}:8080"', compose),
    "Docker HTTP port": ("EXPOSE 8080", dockerfile),
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
PY
}

TESTS+=(
  "source coordinates do not drift|test_source_coordinates_do_not_drift"
)
