#!/bin/bash
set -euo pipefail

OPENBAO_ADDR="${OPENBAO_ADDR:-https://openbao.cocdev.co.kr}"
ENVIRONMENT="${1:-staging}"
MODE="${2:-apply}"

usage() {
  cat <<'EOF'
Usage: ./scripts/openbao/patch-idp-endpoints.sh [staging|production] [apply|dry-run]

Examples:
  ./scripts/openbao/patch-idp-endpoints.sh staging dry-run
  ./scripts/openbao/patch-idp-endpoints.sh production apply

Environment variables:
  OPENBAO_ADDR   OpenBao address (default: https://openbao.cocdev.co.kr)
  VAULT_TOKEN    OpenBao token for HTTP API mode
EOF
}

if [[ "${ENVIRONMENT}" != "staging" && "${ENVIRONMENT}" != "production" ]]; then
  echo "❌ invalid environment: ${ENVIRONMENT}" >&2
  usage
  exit 1
fi

if [[ "${MODE}" != "apply" && "${MODE}" != "dry-run" ]]; then
  echo "❌ invalid mode: ${MODE}" >&2
  usage
  exit 1
fi

if [[ "${ENVIRONMENT}" == "staging" ]]; then
  APP_HOST="stg.cocdev.co.kr"
  IDP_HOST="idp-stg.cocdev.co.kr"
  CORE_API_INTERNAL_URL="http://core-api-stg:3006"
  IDP_API_INTERNAL_URL="http://idp-api-stg"
else
  APP_HOST="cocdev.co.kr"
  IDP_HOST="idp.cocdev.co.kr"
  CORE_API_INTERNAL_URL="http://core-api-prod:3006"
  IDP_API_INTERNAL_URL="http://idp-api-prod"
fi

CORE_API_PATH="secret/core-api/${ENVIRONMENT}"
IDP_API_PATH="secret/idp-api/${ENVIRONMENT}"
IDP_WEB_PATH="secret/idp-web/${ENVIRONMENT}"
IDP_ORIGIN="https://${IDP_HOST}"
ADMIN_BASE_URL="https://${APP_HOST}"
JWKS_URL="${IDP_ORIGIN}/oidc/jwks"

secret_value() {
  local path="$1"
  local key="$2"
  local body

  if [[ -z "${VAULT_TOKEN:-}" ]]; then
    return 0
  fi

  body="$(http_get_secret "${path}")"
  if [[ -z "${body}" ]]; then
    return 0
  fi

  ruby -rjson -e '
    body = JSON.parse(STDIN.read)
    data = body.dig("data", "data") || {}
    value = data[ARGV[0]]
    print(value) unless value.nil?
  ' "${key}" <<< "${body}"
}

print_action() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

run_vault() {
  if [[ "${MODE}" == "dry-run" ]]; then
    print_action "$@"
    return 0
  fi

  "$@"
}

http_get_secret() {
  local path="$1"
  local mount_path="${path%%/*}"
  local secret_path="${path#*/}"
  local response_file
  local http_status

  response_file="$(mktemp)"
  http_status="$(curl -sS -o "${response_file}" -w '%{http_code}' \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    "${OPENBAO_ADDR}/v1/${mount_path}/data/${secret_path}")"

  case "${http_status}" in
    200)
      cat "${response_file}"
      ;;
    404)
      ;;
    *)
      cat "${response_file}" >&2
      rm -f "${response_file}"
      return 1
      ;;
  esac

  rm -f "${response_file}"
}

http_upsert_secret() {
  local path="$1"
  shift

  local mount_path="${path%%/*}"
  local secret_path="${path#*/}"
  local existing_body
  local payload
  local response_file
  local http_status

  existing_body="$(http_get_secret "${path}")"
  payload="$(
    ruby -rjson -e '
      body = STDIN.read
      data =
        begin
          body.empty? ? {} : (JSON.parse(body).dig("data", "data") || {})
        rescue JSON::ParserError
          {}
        end

      ARGV.each_slice(2) do |key, value|
        data[key] = value
      end

      puts JSON.generate({ data: data })
    ' "$@" <<< "${existing_body}"
  )"

  if [[ "${MODE}" == "dry-run" ]]; then
    print_action curl -X POST "${OPENBAO_ADDR}/v1/${mount_path}/data/${secret_path}" "<merged-payload>"
    while [[ "$#" -gt 0 ]]; do
      printf '%s=%q\n' "$1" "$2"
      shift 2
    done
    return 0
  fi

  response_file="$(mktemp)"
  http_status="$(curl -sS -o "${response_file}" -w '%{http_code}' \
    -X POST \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "${payload}" \
    "${OPENBAO_ADDR}/v1/${mount_path}/data/${secret_path}")"

  if [[ "${http_status}" != "200" && "${http_status}" != "204" ]]; then
    cat "${response_file}" >&2
    rm -f "${response_file}"
    return 1
  fi

  rm -f "${response_file}"
}

http_replace_secret_data() {
  local path="$1"
  local data_json="$2"
  local mount_path="${path%%/*}"
  local secret_path="${path#*/}"
  local payload
  local response_file
  local http_status

  payload="$(
    ruby -rjson -e '
      data =
        begin
          JSON.parse(ARGV[0])
        rescue JSON::ParserError
          {}
        end

      puts JSON.generate({ data: data })
    ' "${data_json}"
  )"

  response_file="$(mktemp)"
  http_status="$(curl -sS -o "${response_file}" -w '%{http_code}' \
    -X POST \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "${payload}" \
    "${OPENBAO_ADDR}/v1/${mount_path}/data/${secret_path}")"

  if [[ "${http_status}" != "200" && "${http_status}" != "204" ]]; then
    cat "${response_file}" >&2
    rm -f "${response_file}"
    return 1
  fi

  rm -f "${response_file}"
}

secret_data_json() {
  local path="$1"

  if [[ -n "${VAULT_TOKEN:-}" ]]; then
    local body
    body="$(http_get_secret "${path}")"
    if [[ -z "${body}" ]]; then
      return 0
    fi

    ruby -rjson -e '
      body = JSON.parse(STDIN.read)
      data = body.dig("data", "data") || {}
      puts JSON.generate(data)
    ' <<< "${body}"
    return 0
  fi

  if ! command -v vault >/dev/null 2>&1; then
    echo "❌ vault CLI not found. Set VAULT_TOKEN for HTTP API mode." >&2
    exit 1
  fi

  local body
  if ! body="$(vault kv get -format=json "${path}" 2>/dev/null)"; then
    return 0
  fi

  ruby -rjson -e '
    body = JSON.parse(STDIN.read)
    data = body.dig("data", "data") || {}
    puts JSON.generate(data)
  ' <<< "${body}"
}

upsert_secret() {
  local path="$1"
  shift

  if [[ -n "${VAULT_TOKEN:-}" ]]; then
    http_upsert_secret "${path}" "$@"
    return 0
  fi

  if [[ "${MODE}" == "dry-run" ]]; then
    print_action vault kv patch "${path}" "$@"
    return 0
  fi

  if ! command -v vault >/dev/null 2>&1; then
    echo "❌ vault CLI not found. Set VAULT_TOKEN for HTTP API mode." >&2
    exit 1
  fi

  if [[ "${MODE}" == "apply" ]]; then
    export VAULT_ADDR="${OPENBAO_ADDR}"
    vault token lookup >/dev/null
  fi

  run_vault vault kv patch "${path}" "$@"
}

remove_secret_keys() {
  local path="$1"
  shift

  if [[ "$#" -eq 0 ]]; then
    return 0
  fi

  if [[ "${MODE}" == "dry-run" ]]; then
    print_action remove_openbao_keys "${path}" "$@"
    return 0
  fi

  local current_json
  current_json="$(secret_data_json "${path}")"
  if [[ -z "${current_json}" ]]; then
    return 0
  fi

  local cleaned_json
  cleaned_json="$(
    ruby -rjson -e '
      data =
        begin
          JSON.parse(STDIN.read)
        rescue JSON::ParserError
          {}
        end

      ARGV.each do |key|
        data.delete(key)
      end

      puts JSON.generate(data)
    ' "$@" <<< "${current_json}"
  )"

  if [[ -n "${VAULT_TOKEN:-}" ]]; then
    http_replace_secret_data "${path}" "${cleaned_json}"
    return 0
  fi

  local data_file
  data_file="$(mktemp)"
  printf '%s\n' "${cleaned_json}" > "${data_file}"
  vault kv put "${path}" @"${data_file}" >/dev/null
  rm -f "${data_file}"
}

echo "🔧 environment: ${ENVIRONMENT}"
echo "🔧 idp origin : ${IDP_ORIGIN}"
echo "🔧 admin base : ${ADMIN_BASE_URL}"
echo ""

CURRENT_OIDC_ADMIN_CLIENT_ID="${OIDC_ADMIN_CLIENT_ID:-$(secret_value "${IDP_API_PATH}" "OIDC_ADMIN_CLIENT_ID")}"
CURRENT_OIDC_ADMIN_CLIENT_ID="${CURRENT_OIDC_ADMIN_CLIENT_ID:-admin-web}"

CURRENT_OIDC_ADMIN_CLIENT_SECRET="${OIDC_ADMIN_CLIENT_SECRET:-$(secret_value "${IDP_API_PATH}" "OIDC_ADMIN_CLIENT_SECRET")}"
CURRENT_OIDC_ADMIN_CLIENT_SECRET="${CURRENT_OIDC_ADMIN_CLIENT_SECRET:-admin-secret-change-in-production}"

CURRENT_OIDC_IDP_WEB_CLIENT_ID="${OIDC_IDP_WEB_CLIENT_ID:-$(secret_value "${IDP_API_PATH}" "OIDC_IDP_WEB_CLIENT_ID")}"
CURRENT_OIDC_IDP_WEB_CLIENT_ID="${CURRENT_OIDC_IDP_WEB_CLIENT_ID:-idp-web}"

CURRENT_OIDC_IDP_WEB_REDIRECT_URI="${OIDC_IDP_WEB_REDIRECT_URI:-$(secret_value "${IDP_API_PATH}" "OIDC_IDP_WEB_REDIRECT_URI")}"
CURRENT_OIDC_IDP_WEB_REDIRECT_URI="${CURRENT_OIDC_IDP_WEB_REDIRECT_URI:-${IDP_ORIGIN}/api/v1/auth/callback}"

CURRENT_OIDC_IDP_WEB_CLIENT_SECRET="${OIDC_IDP_WEB_CLIENT_SECRET:-$(secret_value "${IDP_API_PATH}" "OIDC_IDP_WEB_CLIENT_SECRET")}"
CURRENT_OIDC_IDP_WEB_CLIENT_SECRET="${CURRENT_OIDC_IDP_WEB_CLIENT_SECRET:-idp-web-secret-change-in-production}"

upsert_secret "${CORE_API_PATH}" \
  CORE_API_INTERNAL_URL "${CORE_API_INTERNAL_URL}" \
  IDP_API_INTERNAL_URL "${IDP_API_INTERNAL_URL}" \
  OIDC_ISSUER "${IDP_ORIGIN}" \
  OIDC_JWKS_URI "${JWKS_URL}" \
  OIDC_ADMIN_BASE_URL "${ADMIN_BASE_URL}" \
  OIDC_ADMIN_CLIENT_ID "${CURRENT_OIDC_ADMIN_CLIENT_ID}" \
  OIDC_ADMIN_CLIENT_SECRET "${CURRENT_OIDC_ADMIN_CLIENT_SECRET}" \
  IDP_CLIENT_URL "${IDP_ORIGIN}"

upsert_secret "${IDP_API_PATH}" \
  APP_NAME "idp" \
  APP_PORT "3007" \
  NODE_ENV "${ENVIRONMENT}" \
  FRONTEND_DOMAIN "${IDP_ORIGIN}" \
  BACKEND_DOMAIN "${IDP_ORIGIN}" \
  OIDC_ISSUER "${IDP_ORIGIN}" \
  IDP_CLIENT_URL "${IDP_ORIGIN}" \
  OIDC_ADMIN_BASE_URL "${ADMIN_BASE_URL}" \
  OIDC_ADMIN_CLIENT_ID "${CURRENT_OIDC_ADMIN_CLIENT_ID}" \
  OIDC_ADMIN_CLIENT_SECRET "${CURRENT_OIDC_ADMIN_CLIENT_SECRET}" \
  OIDC_JWKS_URI "${JWKS_URL}" \
  OIDC_IDP_WEB_CLIENT_ID "${CURRENT_OIDC_IDP_WEB_CLIENT_ID}" \
  OIDC_IDP_WEB_CLIENT_SECRET "${CURRENT_OIDC_IDP_WEB_CLIENT_SECRET}" \
  OIDC_IDP_WEB_REDIRECT_URI "${CURRENT_OIDC_IDP_WEB_REDIRECT_URI}"

upsert_secret "${IDP_WEB_PATH}" \
  APP_NAME "idp-web" \
  APP_PORT "3008" \
  NODE_ENV "${ENVIRONMENT}" \
  IDP_API_INTERNAL_URL "${IDP_API_INTERNAL_URL}"

remove_secret_keys "${CORE_API_PATH}" \
  OIDC_CLIENT_ID \
  OIDC_CLIENT_SECRET \
  OIDC_REDIRECT_URI \
  STORYBOOK_URL

remove_secret_keys "${IDP_API_PATH}" \
  OIDC_CLIENT_ID \
  OIDC_CLIENT_SECRET \
  OIDC_REDIRECT_URI \
  STORYBOOK_URL \
  OIDC_IDP_CONSOLE_CLIENT_ID \
  OIDC_IDP_CONSOLE_CLIENT_SECRET \
  OIDC_IDP_CONSOLE_REDIRECT_URI

echo ""
if [[ "${MODE}" == "dry-run" ]]; then
  echo "✅ dry-run complete"
else
  echo "✅ OpenBao patch complete"
fi
