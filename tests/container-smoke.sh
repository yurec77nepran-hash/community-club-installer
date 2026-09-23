#!/usr/bin/env bash

set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SCRIPT_ROOT
readonly COMPOSE_FILE="$SCRIPT_ROOT/compose.yaml"
readonly SERVICE_NAME="community-club-installer"
readonly EXPECTED_REPOSITORY="https://github.com/yurec77nepran-hash/community-club-source.git"
readonly EXPECTED_SHA="1ac31045e815d5b12569b34cbeaf53b97a7e81d0"
readonly PROJECT_NAME="community-club-installer-smoke-${USER:-unknown}-$$"
readonly HEALTH_TIMEOUT="${CONTAINER_SMOKE_TIMEOUT:-30}"
readonly HTTP_PORT="${CONTAINER_SMOKE_HTTP_PORT:-0}"
TEMP_DIR=""

compose() {
  docker compose --project-name "$PROJECT_NAME" --file "$COMPOSE_FILE" "$@"
}

cleanup() {
  compose down --remove-orphans >/dev/null 2>&1 || true
  [[ -z "$TEMP_DIR" ]] || rm -rf "$TEMP_DIR"
}

require_docker() {
  command -v docker >/dev/null 2>&1 || {
    printf 'Docker is required to run the container smoke test\n' >&2
    exit 127
  }
  docker compose version >/dev/null 2>&1 || {
    printf 'Docker Compose v2 is required to run the container smoke test\n' >&2
    exit 127
  }
}

assert_compose_contract() {
  local effective_config
  effective_config="$(compose config)"

  grep -Fq 'host_ip: 127.0.0.1' <<<"$effective_config" || {
    printf 'Compose must publish HTTP only on 127.0.0.1\n' >&2
    return 1
  }
  grep -Fq 'target: 8080' <<<"$effective_config" || {
    printf 'Compose must publish container port 8080\n' >&2
    return 1
  }
  [[ "$(grep -Ec '^[[:space:]]+target: ' <<<"$effective_config")" -eq 1 ]] || {
    printf 'Compose must publish exactly one container port\n' >&2
    return 1
  }
  if grep -Eq '8443|protocol: udp|caddy_data|caddy_config|^[[:space:]]*volumes:' <<<"$effective_config"; then
    printf 'Compose must not publish TLS/UDP ports or mount volumes\n' >&2
    return 1
  fi
}

require_docker
export HTTP_PORT
assert_compose_contract
trap cleanup EXIT

compose up --detach \
  --build \
  --wait \
  --wait-timeout "$HEALTH_TIMEOUT"

published_http_endpoint="$(compose port "$SERVICE_NAME" 8080)"
[[ "$published_http_endpoint" == 127.0.0.1:* ]] || {
  printf 'Published HTTP endpoint is not loopback-only: %s\n' "$published_http_endpoint" >&2
  exit 1
}
published_http_port="${published_http_endpoint##*:}"
base_url="http://127.0.0.1:$published_http_port"

TEMP_DIR="$(mktemp -d)"
health_headers="$TEMP_DIR/health.headers"
health_body="$TEMP_DIR/health.json"
club_headers="$TEMP_DIR/club.headers"
club_body="$TEMP_DIR/club"

curl --fail --silent --show-error --dump-header "$health_headers" \
  "$base_url/health" >"$health_body"
grep -iq '^content-type: application/json; charset=utf-8' "$health_headers"
expected_health="{\"service\":\"community-club-installer\",\"commit\":\"$EXPECTED_SHA\"}"
[[ "$(<"$health_body")" == "$expected_health" ]] || {
  printf 'Health response does not identify the service and pinned SHA\n' >&2
  exit 1
}

curl --fail --silent --show-error --dump-header "$club_headers" \
  "$base_url/club" >"$club_body"
grep -iq '^content-type: text/plain' "$club_headers"
grep -iq '^x-content-type-options: nosniff' "$club_headers"
bash -n "$club_body"
grep -Fqx 'set -euo pipefail' <(grep -E '^set -euo pipefail$' "$club_body")
grep -Fqx "readonly REPOSITORY='$EXPECTED_REPOSITORY'" "$club_body"
grep -Fqx "readonly COMMIT='$EXPECTED_SHA'" "$club_body"

unknown_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  "$base_url/unknown")"
[[ "$unknown_status" == '404' ]] || {
  printf 'Unknown path returned HTTP %s instead of 404\n' "$unknown_status" >&2
  exit 1
}

container_id="$(compose ps --quiet "$SERVICE_NAME")"
health_status="$(docker inspect --format '{{.State.Health.Status}}' "$container_id")"
[[ "$health_status" == 'healthy' ]] || {
  printf 'Container health status is %s instead of healthy\n' "$health_status" >&2
  exit 1
}

cleanup
trap - EXIT
printf 'Container smoke test passed\n'
