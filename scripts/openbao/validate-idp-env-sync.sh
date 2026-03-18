#!/bin/bash
set -euo pipefail

# IDP API 환경변수 동기화 점검 스크립트
# - prj-core/apps/idp/api/.env.example
# - OpenBao secret/idp-api/<env> 키 목록을 비교합니다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRJ_DEVOPS_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_PRJ_CORE_ROOT="$(cd "${PRJ_DEVOPS_ROOT}/.." && pwd)/prj-core"

ENVIRONMENT="${1:-production}"
PRJ_CORE_ROOT="${2:-$DEFAULT_PRJ_CORE_ROOT}"
ENV_FILE="${PRJ_CORE_ROOT}/apps/idp/api/.env.example"
OPENBAO_PATH="secret/idp-api/${ENVIRONMENT}"
COMPONENT_NAME="IDP API"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
  log_error "환경 값이 올바르지 않습니다: $ENVIRONMENT"
  echo "사용법: $0 [staging|production] [prj-core 경로(선택)]"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  log_error "${COMPONENT_NAME} env 예시 파일을 찾을 수 없습니다: $ENV_FILE"
  exit 1
fi

if ! command -v vault >/dev/null 2>&1; then
  log_error "vault CLI가 필요합니다."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  log_error "jq가 필요합니다."
  exit 1
fi

if ! vault token lookup >/dev/null 2>&1; then
  log_error "OpenBao에 로그인되어 있지 않습니다. 'vault login' 후 다시 실행하세요."
  exit 1
fi

tmp_expected="$(mktemp)"
tmp_actual="$(mktemp)"
trap 'rm -f "$tmp_expected" "$tmp_actual"' EXIT

# .env.example 키 추출
awk -F= '/^[A-Z0-9_]+=.*/ {print $1}' "$ENV_FILE" | sort -u > "$tmp_expected"

# OpenBao 키 추출 (값은 조회하지 않음)
vault kv get -format=json "$OPENBAO_PATH" \
  | jq -r '.data.data | keys[]' \
  | sort -u > "$tmp_actual"

missing_in_vault="$(comm -23 "$tmp_expected" "$tmp_actual" || true)"
extra_in_vault="$(comm -13 "$tmp_expected" "$tmp_actual" || true)"

log_info "동기화 점검 대상"
echo "  - ENV 파일: $ENV_FILE"
echo "  - OpenBao:  $OPENBAO_PATH"
echo

if [[ -n "$missing_in_vault" ]]; then
  log_error "OpenBao에 없는 키 (.env.example 대비):"
  echo "$missing_in_vault" | sed 's/^/  - /'
  echo
else
  log_info "필수 키 누락 없음"
fi

if [[ -n "$extra_in_vault" ]]; then
  log_warn "OpenBao에만 있는 추가 키 (필요시 유지 가능):"
  echo "$extra_in_vault" | sed 's/^/  - /'
  echo
else
  log_info "추가 키 없음"
fi

if [[ -n "$missing_in_vault" ]]; then
  log_error "${COMPONENT_NAME} 환경변수 동기화 실패"
  echo "누락 키는 다음처럼 반영하세요:"
  echo "  vault kv patch ${OPENBAO_PATH} KEY=value ..."
  exit 1
fi

log_info "${COMPONENT_NAME} 환경변수 동기화 통과"
