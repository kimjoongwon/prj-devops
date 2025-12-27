#!/bin/bash
set -e

# ESC를 위한 OpenBao 정책 및 토큰 설정 스크립트

OPENBAO_ADDR="${OPENBAO_ADDR:-http://localhost:8200}"
POLICY_NAME="${POLICY_NAME:-esc-policy}"
TOKEN_TTL="${TOKEN_TTL:-720h}"  # 30일
TOKEN_PERIOD="${TOKEN_PERIOD:-24h}"  # 자동 갱신 주기

echo "🔐 OpenBao ESC 설정 시작..."
echo "OpenBao 주소: $OPENBAO_ADDR"
echo "정책 이름: $POLICY_NAME"

# 1. 현재 인증 확인
echo ""
echo "📋 Step 1: 현재 인증 상태 확인"
vault token lookup > /dev/null 2>&1 || {
  echo "❌ OpenBao에 로그인되어 있지 않습니다."
  echo "다음 명령으로 로그인하세요:"
  echo "  export VAULT_ADDR=$OPENBAO_ADDR"
  echo "  vault login"
  exit 1
}

# 2. 정책 생성
echo ""
echo "📝 Step 2: ESC 정책 생성"
POLICY_FILE="$(dirname "$0")/../policies/esc-policy.hcl"

if [ ! -f "$POLICY_FILE" ]; then
  echo "❌ 정책 파일을 찾을 수 없습니다: $POLICY_FILE"
  exit 1
fi

vault policy write "$POLICY_NAME" "$POLICY_FILE"
echo "✅ 정책 '$POLICY_NAME' 생성 완료"

# 3. 정책 확인
echo ""
echo "🔍 Step 3: 생성된 정책 확인"
vault policy read "$POLICY_NAME"

# 4. 토큰 생성
echo ""
echo "🎫 Step 4: ESC용 토큰 생성"
echo "토큰 설정:"
echo "  - TTL: $TOKEN_TTL"
echo "  - Period: $TOKEN_PERIOD (자동 갱신)"
echo "  - Renewable: true"

TOKEN_OUTPUT=$(vault token create \
  -policy="$POLICY_NAME" \
  -ttl="$TOKEN_TTL" \
  -period="$TOKEN_PERIOD" \
  -renewable=true \
  -display-name="esc-token" \
  -format=json)

TOKEN=$(echo "$TOKEN_OUTPUT" | jq -r '.auth.client_token')
TOKEN_ACCESSOR=$(echo "$TOKEN_OUTPUT" | jq -r '.auth.accessor')

echo "✅ 토큰 생성 완료"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📌 ESC 토큰 정보"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Token:          $TOKEN"
echo "Accessor:       $TOKEN_ACCESSOR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  이 토큰을 안전한 곳에 저장하세요!"
echo ""

# 5. 토큰 상세 정보
echo "📊 Step 5: 토큰 상세 정보"
vault token lookup "$TOKEN"

# 6. Kubernetes Secret 생성 명령 출력
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Kubernetes에 적용할 명령어"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Staging 환경"
echo "kubectl create secret generic openbao-token \\"
echo "  --from-literal=token=$TOKEN \\"
echo "  --namespace=external-secrets-stg \\"
echo "  --dry-run=client -o yaml | kubectl apply -f -"
echo ""
echo "# Production 환경"
echo "kubectl create secret generic openbao-token \\"
echo "  --from-literal=token=$TOKEN \\"
echo "  --namespace=external-secrets-prod \\"
echo "  --dry-run=client -o yaml | kubectl apply -f -"
echo ""

# 7. 토큰 테스트
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 Step 6: 토큰 권한 테스트"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 서버 시크릿 테스트
VAULT_TOKEN="$TOKEN" vault kv get secret/server/staging 2>/dev/null && \
  echo "✅ secret/server/staging 경로 접근 성공" || \
  echo "⚠️  secret/server/staging 경로가 없거나 접근 불가"

VAULT_TOKEN="$TOKEN" vault kv get secret/server/production 2>/dev/null && \
  echo "✅ secret/server/production 경로 접근 성공" || \
  echo "⚠️  secret/server/production 경로가 없거나 접근 불가"

# Harbor 시크릿 테스트
VAULT_TOKEN="$TOKEN" vault kv get secret/harbor/staging 2>/dev/null && \
  echo "✅ secret/harbor/staging 경로 접근 성공" || \
  echo "⚠️  secret/harbor/staging 경로가 없거나 접근 불가"

VAULT_TOKEN="$TOKEN" vault kv get secret/harbor/production 2>/dev/null && \
  echo "✅ secret/harbor/production 경로 접근 성공" || \
  echo "⚠️  secret/harbor/production 경로가 없거나 접근 불가"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 다음 단계: OpenBao에 시크릿 생성"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "위 테스트에서 경로가 없다는 메시지가 나왔다면, 시크릿을 먼저 생성해야 합니다:"
echo ""
echo "# Staging 서버 시크릿 생성"
echo "vault kv put secret/server/staging \\"
echo "  APP_PORT=3000 \\"
echo "  APP_NAME=plate-server \\"
echo "  NODE_ENV=staging"
echo ""
echo "# Production 서버 시크릿 생성"
echo "vault kv put secret/server/production \\"
echo "  APP_PORT=3000 \\"
echo "  APP_NAME=plate-server \\"
echo "  NODE_ENV=production"
echo ""
echo "# Staging Harbor 시크릿 생성"
echo "vault kv put secret/harbor/staging \\"
echo "  .dockerconfigjson='{\"auths\":{\"harbor.example.com\":{\"username\":\"user\",\"password\":\"pass\"}}}'"
echo ""
echo "# Production Harbor 시크릿 생성"
echo "vault kv put secret/harbor/production \\"
echo "  .dockerconfigjson='{\"auths\":{\"harbor.example.com\":{\"username\":\"user\",\"password\":\"pass\"}}}'"
echo ""
echo "✅ ESC 설정 완료!"
