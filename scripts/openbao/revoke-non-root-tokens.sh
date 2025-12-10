#!/bin/bash
set -e

# Root 토큰을 제외한 모든 토큰 무효화 스크립트

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🗑️  Root 제외 모든 토큰 무효화"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. Root 권한 확인
echo "📋 Step 1: Root 권한 확인"
vault token lookup > /dev/null 2>&1 || {
  echo "❌ OpenBao에 로그인되어 있지 않습니다."
  echo "vault login 명령으로 먼저 로그인하세요."
  exit 1
}

CURRENT_POLICIES=$(vault token lookup | grep "^policies" | awk '{print $2}')

if ! echo "$CURRENT_POLICIES" | grep -q "root"; then
  echo "❌ Root 권한이 필요합니다."
  echo "현재 정책: $CURRENT_POLICIES"
  exit 1
fi

echo "✅ Root 권한 확인됨"
echo ""

# 2. 사용자 확인
echo "⚠️  경고: Root 토큰을 제외한 모든 토큰이 무효화됩니다!"
echo ""
read -p "계속하시겠습니까? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
  echo "취소되었습니다."
  exit 0
fi

# 3. 모든 토큰 Accessor 조회
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Step 2: 모든 토큰 조회 중..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ACCESSORS=$(vault list -format=json auth/token/accessors 2>/dev/null | jq -r '.[]')

if [ -z "$ACCESSORS" ]; then
  echo "⚠️  토큰을 찾을 수 없습니다."
  exit 0
fi

TOTAL=$(echo "$ACCESSORS" | wc -l | tr -d ' ')
echo "📊 총 $TOTAL 개의 토큰 발견"
echo ""

# 4. 토큰 무효화
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🗑️  Step 3: 토큰 무효화 중..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

REVOKED=0
SKIPPED=0
FAILED=0

for accessor in $ACCESSORS; do
  # Accessor로 토큰 정보 조회
  TOKEN_INFO=$(vault token lookup -accessor "$accessor" 2>/dev/null)

  if [ $? -ne 0 ]; then
    echo "⚠️  Accessor ${accessor:0:20}... 조회 실패 (이미 삭제됨)"
    ((FAILED++))
    continue
  fi

  # 토큰 정보 추출
  POLICIES=$(echo "$TOKEN_INFO" | grep "^policies" | awk '{print $2}')
  DISPLAY_NAME=$(echo "$TOKEN_INFO" | grep "^display_name" | awk '{$1=""; print $0}' | xargs)
  TTL=$(echo "$TOKEN_INFO" | grep "^ttl" | awk '{print $2}')
  CREATION_TIME=$(echo "$TOKEN_INFO" | grep "^creation_time" | awk '{$1=""; print $0}' | xargs)

  # Root 정책 포함 여부 확인
  if echo "$POLICIES" | grep -q "root"; then
    echo "⏭️  [SKIP] Root 토큰: $DISPLAY_NAME"
    ((SKIPPED++))
  else
    echo "🗑️  [DELETE] $DISPLAY_NAME"
    echo "    ├─ Policies: $POLICIES"
    echo "    ├─ TTL: $TTL"
    echo "    └─ Created: $CREATION_TIME"

    # 토큰 무효화
    if vault token revoke -accessor "$accessor" 2>/dev/null; then
      ((REVOKED++))
    else
      echo "    ❌ 무효화 실패"
      ((FAILED++))
    fi
  fi
  echo ""
done

# 5. 결과 요약
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 무효화 완료"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "총 토큰 수:        $TOTAL"
echo "무효화됨:          $REVOKED"
echo "건너뜀 (Root):     $SKIPPED"
echo "실패:              $FAILED"
echo ""

if [ $REVOKED -gt 0 ]; then
  echo "✅ $REVOKED 개의 토큰이 무효화되었습니다."
fi

if [ $SKIPPED -gt 0 ]; then
  echo "⏭️  $SKIPPED 개의 Root 토큰이 보존되었습니다."
fi

if [ $FAILED -gt 0 ]; then
  echo "⚠️  $FAILED 개의 토큰 처리에 실패했습니다."
fi
