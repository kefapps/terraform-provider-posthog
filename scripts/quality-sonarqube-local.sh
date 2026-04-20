#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolve_git_common_dir() {
  local repo_dir="$1"
  local common_dir
  common_dir="$(git -C "$repo_dir" rev-parse --git-common-dir)"
  if [[ "$common_dir" = /* ]]; then
    printf '%s\n' "$common_dir"
  else
    printf '%s\n' "$repo_dir/$common_dir"
  fi
}

GIT_COMMON_DIR="$(resolve_git_common_dir "$ROOT_DIR")"
STATE_DIR="${SONAR_STATE_DIR:-$GIT_COMMON_DIR/posthog-terraform-provider-sonarqube}"
ENV_FILE="$STATE_DIR/.env.local"
BOOTSTRAP_SOURCE_REPO="${SONAR_BOOTSTRAP_SOURCE_REPO:-$ROOT_DIR/../../keftionnaire}"

MODE="${1:-bootstrap}"
FORMAT="text"
if [[ "${2:-}" == "--format" ]]; then
  FORMAT="${3:-text}"
fi

mkdir -p "$STATE_DIR"

emit_env_lines() {
  local source_file="$1"
  python3 - "$source_file" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
if not path.exists():
    sys.exit(0)

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

load_env_file() {
  local source_file="$1"
  if [[ ! -f "$source_file" ]]; then
    return 0
  fi

  while IFS=$'\t' read -r env_key env_value; do
    if [[ -n "$env_key" ]]; then
      export "${env_key}=${env_value}"
    fi
  done < <(emit_env_lines "$source_file")
}

write_env_file() {
  local target_file="$1"
  python3 - "$target_file" <<'PY'
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
keys = [
    "SONAR_HOST_URL",
    "SONAR_PROJECT_KEY",
    "SONAR_PROJECT_NAME",
    "SONAR_TOKEN_NAME",
    "SONAR_TOKEN",
    "SONAR_REFERENCE_BRANCH",
    "SONAR_ADMIN_LOGIN",
    "SONAR_ADMIN_PASSWORD",
    "SONAR_SCANNER_IMAGE",
]
lines = []
for key in keys:
    value = os.environ.get(key, "")
    lines.append(f"{key}={value}")
path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
}

json_status() {
  python3 - <<'PY'
import json
import os

payload = {
    "envPath": os.environ["ENV_FILE"],
    "envFilePresent": os.path.exists(os.environ["ENV_FILE"]),
    "hostUrl": os.environ.get("SONAR_HOST_URL", ""),
    "projectKey": os.environ.get("SONAR_PROJECT_KEY", ""),
    "tokenName": os.environ.get("SONAR_TOKEN_NAME", ""),
    "bootstrapSourceRepo": os.environ.get("BOOTSTRAP_SOURCE_REPO", ""),
}
print(json.dumps(payload, indent=2))
PY
}

validate_token() {
  local base_url="$1"
  local token="$2"
  if [[ -z "$token" ]]; then
    return 1
  fi

  local response
  response="$(curl -fsS -H "Authorization: Bearer $token" \
    "$base_url/api/authentication/validate" 2>/dev/null || true)"
  [[ "$response" == *'"valid":true'* ]]
}

validate_basic_auth() {
  local base_url="$1"
  local login="$2"
  local password="$3"
  if [[ -z "$login" || -z "$password" ]]; then
    return 1
  fi

  local response
  response="$(curl -fsS -u "$login:$password" \
    "$base_url/api/authentication/validate" 2>/dev/null || true)"
  [[ "$response" == *'"valid":true'* ]]
}

seed_from_keftionnaire() {
  if [[ ! -d "$BOOTSTRAP_SOURCE_REPO" ]]; then
    return 0
  fi

  local seed_git_common_dir
  seed_git_common_dir="$(resolve_git_common_dir "$BOOTSTRAP_SOURCE_REPO" 2>/dev/null || true)"
  if [[ -z "$seed_git_common_dir" ]]; then
    return 0
  fi

  local seed_env_file="$seed_git_common_dir/ansyo-sonarqube/.env.local"
  if [[ ! -f "$seed_env_file" ]]; then
    return 0
  fi

  local seed_sonar_host_url="${SONAR_HOST_URL:-}"
  local seed_sonar_project_key="${SONAR_PROJECT_KEY:-}"
  local seed_sonar_project_name="${SONAR_PROJECT_NAME:-}"
  local seed_sonar_token_name="${SONAR_TOKEN_NAME:-}"
  local seed_sonar_token="${SONAR_TOKEN:-}"
  local seed_sonar_reference_branch="${SONAR_REFERENCE_BRANCH:-}"
  local seed_sonar_admin_login="${SONAR_ADMIN_LOGIN:-}"
  local seed_sonar_admin_password="${SONAR_ADMIN_PASSWORD:-}"
  local seed_sonar_scanner_image="${SONAR_SCANNER_IMAGE:-}"

  load_env_file "$seed_env_file"

  if [[ -n "$seed_sonar_host_url" ]]; then
    export SONAR_HOST_URL="$seed_sonar_host_url"
  fi
  if [[ -n "$seed_sonar_project_key" ]]; then
    export SONAR_PROJECT_KEY="$seed_sonar_project_key"
  fi
  if [[ -n "$seed_sonar_project_name" ]]; then
    export SONAR_PROJECT_NAME="$seed_sonar_project_name"
  fi
  if [[ -n "$seed_sonar_token_name" ]]; then
    export SONAR_TOKEN_NAME="$seed_sonar_token_name"
  fi
  if [[ -n "$seed_sonar_reference_branch" ]]; then
    export SONAR_REFERENCE_BRANCH="$seed_sonar_reference_branch"
  fi
  if [[ -n "$seed_sonar_scanner_image" ]]; then
    export SONAR_SCANNER_IMAGE="$seed_sonar_scanner_image"
  fi

  if [[ -n "$seed_sonar_token" ]]; then
    export SONAR_TOKEN="$seed_sonar_token"
  fi
  if [[ -n "$seed_sonar_admin_login" ]]; then
    export SONAR_ADMIN_LOGIN="$seed_sonar_admin_login"
  fi
  if [[ -n "$seed_sonar_admin_password" ]]; then
    export SONAR_ADMIN_PASSWORD="$seed_sonar_admin_password"
  fi
}

ensure_project() {
  local response_file
  response_file="$(mktemp)"
  local status_code
  status_code="$(curl -sS -o "$response_file" -w "%{http_code}" \
    -u "$SONAR_ADMIN_LOGIN:$SONAR_ADMIN_PASSWORD" \
    -X POST "$SONAR_HOST_URL/api/projects/create" \
    --data-urlencode "project=$SONAR_PROJECT_KEY" \
    --data-urlencode "name=$SONAR_PROJECT_NAME")"

  if [[ "$status_code" == "200" ]]; then
    rm -f "$response_file"
    return 0
  fi

  if grep -q "already exists" "$response_file"; then
    rm -f "$response_file"
    return 0
  fi

  cat "$response_file" >&2
  rm -f "$response_file"
  echo "Failed to ensure Sonar project '$SONAR_PROJECT_KEY' (HTTP $status_code)." >&2
  exit 1
}

generate_token() {
  curl -fsS -u "$SONAR_ADMIN_LOGIN:$SONAR_ADMIN_PASSWORD" \
    -X POST "$SONAR_HOST_URL/api/user_tokens/revoke" \
    --data-urlencode "name=$SONAR_TOKEN_NAME" >/dev/null 2>&1 || true

  curl -fsS -u "$SONAR_ADMIN_LOGIN:$SONAR_ADMIN_PASSWORD" \
    -X POST "$SONAR_HOST_URL/api/user_tokens/generate" \
    --data-urlencode "name=$SONAR_TOKEN_NAME" \
    | python3 - <<'PY'
import json
import sys

payload = json.load(sys.stdin)
token = payload.get("token", "")
if not token:
    raise SystemExit("SonarQube did not return a scanner token.")
print(token)
PY
}

bootstrap() {
  export SONAR_HOST_URL="${SONAR_HOST_URL:-http://localhost:9000}"
  export SONAR_PROJECT_KEY="${SONAR_PROJECT_KEY:-posthog-terraform-provider}"
  export SONAR_PROJECT_NAME="${SONAR_PROJECT_NAME:-posthog-terraform-provider}"
  export SONAR_TOKEN_NAME="${SONAR_TOKEN_NAME:-posthog-terraform-provider-local-scanner}"
  export SONAR_REFERENCE_BRANCH="${SONAR_REFERENCE_BRANCH:-main}"
  export SONAR_ADMIN_LOGIN="${SONAR_ADMIN_LOGIN:-admin}"
  export SONAR_ADMIN_PASSWORD="${SONAR_ADMIN_PASSWORD:-}"
  export SONAR_SCANNER_IMAGE="${SONAR_SCANNER_IMAGE:-sonarsource/sonar-scanner-cli:12.1.0.3225_8.0.1}"
  export SONAR_TOKEN="${SONAR_TOKEN:-}"

  load_env_file "$ENV_FILE"

  if ! validate_token "$SONAR_HOST_URL" "$SONAR_TOKEN"; then
    seed_from_keftionnaire
  fi

  if validate_token "$SONAR_HOST_URL" "$SONAR_TOKEN"; then
    write_env_file "$ENV_FILE"
    echo "$ENV_FILE"
    return 0
  fi

  if ! validate_basic_auth "$SONAR_HOST_URL" "$SONAR_ADMIN_LOGIN" "$SONAR_ADMIN_PASSWORD"; then
    if [[ -z "$SONAR_ADMIN_PASSWORD" ]] && validate_basic_auth "$SONAR_HOST_URL" "admin" "admin"; then
      export SONAR_ADMIN_LOGIN="admin"
      export SONAR_ADMIN_PASSWORD="admin"
    else
      echo "Unable to authenticate to local SonarQube. Seed the local state or provide SONAR_ADMIN_LOGIN/SONAR_ADMIN_PASSWORD." >&2
      exit 1
    fi
  fi

  ensure_project
  export SONAR_TOKEN="$(generate_token)"
  write_env_file "$ENV_FILE"
  echo "$ENV_FILE"
}

case "$MODE" in
  bootstrap)
    bootstrap
    ;;
  env-path)
    echo "$ENV_FILE"
    ;;
  status)
    load_env_file "$ENV_FILE"
    if [[ "$FORMAT" == "json" ]]; then
      export ENV_FILE BOOTSTRAP_SOURCE_REPO
      json_status
    else
      echo "env_path=$ENV_FILE env_present=$([[ -f "$ENV_FILE" ]] && echo yes || echo no) host=${SONAR_HOST_URL:-} project=${SONAR_PROJECT_KEY:-}"
    fi
    ;;
  reset)
    rm -rf "$STATE_DIR"
    echo "reset $STATE_DIR"
    ;;
  *)
    echo "Unsupported mode: $MODE" >&2
    exit 1
    ;;
esac
