#!/bin/bash
set -euo pipefail

# OpenBao KV 경로 마이그레이션:
#   secret/server/{env} -> secret/core-api/{env}
#
# Usage:
#   ./scripts/openbao/migrate-server-to-core-api.sh [all|staging|production|default]
#
# Optional:
#   DELETE_OLD=true ./scripts/openbao/migrate-server-to-core-api.sh all

ENV_ARG="${1:-all}"
DELETE_OLD="${DELETE_OLD:-false}"
KV_MOUNT="${KV_MOUNT:-secret}"

case "$ENV_ARG" in
  all)
    ENVS=("staging" "production" "default")
    ;;
  staging|production|default)
    ENVS=("$ENV_ARG")
    ;;
  *)
    echo "❌ 잘못된 환경 인자: $ENV_ARG"
    echo "사용법: $0 [all|staging|production|default]"
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
echo "🔄 OpenBao 경로 마이그레이션"
echo "  from: ${KV_MOUNT}/server/{env}"
echo "  to:   ${KV_MOUNT}/core-api/{env}"
echo "  envs: ${ENVS[*]}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for env in "${ENVS[@]}"; do
  old_path="${KV_MOUNT}/server/${env}"
  new_path="${KV_MOUNT}/core-api/${env}"

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

  vault kv put "$new_path" @"$data_file" >/dev/null
  rm -f "$data_file"

  # 읽기 검증
  vault kv get "$new_path" >/dev/null
  echo "  ✅ 복사 완료: $old_path -> $new_path (keys: $key_count)"

  if [ "$DELETE_OLD" = "true" ]; then
    # 안전을 위해 명시적으로 활성화한 경우에만 삭제
    vault kv metadata delete "$old_path" >/dev/null
    echo "  🗑️  원본 삭제 완료: $old_path"
  fi
done

echo ""
echo "✅ 마이그레이션 완료"
echo "다음 확인 명령:"
echo "  vault kv get ${KV_MOUNT}/core-api/staging"
echo "  vault kv get ${KV_MOUNT}/core-api/production"
echo "  vault kv get ${KV_MOUNT}/core-api/default"
