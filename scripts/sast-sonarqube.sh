#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

QUALITY_ENV_FILE="$("$ROOT_DIR/scripts/quality-sonarqube-local.sh" bootstrap)"

load_generated_env_file() {
  local env_file="$1"
  python3 - "$env_file" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
for raw_line in path.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("export "):
        line = line[7:]
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    key = key.strip()
    value = value.strip()
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        value = value[1:-1]
    print(f"{key}\t{value}")
PY
}

while IFS=$'\t' read -r env_key env_value; do
  if [[ -n "$env_key" ]]; then
    export "${env_key}=${env_value}"
  fi
done < <(load_generated_env_file "$QUALITY_ENV_FILE")

if [[ -z "${SONAR_TOKEN:-}" ]]; then
  echo "SONAR_TOKEN is required. Bootstrap failed for $QUALITY_ENV_FILE" >&2
  exit 1
fi

SONAR_HOST_URL="${SONAR_HOST_URL:-http://localhost:9000}"
SONAR_SCANNER_IMAGE="${SONAR_SCANNER_IMAGE:-sonarsource/sonar-scanner-cli:12.1.0.3225_8.0.1}"
SONAR_REFERENCE_BRANCH="${SONAR_REFERENCE_BRANCH:-main}"
SONAR_COVERAGE_FILE="${SONAR_COVERAGE_FILE:-coverage.out}"
CURRENT_BRANCH="$(git branch --show-current 2>/dev/null || true)"

SCANNER_ARGS=(
  "-Dsonar.host.url=${SONAR_HOST_URL}"
  "-Dsonar.token=${SONAR_TOKEN}"
  "-Dsonar.projectKey=${SONAR_PROJECT_KEY:-posthog-terraform-provider}"
  "-Dsonar.projectName=${SONAR_PROJECT_NAME:-posthog-terraform-provider}"
  "-Dsonar.qualitygate.wait=true"
)

if [[ -n "${SONAR_QUALITYGATE_TIMEOUT:-}" ]]; then
  SCANNER_ARGS+=("-Dsonar.qualitygate.timeout=${SONAR_QUALITYGATE_TIMEOUT}")
fi

if [[ -n "${SONAR_BRANCH_NAME:-}" ]]; then
  SCANNER_ARGS+=("-Dsonar.branch.name=${SONAR_BRANCH_NAME}")
elif [[ -n "$CURRENT_BRANCH" && "$CURRENT_BRANCH" != "$SONAR_REFERENCE_BRANCH" ]]; then
  SCANNER_ARGS+=("-Dsonar.branch.name=${CURRENT_BRANCH}")
fi

analysis_branch="${SONAR_BRANCH_NAME:-$CURRENT_BRANCH}"
if [[ -n "$analysis_branch" && "$analysis_branch" != "$SONAR_REFERENCE_BRANCH" ]]; then
  SCANNER_ARGS+=("-Dsonar.newCode.referenceBranch=${SONAR_REFERENCE_BRANCH}")
fi

go test -coverprofile="$SONAR_COVERAGE_FILE" -covermode=atomic ./...

if command -v sonar-scanner >/dev/null 2>&1; then
  sonar-scanner "${SCANNER_ARGS[@]}"
else
  docker_sonar_host_url="${SONAR_DOCKER_HOST_URL:-$SONAR_HOST_URL}"
  docker_sonar_host_url="${docker_sonar_host_url/127.0.0.1/host.docker.internal}"
  docker_sonar_host_url="${docker_sonar_host_url/localhost/host.docker.internal}"

  docker run --rm \
    -v "$PWD:/usr/src" \
    "$SONAR_SCANNER_IMAGE" \
    "-Dsonar.host.url=${docker_sonar_host_url}" \
    "-Dsonar.token=${SONAR_TOKEN}" \
    "-Dsonar.projectKey=${SONAR_PROJECT_KEY:-posthog-terraform-provider}" \
    "-Dsonar.projectName=${SONAR_PROJECT_NAME:-posthog-terraform-provider}" \
    "${SCANNER_ARGS[@]:4}"
fi
