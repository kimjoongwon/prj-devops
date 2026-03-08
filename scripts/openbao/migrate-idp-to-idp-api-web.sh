#!/bin/bash
set -euo pipefail

# OpenBao KV 경로 마이그레이션:
#   secret/idp/{env} -> secret/idp-api/{env}, secret/idp-web/{env}
#
# Usage:
#   ./scripts/openbao/migrate-idp-to-idp-api-web.sh [all|staging|production|development|default]
#
# Optional:
#   DELETE_OLD=true ./scripts/openbao/migrate-idp-to-idp-api-web.sh all

ENV_ARG="${1:-all}"
DELETE_OLD="${DELETE_OLD:-false}"
KV_MOUNT="${KV_MOUNT:-secret}"

case "$ENV_ARG" in
  all)
    ENVS=("staging" "production" "development" "default")
    ;;
  staging|production|development|default)
    ENVS=("$ENV_ARG")
    ;;
  *)
    echo "❌ 잘못된 환경 인자: $ENV_ARG"
    echo "사용법: $0 [all|staging|production|development|default]"
    exit 1
    ;;
esac

if ! command -v vault >/dev/null 2>&1; then
  echo "❌ vault CLI가 필요합니다."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq가 필요합니다."
  exit 1
fi

vault token lookup >/dev/null 2>&1 || {
  echo "❌ OpenBao 로그인 상태가 아닙니다. vault login 먼저 실행하세요."
  exit 1
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔄 OpenBao IDP 경로 마이그레이션"
echo "  from: ${KV_MOUNT}/idp/{env}"
echo "  to:   ${KV_MOUNT}/idp-api/{env}, ${KV_MOUNT}/idp-web/{env}"
echo "  envs: ${ENVS[*]}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for env in "${ENVS[@]}"; do
  old_path="${KV_MOUNT}/idp/${env}"
  api_path="${KV_MOUNT}/idp-api/${env}"
  web_path="${KV_MOUNT}/idp-web/${env}"

  echo ""
  echo "▶ ${env}"
  if ! old_json="$(vault kv get -format=json "$old_path" 2>/dev/null)"; then
    echo "  ⚠️  원본 경로 없음: $old_path (건너뜀)"
    continue
  fi

  data_file="$(mktemp)"
  echo "$old_json" | jq '.data.data' > "$data_file"

  key_count="$(jq 'keys | length' "$data_file")"
  if [ "$key_count" -eq 0 ]; then
    echo "  ⚠️  원본 데이터가 비어 있음: $old_path"
  fi

  vault kv put "$api_path" @"$data_file" >/dev/null
  vault kv put "$web_path" @"$data_file" >/dev/null
  rm -f "$data_file"

  vault kv get "$api_path" >/dev/null
  vault kv get "$web_path" >/dev/null
  echo "  ✅ 복사 완료: $old_path -> $api_path, $web_path (keys: $key_count)"

  if [ "$DELETE_OLD" = "true" ]; then
    vault kv metadata delete "$old_path" >/dev/null
    echo "  🗑️  원본 삭제 완료: $old_path"
  fi
done

echo ""
echo "✅ 마이그레이션 완료"
echo "다음 확인 명령:"
echo "  vault kv get ${KV_MOUNT}/idp-api/production"
echo "  vault kv get ${KV_MOUNT}/idp-web/production"
