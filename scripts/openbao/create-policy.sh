#!/bin/bash

# OpenBao 정책 생성 스크립트
# 사용법: ./scripts/create-policy.sh

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 스크립트 디렉토리 찾기
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
POLICY_FILE="$PROJECT_ROOT/policies/esc-policy.hcl"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}OpenBao 정책 생성 스크립트${NC}"
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

# 정책 파일 존재 확인
if [ ! -f "$POLICY_FILE" ]; then
    echo -e "${RED}❌ 정책 파일을 찾을 수 없습니다: $POLICY_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} 정책 파일 확인: policies/esc-policy.hcl"
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

# 토큰 정보 표시
TOKEN_INFO=$(vault token lookup -format=json 2>/dev/null)
DISPLAY_NAME=$(echo "$TOKEN_INFO" | jq -r '.data.display_name // "unknown"')
POLICIES=$(echo "$TOKEN_INFO" | jq -r '.data.policies | join(", ")')

echo -e "${GREEN}✓${NC} 로그인됨: $DISPLAY_NAME"
echo -e "${GREEN}✓${NC} 현재 정책: $POLICIES"
echo

# 정책 이름 입력받기
echo -e "${BLUE}정책 이름을 입력하세요 (기본값: esc-policy):${NC}"
read -r POLICY_NAME
POLICY_NAME=${POLICY_NAME:-esc-policy}

echo
echo -e "${YELLOW}📋 정책 정보:${NC}"
echo "  이름: $POLICY_NAME"
echo "  파일: policies/esc-policy.hcl"
echo

# 기존 정책 확인
if vault policy read "$POLICY_NAME" &> /dev/null; then
    echo -e "${YELLOW}⚠️  정책 '$POLICY_NAME'이 이미 존재합니다${NC}"
    echo
    echo "기존 정책을 덮어쓰시겠습니까? (y/N)"
    read -r CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}작업이 취소되었습니다${NC}"
        exit 0
    fi
    echo
fi

# 정책 생성
echo -e "${YELLOW}🚀 정책 생성 중...${NC}"
if vault policy write "$POLICY_NAME" "$POLICY_FILE"; then
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ 정책이 성공적으로 생성되었습니다!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo

    # 정책 확인
    echo -e "${BLUE}📄 생성된 정책 내용:${NC}"
    echo
    vault policy read "$POLICY_NAME"
    echo

    # 정책 요약
    echo -e "${BLUE}📊 정책 요약:${NC}"
    echo "  정책 이름: $POLICY_NAME"
    echo "  권한: 읽기 전용 (read-only)"
    echo "  접근 가능 경로:"
    echo "    - secret/data/server/{staging,production,default}"
    echo "    - secret/data/harbor/{staging,production,development}"
    echo "    - auth/token/lookup-self (토큰 정보)"
    echo "    - auth/token/renew-self (토큰 갱신)"
    echo "    - sys/health (헬스체크)"
    echo

    # 다음 단계 안내
    echo -e "${BLUE}📝 다음 단계:${NC}"
    echo
    echo "1. 이 정책으로 토큰 생성:"
    echo "   vault token create \\"
    echo "     -policy=$POLICY_NAME \\"
    echo "     -ttl=720h \\"
    echo "     -period=24h \\"
    echo "     -renewable=true \\"
    echo "     -display-name=team-token"
    echo
    echo "2. 또는 자동화 스크립트 사용:"
    echo "   ./scripts/setup-esc.sh"
    echo
    echo "3. 정책 확인:"
    echo "   vault policy read $POLICY_NAME"
    echo
    echo "4. 정책 목록:"
    echo "   vault policy list"
    echo

else
    echo
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}❌ 정책 생성에 실패했습니다${NC}"
    echo -e "${RED}========================================${NC}"
    echo
    echo -e "${YELLOW}가능한 원인:${NC}"
    echo "  1. 권한 부족 (관리자 권한 필요)"
    echo "  2. 정책 파일 형식 오류"
    echo "  3. OpenBao 서버 오류"
    echo
    exit 1
fi
