#!/bin/bash
set -e

# OpenBao 시크릿 생성 헬퍼 스크립트
# ESC 정책에 맞춰 필요한 시크릿들을 생성합니다

OPENBAO_ADDR="${OPENBAO_ADDR:-http://localhost:8200}"
ENV="${1:-staging}"  # staging 또는 production

echo "🔐 OpenBao 시크릿 생성 시작..."
echo "OpenBao 주소: $OPENBAO_ADDR"
echo "환경: $ENV"

# 현재 인증 확인
echo ""
echo "📋 Step 1: 현재 인증 상태 확인"
vault token lookup > /dev/null 2>&1 || {
  echo "❌ OpenBao에 로그인되어 있지 않습니다."
  echo "다음 명령으로 로그인하세요:"
  echo "  export VAULT_ADDR=$OPENBAO_ADDR"
  echo "  vault login"
  exit 1
}

if [[ "$ENV" != "staging" && "$ENV" != "production" ]]; then
  echo "❌ 잘못된 환경입니다. staging 또는 production을 입력하세요."
  echo "사용법: $0 [staging|production]"
  exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 Step 2: 서버 환경 변수 시크릿 생성"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  실제 값으로 교체해야 하는 항목들:"
echo "  - AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
echo "  - SMTP_USERNAME, SMTP_PASSWORD"
echo "  - AUTH_JWT_SECRET"
echo "  - DATABASE_URL, DIRECT_URL"
echo ""
read -p "계속하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "취소되었습니다."
  exit 0
fi

# 서버 환경 변수 기본값 설정
if [[ "$ENV" == "staging" ]]; then
  FRONTEND_DOMAIN="https://staging.cocdev.co.kr"
  BACKEND_DOMAIN="https://api-staging.cocdev.co.kr"
  NODE_ENV="staging"
else
  FRONTEND_DOMAIN="https://app.cocdev.co.kr"
  BACKEND_DOMAIN="https://api.cocdev.co.kr"
  NODE_ENV="production"
fi

echo ""
echo "🔧 서버 시크릿 생성 중..."
vault kv put "secret/server/$ENV" \
  APP_PORT=3000 \
  APP_NAME=plate-api \
  APP_ADMIN_EMAIL="admin@cocdev.co.kr" \
  API_PREFIX=/api \
  APP_FALLBACK_LANGUAGE=ko \
  APP_HEADER_LANGUAGE=x-custom-lang \
  FRONTEND_DOMAIN="$FRONTEND_DOMAIN" \
  BACKEND_DOMAIN="$BACKEND_DOMAIN" \
  NODE_ENV="$NODE_ENV" \
  AWS_ACCESS_KEY_ID="CHANGE_ME_AWS_KEY" \
  AWS_SECRET_ACCESS_KEY="CHANGE_ME_AWS_SECRET" \
  AWS_REGION=ap-northeast-2 \
  AWS_S3_BUCKET_NAME="plate-$ENV" \
  SMTP_HOST=smtp.gmail.com \
  SMTP_PORT=587 \
  SMTP_USERNAME="CHANGE_ME_SMTP_USER" \
  SMTP_PASSWORD="CHANGE_ME_SMTP_PASS" \
  SMTP_SENDER="noreply@cocdev.co.kr" \
  AUTH_JWT_SECRET="CHANGE_ME_$(openssl rand -hex 32)" \
  AUTH_JWT_TOKEN_EXPIRES_IN=3600 \
  AUTH_JWT_TOKEN_REFRESH_IN=86400 \
  AUTH_JWT_SALT_ROUNDS=10 \
  CORS_ENABLED=true \
  DATABASE_URL="CHANGE_ME_postgresql://user:pass@host:5432/db" \
  DIRECT_URL="CHANGE_ME_postgresql://user:pass@host:5432/db"

echo "✅ 서버 시크릿 생성 완료: secret/server/$ENV"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🐳 Step 3: Harbor Registry 시크릿 생성"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Harbor Robot 계정 정보를 입력하세요:"
read -p "Harbor 사용자명 (예: robot\$plate-$ENV): " HARBOR_USERNAME
read -sp "Harbor 토큰/비밀번호: " HARBOR_PASSWORD
echo ""

# Docker config JSON 생성
HARBOR_AUTH=$(echo -n "$HARBOR_USERNAME:$HARBOR_PASSWORD" | base64)
DOCKER_CONFIG="{\"auths\":{\"harbor.cocdev.co.kr\":{\"username\":\"$HARBOR_USERNAME\",\"password\":\"$HARBOR_PASSWORD\",\"auth\":\"$HARBOR_AUTH\"}}}"

echo ""
echo "🔧 Harbor 시크릿 생성 중..."
vault kv put "secret/harbor/$ENV" \
  .dockerconfigjson="$DOCKER_CONFIG"

echo "✅ Harbor 시크릿 생성 완료: secret/harbor/$ENV"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 모든 시크릿 생성 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 생성된 시크릿 확인:"
echo "  vault kv get secret/server/$ENV"
echo "  vault kv get secret/harbor/$ENV"
echo ""
echo "⚠️  다음 항목들을 실제 값으로 업데이트하세요:"
echo ""
echo "# AWS 자격증명 업데이트"
echo "vault kv patch secret/server/$ENV \\"
echo "  AWS_ACCESS_KEY_ID=<실제_키> \\"
echo "  AWS_SECRET_ACCESS_KEY=<실제_시크릿>"
echo ""
echo "# SMTP 자격증명 업데이트"
echo "vault kv patch secret/server/$ENV \\"
echo "  SMTP_USERNAME=<실제_사용자명> \\"
echo "  SMTP_PASSWORD=<실제_비밀번호>"
echo ""
echo "# 데이터베이스 URL 업데이트"
echo "vault kv patch secret/server/$ENV \\"
echo "  DATABASE_URL=<실제_DB_URL> \\"
echo "  DIRECT_URL=<실제_DIRECT_URL>"
echo ""
echo "# JWT 시크릿 업데이트 (선택사항, 자동 생성됨)"
echo "vault kv patch secret/server/$ENV \\"
echo "  AUTH_JWT_SECRET=<실제_JWT_시크릿>"
