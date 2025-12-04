#!/bin/bash

# OpenBao 토큰 생성 스크립트
# 사용법: ./scripts/create-token.sh [정책명]
# 예제: ./scripts/create-token.sh esc-policy

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}OpenBao 토큰 생성 스크립트${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# 환경 변수 확인
if [ -z "$VAULT_ADDR" ]; then
    echo -e "${RED}❌ VAULT_ADDR 환경 변수가 설정되지 않았습니다${NC}"
    echo
    echo "다음 명령어로 설정하세요:"
    echo "  export VAULT_ADDR=https://openbao.cocdev.co.kr"
    echo "  또는"
    echo "  export VAULT_ADDR=http://localhost:8200"
    exit 1
fi

echo -e "${GREEN}✓${NC} VAULT_ADDR: $VAULT_ADDR"

# vault CLI 설치 확인
if ! command -v vault &> /dev/null; then
    echo -e "${RED}❌ vault CLI가 설치되지 않았습니다${NC}"
    echo
    echo "다음 명령어로 설치하세요:"
    echo "  ./scripts/install-vault-cli.sh"
    exit 1
fi

echo -e "${GREEN}✓${NC} vault CLI 설치됨: $(vault version | head -n 1)"
echo

# OpenBao 연결 테스트
echo -e "${YELLOW}🔍 OpenBao 서버 연결 테스트...${NC}"
if ! vault status &> /dev/null; then
    echo -e "${RED}❌ OpenBao 서버에 연결할 수 없습니다${NC}"
    echo
    echo "다음을 확인하세요:"
    echo "  1. VAULT_ADDR이 올바른지 확인"
    echo "  2. OpenBao 서버가 실행 중인지 확인"
    echo "  3. 네트워크 연결 확인"
    exit 1
fi

echo -e "${GREEN}✓${NC} OpenBao 서버 연결 성공"
echo

# 토큰 확인
echo -e "${YELLOW}🔍 인증 상태 확인...${NC}"
if ! vault token lookup &> /dev/null; then
    echo -e "${RED}❌ 로그인되지 않았습니다${NC}"
    echo
    echo "다음 명령어로 로그인하세요:"
    echo "  vault login"
    exit 1
fi

# 현재 토큰 정보 표시
TOKEN_INFO=$(vault token lookup -format=json 2>/dev/null)
DISPLAY_NAME=$(echo "$TOKEN_INFO" | jq -r '.data.display_name // "unknown"')
CURRENT_POLICIES=$(echo "$TOKEN_INFO" | jq -r '.data.policies | join(", ")')

echo -e "${GREEN}✓${NC} 로그인됨: $DISPLAY_NAME"
echo -e "${GREEN}✓${NC} 현재 정책: $CURRENT_POLICIES"
echo

# 정책명 입력받기
if [ -n "$1" ]; then
    POLICY_NAME="$1"
else
    echo -e "${BLUE}정책 이름을 입력하세요 (기본값: esc-policy):${NC}"
    read -r POLICY_NAME
    POLICY_NAME=${POLICY_NAME:-esc-policy}
fi

# 정책 존재 확인
echo -e "${YELLOW}🔍 정책 확인 중...${NC}"
if ! vault policy read "$POLICY_NAME" &> /dev/null; then
    echo -e "${RED}❌ 정책 '$POLICY_NAME'을 찾을 수 없습니다${NC}"
    echo
    echo "사용 가능한 정책 목록:"
    vault policy list
    echo
    echo "정책을 먼저 생성하세요:"
    echo "  ./scripts/create-policy.sh"
    exit 1
fi

echo -e "${GREEN}✓${NC} 정책 '$POLICY_NAME' 확인됨"
echo

# 토큰 설정 입력받기
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}토큰 설정${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Display Name
echo -e "${CYAN}토큰 표시 이름을 입력하세요 (기본값: team-token):${NC}"
read -r TOKEN_DISPLAY_NAME
TOKEN_DISPLAY_NAME=${TOKEN_DISPLAY_NAME:-team-token}

# TTL (Time To Live)
echo
echo -e "${CYAN}토큰 유효 기간을 입력하세요${NC}"
echo "  예: 720h (30일), 168h (7일), 24h (1일)"
echo "  기본값: 720h (30일)"
read -r TOKEN_TTL
TOKEN_TTL=${TOKEN_TTL:-720h}

# Period (자동 갱신 주기)
echo
echo -e "${CYAN}토큰 자동 갱신 주기를 입력하세요${NC}"
echo "  예: 24h (매일), 168h (매주)"
echo "  기본값: 24h (매일 자동 갱신)"
read -r TOKEN_PERIOD
TOKEN_PERIOD=${TOKEN_PERIOD:-24h}

# Renewable
echo
echo -e "${CYAN}토큰 갱신 가능 여부 (Y/n):${NC}"
read -r TOKEN_RENEWABLE
if [[ "$TOKEN_RENEWABLE" =~ ^[Nn]$ ]]; then
    RENEWABLE_FLAG=""
else
    RENEWABLE_FLAG="-renewable=true"
fi

echo
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}토큰 설정 요약${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  정책: $POLICY_NAME"
echo "  표시 이름: $TOKEN_DISPLAY_NAME"
echo "  유효 기간: $TOKEN_TTL"
echo "  자동 갱신: $TOKEN_PERIOD"
echo "  갱신 가능: ${RENEWABLE_FLAG:-false}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

echo -e "${YELLOW}위 설정으로 토큰을 생성하시겠습니까? (Y/n)${NC}"
read -r CONFIRM
if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    echo -e "${BLUE}작업이 취소되었습니다${NC}"
    exit 0
fi

echo
echo -e "${YELLOW}🚀 토큰 생성 중...${NC}"
echo

# 토큰 생성
TOKEN_OUTPUT=$(vault token create \
    -policy="$POLICY_NAME" \
    -ttl="$TOKEN_TTL" \
    -period="$TOKEN_PERIOD" \
    -display-name="$TOKEN_DISPLAY_NAME" \
    $RENEWABLE_FLAG \
    -format=json 2>&1)

if [ $? -eq 0 ]; then
    # 토큰 추출
    TOKEN=$(echo "$TOKEN_OUTPUT" | jq -r '.auth.client_token')
    TOKEN_ACCESSOR=$(echo "$TOKEN_OUTPUT" | jq -r '.auth.accessor')

    # Base64 인코딩 (echo -n 사용 - 개행문자 제거)
    # macOS와 Linux 모두 호환
    TOKEN_BASE64=$(printf '%s' "$TOKEN" | base64 | tr -d '\n')

    # Base64 인코딩 검증
    DECODED_TOKEN=$(echo "$TOKEN_BASE64" | base64 -d 2>/dev/null)
    if [ "$DECODED_TOKEN" != "$TOKEN" ]; then
        echo -e "${RED}⚠️  Base64 인코딩 검증 실패!${NC}"
        echo "원본: $TOKEN"
        echo "디코딩: $DECODED_TOKEN"
        exit 1
    fi

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ 토큰이 성공적으로 생성되었습니다!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo

    # 토큰 정보 표시
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}생성된 토큰 정보${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}토큰 (Token):${NC}"
    echo -e "${GREEN}$TOKEN${NC}"
    echo
    echo -e "${CYAN}토큰 Base64 인코딩:${NC}"
    echo -e "${GREEN}$TOKEN_BASE64${NC}"
    echo
    echo -e "${CYAN}토큰 Accessor:${NC}"
    echo "$TOKEN_ACCESSOR"
    echo
    echo -e "${CYAN}정책 (Policy):${NC}"
    echo "$POLICY_NAME"
    echo
    echo -e "${CYAN}표시 이름:${NC}"
    echo "$TOKEN_DISPLAY_NAME"
    echo
    echo -e "${CYAN}유효 기간 (TTL):${NC}"
    echo "$TOKEN_TTL"
    echo
    echo -e "${CYAN}자동 갱신 주기:${NC}"
    echo "$TOKEN_PERIOD"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo

    # 보안 경고
    echo -e "${RED}⚠️  보안 주의사항:${NC}"
    echo "  1. 이 토큰을 안전한 곳에 저장하세요"
    echo "  2. Git에 절대 커밋하지 마세요"
    echo "  3. 평문으로 저장하지 마세요"
    echo "  4. 필요 없어지면 즉시 폐기하세요"
    echo

    # 사용 예제
    echo -e "${BLUE}📝 토큰 사용 방법:${NC}"
    echo
    echo "1. 환경 변수로 설정:"
    echo "   export VAULT_TOKEN=$TOKEN"
    echo
    echo "2. CLI에서 직접 사용:"
    echo "   vault kv get -token=$TOKEN secret/server/staging"
    echo
    echo "3. 토큰 정보 확인:"
    echo "   vault token lookup $TOKEN"
    echo
    echo "4. 토큰 갱신:"
    echo "   vault token renew $TOKEN"
    echo
    echo "5. 토큰 폐기:"
    echo "   vault token revoke $TOKEN"
    echo

    # 정책 정보 표시
    echo -e "${BLUE}📋 정책이 허용하는 작업:${NC}"
    echo
    vault policy read "$POLICY_NAME" | grep -E "^path|capabilities" | head -20
    echo

    # 토큰 파일로 저장 옵션
    echo -e "${YELLOW}토큰을 파일로 저장하시겠습니까? (y/N)${NC}"
    read -r SAVE_TOKEN
    if [[ "$SAVE_TOKEN" =~ ^[Yy]$ ]]; then
        TOKEN_FILE="token-${TOKEN_DISPLAY_NAME}-$(date +%Y%m%d-%H%M%S).txt"
        cat > "$TOKEN_FILE" << EOF
# OpenBao Token Information
# Generated: $(date)
# WARNING: Keep this file secure and never commit to git!

Token: $TOKEN
Token (Base64): $TOKEN_BASE64
Accessor: $TOKEN_ACCESSOR
Policy: $POLICY_NAME
Display Name: $TOKEN_DISPLAY_NAME
TTL: $TOKEN_TTL
Period: $TOKEN_PERIOD

# Usage:
# export VAULT_TOKEN=$TOKEN
# vault kv get secret/server/staging
EOF
        echo
        echo -e "${GREEN}✓${NC} 토큰이 다음 파일에 저장되었습니다: $TOKEN_FILE"
        echo -e "${RED}⚠️  이 파일을 안전하게 보관하고 사용 후 삭제하세요!${NC}"
        echo
    fi

    # Helm values 파일 업데이트 옵션
    echo
    echo -e "${YELLOW}Helm values 파일에 토큰을 업데이트하시겠습니까? (y/N)${NC}"
    read -r UPDATE_HELM_VALUES
    if [[ "$UPDATE_HELM_VALUES" =~ ^[Yy]$ ]]; then
        # Helm values 파일 경로
        HELM_DIR="helm/shared-configs/openbao-secrets-manager"
        VALUES_FILES=(
            "$HELM_DIR/values.yaml"
            "$HELM_DIR/values-staging.yaml"
            "$HELM_DIR/values-production.yaml"
        )

        echo
        echo -e "${YELLOW}🔄 Helm values 파일 업데이트 중...${NC}"
        echo

        for VALUES_FILE in "${VALUES_FILES[@]}"; do
            if [ -f "$VALUES_FILE" ]; then
                # yq를 사용하여 토큰 값 업데이트 (yq가 있는 경우)
                if command -v yq &> /dev/null; then
                    if yq eval ".openbao.token.value = \"$TOKEN_BASE64\"" -i "$VALUES_FILE" 2>/dev/null; then
                        echo -e "${GREEN}✓${NC} 업데이트됨: $VALUES_FILE"
                    else
                        echo -e "${RED}✗${NC} 업데이트 실패: $VALUES_FILE"
                    fi
                else
                    # yq가 없는 경우 sed 사용 (openbao.token.value 경로만 찾기)
                    # openbao 섹션 내의 token.value를 찾기 위한 패턴
                    if awk '
                        /^openbao:/ { in_openbao=1 }
                        in_openbao && /^[^ ]/ && !/^openbao:/ { in_openbao=0 }
                        in_openbao && /^  token:/ { in_token=1 }
                        in_token && /^  [^ ]/ && !/^  token:/ { in_token=0 }
                        in_token && /^    value:/ {
                            sub(/value: ".*"/, "value: \"'"$TOKEN_BASE64"'\"")
                        }
                        { print }
                    ' "$VALUES_FILE" > "$VALUES_FILE.tmp" && mv "$VALUES_FILE.tmp" "$VALUES_FILE"; then
                        echo -e "${GREEN}✓${NC} 업데이트됨: $VALUES_FILE"
                    else
                        echo -e "${RED}✗${NC} 업데이트 실패: $VALUES_FILE"
                        rm -f "$VALUES_FILE.tmp"
                    fi
                fi
            else
                echo -e "${RED}✗${NC} 파일을 찾을 수 없음: $VALUES_FILE"
            fi
        done

        echo
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}✅ Helm values 파일 업데이트 완료!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo
        echo -e "${CYAN}업데이트된 파일:${NC}"
        for VALUES_FILE in "${VALUES_FILES[@]}"; do
            if [ -f "$VALUES_FILE" ]; then
                echo "  - $VALUES_FILE"
            fi
        done
        echo
        echo -e "${BLUE}💡 다음 단계:${NC}"
        echo "  1. 변경사항 확인:"
        echo "     git diff $HELM_DIR"
        echo
        echo "  2. Helm 차트 배포:"
        echo "     helm upgrade --install openbao-secrets-manager $HELM_DIR -f $HELM_DIR/values-staging.yaml"
        echo "     helm upgrade --install openbao-secrets-manager $HELM_DIR -f $HELM_DIR/values-production.yaml"
        echo
    fi

else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}❌ 토큰 생성에 실패했습니다${NC}"
    echo -e "${RED}========================================${NC}"
    echo
    echo -e "${YELLOW}오류 메시지:${NC}"
    echo "$TOKEN_OUTPUT"
    echo
    echo -e "${YELLOW}가능한 원인:${NC}"
    echo "  1. 권한 부족 (토큰 생성 권한 필요)"
    echo "  2. 정책 이름 오류"
    echo "  3. TTL 설정 오류"
    echo "  4. OpenBao 서버 오류"
    echo
    exit 1
fi
