#!/bin/bash
set -e

# OpenBao 시크릿 생성 헬퍼 스크립트
# ESC 정책에 맞춰 필요한 시크릿들을 생성합니다

OPENBAO_ADDR="${OPENBAO_ADDR:-http://localhost:8200}"
ENV="${1:-staging}"  # staging 또는 production
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRJ_DEVOPS_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROJECTS_DIR="$(cd "${PRJ_DEVOPS_DIR}/.." && pwd)"
PRJ_CORE_DIR="${PRJ_CORE_DIR:-${PROJECTS_DIR}/prj-core}"

generate_oidc_jwks_keys() {
  local generator="${PRJ_CORE_DIR}/apps/idp/api/scripts/generate-jwks.mjs"
  local generated

  if [[ ! -f "${generator}" ]]; then
    echo "❌ OIDC JWKS 생성 스크립트를 찾을 수 없습니다: ${generator}" >&2
    exit 1
  fi

  generated="$(node "${generator}" | sed -n "s/^OIDC_JWKS_KEYS='\\(.*\\)'$/\\1/p")"
  if [[ -z "${generated}" ]]; then
    echo "❌ OIDC_JWKS_KEYS 생성에 실패했습니다." >&2
    exit 1
  fi

  printf '%s' "${generated}"
}

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
echo "  - OBJECT_STORAGE_ACCESS_KEY, OBJECT_STORAGE_SECRET_KEY"
echo "  - OBJECT_STORAGE_PROVIDER, OBJECT_STORAGE_ENDPOINT, OBJECT_STORAGE_API_TOKEN"
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
  FRONTEND_DOMAIN="https://stg.cocdev.co.kr"
  BACKEND_DOMAIN="https://stg.cocdev.co.kr"
  IDP_DOMAIN="https://idp-stg.cocdev.co.kr"
  ADMIN_BASE_URL="https://stg.cocdev.co.kr"
  STORYBOOK_BASE_URL="https://stg.cocdev.co.kr/story"
  NODE_ENV="staging"
else
  FRONTEND_DOMAIN="https://cocdev.co.kr"
  BACKEND_DOMAIN="https://cocdev.co.kr"
  IDP_DOMAIN="https://idp.cocdev.co.kr"
  ADMIN_BASE_URL="https://cocdev.co.kr"
  STORYBOOK_BASE_URL="https://cocdev.co.kr/story"
  NODE_ENV="production"
fi

OIDC_ADMIN_CLIENT_ID="${OIDC_ADMIN_CLIENT_ID:-admin-web}"
OIDC_ADMIN_CLIENT_SECRET="${OIDC_ADMIN_CLIENT_SECRET:-CHANGE_ME_$(openssl rand -hex 24)}"
OIDC_STORYBOOK_CLIENT_ID="${OIDC_STORYBOOK_CLIENT_ID:-storybook}"
OIDC_STORYBOOK_CLIENT_SECRET="${OIDC_STORYBOOK_CLIENT_SECRET:-CHANGE_ME_$(openssl rand -hex 24)}"
OIDC_IDP_WEB_CLIENT_ID="${OIDC_IDP_WEB_CLIENT_ID:-idp-web}"
OIDC_IDP_WEB_CLIENT_SECRET="${OIDC_IDP_WEB_CLIENT_SECRET:-CHANGE_ME_$(openssl rand -hex 24)}"
OIDC_JWKS_KEYS="${OIDC_JWKS_KEYS:-$(generate_oidc_jwks_keys)}"

echo ""
echo "🔧 인프라 공통 시크릿 생성 중..."
vault kv put "secret/devops/$ENV" \
  OBJECT_STORAGE_ACCESS_KEY="CHANGE_ME_OBJECT_STORAGE_ACCESS_KEY" \
  OBJECT_STORAGE_SECRET_KEY="CHANGE_ME_OBJECT_STORAGE_SECRET_KEY" \
  OBJECT_STORAGE_PROVIDER="CHANGE_ME_OBJECT_STORAGE_PROVIDER" \
  OBJECT_STORAGE_REGION="CHANGE_ME_OBJECT_STORAGE_REGION" \
  OBJECT_STORAGE_BUCKET="plate" \
  OBJECT_STORAGE_ENDPOINT="CHANGE_ME_OBJECT_STORAGE_ENDPOINT" \
  OBJECT_STORAGE_API_TOKEN="CHANGE_ME_OBJECT_STORAGE_API_TOKEN"

echo "✅ 인프라 공통 시크릿 생성 완료: secret/devops/$ENV"

echo ""
echo "🔧 서버 시크릿 생성 중..."
if [[ "$ENV" == "staging" ]]; then
  CORE_API_INTERNAL_URL="http://core-api-stg:3006"
  IDP_API_INTERNAL_URL="http://idp-api-stg"
else
  CORE_API_INTERNAL_URL="http://core-api-prod:3006"
  IDP_API_INTERNAL_URL="http://idp-api-prod"
fi

vault kv put "secret/core-api/$ENV" \
  APP_PORT=3000 \
  APP_NAME=core-api \
  APP_ADMIN_EMAIL="admin@cocdev.co.kr" \
  API_PREFIX=/api \
  APP_FALLBACK_LANGUAGE=ko \
  APP_HEADER_LANGUAGE=x-custom-lang \
  FRONTEND_DOMAIN="$FRONTEND_DOMAIN" \
  BACKEND_DOMAIN="$BACKEND_DOMAIN" \
  NODE_ENV="$NODE_ENV" \
  SMTP_HOST=smtp.gmail.com \
  SMTP_PORT=587 \
  SMTP_SECURE=false \
  SMTP_USERNAME="CHANGE_ME_SMTP_USER" \
  SMTP_PASSWORD="CHANGE_ME_SMTP_PASS" \
  SMTP_SENDER="noreply@cocdev.co.kr" \
  AUTH_JWT_SECRET="CHANGE_ME_$(openssl rand -hex 32)" \
  AUTH_JWT_TOKEN_EXPIRES_IN=3600 \
  AUTH_JWT_TOKEN_REFRESH_IN=86400 \
  AUTH_JWT_SALT_ROUNDS=10 \
  CORS_ENABLED=true \
  OTEL_EXPORTER_OTLP_ENDPOINT="http://otel-collector.grafana.svc.cluster.local:4317" \
  OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
  OTEL_TRACES_SAMPLER=traceidratio \
  OTEL_TRACES_SAMPLER_ARG=0.1 \
  OTEL_PROPAGATORS="tracecontext,baggage" \
  OTEL_METRICS_EXPORTER=none \
  OTEL_LOGS_EXPORTER=none \
  CORE_API_INTERNAL_URL="$CORE_API_INTERNAL_URL" \
  IDP_API_INTERNAL_URL="$IDP_API_INTERNAL_URL" \
  OIDC_ISSUER="$IDP_DOMAIN" \
  OIDC_JWKS_URI="$IDP_DOMAIN/oidc/jwks" \
  OIDC_ADMIN_BASE_URL="$ADMIN_BASE_URL" \
  OIDC_ADMIN_CLIENT_ID="$OIDC_ADMIN_CLIENT_ID" \
  OIDC_ADMIN_CLIENT_SECRET="$OIDC_ADMIN_CLIENT_SECRET" \
  IDP_CLIENT_URL="$IDP_DOMAIN" \
  DATABASE_URL="CHANGE_ME_postgresql://user:pass@host:5432/db" \
  DIRECT_URL="CHANGE_ME_postgresql://user:pass@host:5432/db"

echo "✅ 서버 시크릿 생성 완료: secret/core-api/$ENV"

echo ""
echo "🔧 IDP API 시크릿 생성 중..."
vault kv put "secret/idp-api/$ENV" \
  APP_NAME=idp \
  APP_PORT=3007 \
  NODE_ENV="$NODE_ENV" \
  APP_ADMIN_EMAIL="admin@cocdev.co.kr" \
  API_PREFIX=api \
  APP_FALLBACK_LANGUAGE=ko \
  APP_HEADER_LANGUAGE=x-custom-lang \
  FRONTEND_DOMAIN="$IDP_DOMAIN" \
  BACKEND_DOMAIN="$IDP_DOMAIN" \
  DATABASE_URL="CHANGE_ME_postgresql://user:pass@host:5432/db" \
  DIRECT_URL="CHANGE_ME_postgresql://user:pass@host:5432/db" \
  REDIS_HOST="CHANGE_ME_REDIS_HOST" \
  REDIS_PORT=6379 \
  REDIS_PASSWORD="CHANGE_ME_REDIS_PASSWORD" \
  CORS_ENABLED=true \
  SMTP_HOST=smtp.gmail.com \
  SMTP_PORT=587 \
  SMTP_SECURE=false \
  SMTP_USERNAME="CHANGE_ME_SMTP_USER" \
  SMTP_PASSWORD="CHANGE_ME_SMTP_PASS" \
  SMTP_SENDER="noreply@cocdev.co.kr" \
  AUTH_JWT_SECRET="CHANGE_ME_$(openssl rand -hex 32)" \
  AUTH_JWT_TOKEN_EXPIRES_IN=1h \
  AUTH_JWT_TOKEN_REFRESH_IN=7d \
  AUTH_JWT_SALT_ROUNDS=10 \
  OIDC_ISSUER="$IDP_DOMAIN" \
  OIDC_COOKIE_SECRET="CHANGE_ME_$(openssl rand -hex 32)" \
  OIDC_ADMIN_BASE_URL="$ADMIN_BASE_URL" \
  OIDC_STORYBOOK_BASE_URL="$STORYBOOK_BASE_URL" \
  OIDC_ADMIN_CLIENT_ID="$OIDC_ADMIN_CLIENT_ID" \
  OIDC_ADMIN_CLIENT_SECRET="$OIDC_ADMIN_CLIENT_SECRET" \
  OIDC_STORYBOOK_CLIENT_ID="$OIDC_STORYBOOK_CLIENT_ID" \
  OIDC_STORYBOOK_CLIENT_SECRET="$OIDC_STORYBOOK_CLIENT_SECRET" \
  OIDC_IDP_WEB_CLIENT_ID="$OIDC_IDP_WEB_CLIENT_ID" \
  OIDC_IDP_WEB_CLIENT_SECRET="$OIDC_IDP_WEB_CLIENT_SECRET" \
  OIDC_IDP_WEB_REDIRECT_URI="$IDP_DOMAIN/api/v1/auth/callback" \
  OIDC_JWKS_URI="$IDP_DOMAIN/oidc/jwks" \
  OIDC_JWKS_KEYS="$OIDC_JWKS_KEYS" \
  IDP_CLIENT_URL="$IDP_DOMAIN"

echo "✅ IDP API 시크릿 생성 완료: secret/idp-api/$ENV"

echo ""
echo "🔧 IDP Web 시크릿 생성 중..."
vault kv put "secret/idp-web/$ENV" \
  APP_NAME=idp-web \
  APP_PORT=3008 \
  NODE_ENV="$NODE_ENV" \
  IDP_API_INTERNAL_URL="$IDP_API_INTERNAL_URL"

echo "✅ IDP Web 시크릿 생성 완료: secret/idp-web/$ENV"

echo ""
echo "🔧 pgAdmin 시크릿 생성 중..."
vault kv put "secret/pgadmin/$ENV" \
  PGADMIN_EMAIL="admin@plate.com" \
  PGADMIN_PASSWORD="CHANGE_ME_PGADMIN_PASSWORD"

echo "✅ pgAdmin 시크릿 생성 완료: secret/pgadmin/$ENV"

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
  registry="harbor.cocdev.co.kr" \
  username="$HARBOR_USERNAME" \
  password="$HARBOR_PASSWORD" \
  .dockerconfigjson="$DOCKER_CONFIG"

echo "✅ Harbor 시크릿 생성 완료: secret/harbor/$ENV"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 모든 시크릿 생성 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 생성된 시크릿 확인:"
echo "  vault kv get secret/devops/$ENV"
echo "  vault kv get secret/core-api/$ENV"
echo "  vault kv get secret/idp-api/$ENV"
echo "  vault kv get secret/idp-web/$ENV"
echo "  vault kv get secret/pgadmin/$ENV"
echo "  vault kv get secret/harbor/$ENV"
echo ""
echo "⚠️  다음 항목들을 실제 값으로 업데이트하세요:"
echo ""
echo "# Object storage 자격증명 업데이트"
echo "vault kv patch secret/devops/$ENV \\"
echo "  OBJECT_STORAGE_ACCESS_KEY=<실제_액세스_키> \\"
echo "  OBJECT_STORAGE_SECRET_KEY=<실제_시크릿_키> \\"
echo "  OBJECT_STORAGE_PROVIDER=<aws-s3|backblaze-b2|cloudflare-r2> \\"
echo "  OBJECT_STORAGE_REGION=<실제_리전_또는_auto> \\"
echo "  OBJECT_STORAGE_BUCKET=plate \\"
echo "  OBJECT_STORAGE_ENDPOINT=<실제_엔드포인트> \\"
echo "  OBJECT_STORAGE_API_TOKEN=<실제_API_토큰>"
echo ""
echo "# SMTP 자격증명 업데이트"
echo "vault kv patch secret/core-api/$ENV \\"
echo "  SMTP_SECURE=<true|false> \\"
echo "  SMTP_USERNAME=<실제_사용자명> \\"
echo "  SMTP_PASSWORD=<실제_비밀번호>"
echo ""
echo "# 데이터베이스 URL 업데이트"
echo "vault kv patch secret/core-api/$ENV \\"
echo "  DATABASE_URL=<실제_DB_URL> \\"
echo "  DIRECT_URL=<실제_DIRECT_URL>"
echo ""
echo "# pgAdmin 로그인 정보 업데이트"
echo "vault kv patch secret/pgadmin/$ENV \\"
echo "  PGADMIN_EMAIL=<실제_EMAIL> \\"
echo "  PGADMIN_PASSWORD=<실제_비밀번호>"
echo ""
echo "# IDP API 시크릿 업데이트"
echo "vault kv patch secret/idp-api/$ENV \\"
echo "  DATABASE_URL=<실제_DB_URL> \\"
echo "  DIRECT_URL=<실제_DIRECT_URL> \\"
echo "  REDIS_HOST=<실제_REDIS_HOST> \\"
echo "  REDIS_PASSWORD=<실제_REDIS_PASSWORD> \\"
echo "  SMTP_SECURE=<true|false> \\"
echo "  SMTP_USERNAME=<실제_사용자명> \\"
echo "  SMTP_PASSWORD=<실제_비밀번호> \\"
echo "  OIDC_COOKIE_SECRET=<32자이상_시크릿> \\"
echo "  OIDC_ADMIN_CLIENT_SECRET=<실제_ADMIN_CLIENT_SECRET> \\"
echo "  OIDC_IDP_WEB_CLIENT_ID=idp-web \\"
echo "  OIDC_IDP_WEB_CLIENT_SECRET=<실제_or_생성된_IDP_WEB_SECRET> \\"
echo "  OIDC_IDP_WEB_REDIRECT_URI=$IDP_DOMAIN/api/v1/auth/callback"
echo ""
echo "# IDP Web 시크릿 업데이트"
echo "vault kv patch secret/idp-web/$ENV \\"
echo "  IDP_API_INTERNAL_URL=<idp_api_service_url>"
echo ""
echo "# JWT 시크릿 업데이트 (선택사항, 자동 생성됨)"
echo "vault kv patch secret/core-api/$ENV \\"
echo "  AUTH_JWT_SECRET=<실제_JWT_시크릿>"
