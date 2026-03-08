#!/usr/bin/env bash
set -euo pipefail

# Move infra-related keys from app secret paths to secret/devops/<env>.
#
# Defaults:
# - Environments: staging + production (or all with first arg)
# - Source services: core-api,idp-api,spring-api
# - Keys: AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY,AWS_REGION,AWS_S3_BUCKET_NAME
# - Remove keys from source after move: true
# - Dry run: false

KV_MOUNT="${KV_MOUNT:-secret}"
TARGET_PREFIX="${TARGET_PREFIX:-devops}"
SOURCE_SERVICES="${SOURCE_SERVICES:-core-api,idp-api,spring-api}"
REMOVE_FROM_SOURCE="${REMOVE_FROM_SOURCE:-true}"
DRY_RUN="${DRY_RUN:-false}"
INFRA_KEYS="${INFRA_KEYS:-AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY,AWS_REGION,AWS_S3_BUCKET_NAME}"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [all|staging|production|development|default]

Environment variables:
  KV_MOUNT            KV mount name (default: secret)
  TARGET_PREFIX       Target prefix under KV mount (default: devops)
  SOURCE_SERVICES     Comma-separated source services (default: core-api,idp-api,spring-api)
  INFRA_KEYS          Comma-separated keys to move
  REMOVE_FROM_SOURCE  true|false (default: true)
  DRY_RUN             true|false (default: false)
EOF
}

log() {
  echo "[migrate-infra-secrets] $*"
}

fail() {
  echo "[migrate-infra-secrets] ERROR: $*" >&2
  exit 1
}

normalize_bool() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    true|1|yes|y) echo "true" ;;
    false|0|no|n|"") echo "false" ;;
    *) fail "Invalid boolean value: $1" ;;
  esac
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v vault >/dev/null 2>&1; then
  fail "vault CLI is required."
fi
if ! command -v jq >/dev/null 2>&1; then
  fail "jq is required."
fi
vault token lookup >/dev/null 2>&1 || fail "Not logged in. Run 'vault login' first."

REMOVE_FROM_SOURCE="$(normalize_bool "$REMOVE_FROM_SOURCE")"
DRY_RUN="$(normalize_bool "$DRY_RUN")"

TARGET_ENV="${1:-all}"
declare -a ENVS=()
case "$TARGET_ENV" in
  all) ENVS=("staging" "production" "development" "default") ;;
  staging|production|development|default) ENVS=("$TARGET_ENV") ;;
  *) fail "Invalid environment: $TARGET_ENV" ;;
esac

IFS=',' read -r -a SOURCES <<< "$SOURCE_SERVICES"
IFS=',' read -r -a KEYS <<< "$INFRA_KEYS"

if [[ ${#SOURCES[@]} -eq 0 ]]; then
  fail "SOURCE_SERVICES is empty."
fi
if [[ ${#KEYS[@]} -eq 0 ]]; then
  fail "INFRA_KEYS is empty."
fi

KEYS_JSON="$(printf '%s\n' "${KEYS[@]}" | jq -R . | jq -c -s .)"

extract_keys() {
  local json_data="$1"
  jq -c --argjson keys "$KEYS_JSON" '
    reduce $keys[] as $k ({}; if .[$k] != null then . + {($k): .[$k]} else . end)
  ' <<<"$json_data"
}

remove_keys() {
  local json_data="$1"
  jq -c --argjson keys "$KEYS_JSON" 'delpaths($keys | map([.]))' <<<"$json_data"
}

put_json() {
  local path="$1"
  local json_data="$2"
  local tmp_file
  tmp_file="$(mktemp)"
  echo "$json_data" >"$tmp_file"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY_RUN: vault kv put $path @${tmp_file}"
  else
    vault kv put "$path" @"$tmp_file" >/dev/null
  fi
  rm -f "$tmp_file"
}

for env in "${ENVS[@]}"; do
  log "Processing environment: $env"
  target_path="${KV_MOUNT}/${TARGET_PREFIX}/${env}"

  target_data='{}'
  if target_raw="$(vault kv get -format=json "$target_path" 2>/dev/null)"; then
    target_data="$(jq -c '.data.data // {}' <<<"$target_raw")"
  fi

  moved_any="false"
  for src in "${SOURCES[@]}"; do
    source_path="${KV_MOUNT}/${src}/${env}"
    if ! source_raw="$(vault kv get -format=json "$source_path" 2>/dev/null)"; then
      log "Skip source (not found): $source_path"
      continue
    fi

    source_data="$(jq -c '.data.data // {}' <<<"$source_raw")"
    extracted="$(extract_keys "$source_data")"
    if [[ "$extracted" == "{}" ]]; then
      log "No infra keys in source: $source_path"
      continue
    fi

    log "Move keys from $source_path -> $target_path: $(jq -r 'keys | join(",")' <<<"$extracted")"
    target_data="$(jq -c -s '.[0] * .[1]' <(echo "$target_data") <(echo "$extracted"))"
    moved_any="true"

    if [[ "$REMOVE_FROM_SOURCE" == "true" ]]; then
      source_clean="$(remove_keys "$source_data")"
      put_json "$source_path" "$source_clean"
      log "Removed moved keys from source: $source_path"
    fi
  done

  if [[ "$moved_any" == "true" ]]; then
    put_json "$target_path" "$target_data"
    log "Updated target: $target_path"
  else
    log "No keys moved for environment: $env"
  fi
done

log "Done."
