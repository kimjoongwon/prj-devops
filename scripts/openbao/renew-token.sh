#!/bin/bash

# OpenBao 토큰 갱신 스크립트
# 사용법: ./scripts/openbao/renew-token.sh [토큰]
# 예제: ./scripts/openbao/renew-token.sh hvs.xxxxx

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}OpenBao 토큰 갱신 스크립트${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# 환경 변수 확인
if [ -z "$VAULT_ADDR" ]; then
    echo -e "${RED}❌ VAULT_ADDR 환경 변수가 설정되지 않았습니다${NC}"
    echo
    echo "다음 명령어로 설정하세요:"
    echo "  export VAULT_ADDR=https://openbao.cocdev.co.kr"
    exit 1
fi

echo -e "${GREEN}✓${NC} VAULT_ADDR: $VAULT_ADDR"

# vault CLI 설치 확인
if ! command -v vault &> /dev/null; then
    echo -e "${RED}❌ vault CLI가 설치되지 않았습니다${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} vault CLI 설치됨"
echo

# 토큰 선택
USE_ACCESSOR=false
TARGET_ACCESSOR=""

if [ -n "$1" ]; then
    TARGET_TOKEN="$1"
else
    echo -e "${YELLOW}🔍 토큰 목록 조회 중...${NC}"
    echo

    # 토큰 accessor 목록 조회
    ACCESSORS=$(vault list -format=json auth/token/accessors 2>/dev/null) || true

    if [ -z "$ACCESSORS" ] || [ "$ACCESSORS" == "null" ] || ! echo "$ACCESSORS" | jq -e '.' > /dev/null 2>&1; then
        echo -e "${RED}❌ 토큰 목록을 조회할 수 없습니다${NC}"
        echo "권한이 없거나 토큰이 없습니다."
        echo
        echo -e "${CYAN}토큰을 직접 입력하세요:${NC}"
        read -r TARGET_TOKEN
    else
        ACCESSOR_LIST=$(echo "$ACCESSORS" | jq -r '.[]' 2>/dev/null)

        # 현재 토큰 accessor (자기 자신 제외용)
        CURRENT_ACCESSOR=$(vault token lookup -format=json 2>/dev/null | jq -r '.data.accessor' 2>/dev/null) || true

        # 토큰 정보 수집
        declare -a TOKEN_ACCESSORS=()
        declare -a TOKEN_INFOS=()
        declare -a TOKEN_VALUES=()

        COUNT=0
        MAX_CHECK=30

        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}갱신 가능한 토큰 목록${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo

        for ACCESSOR in $ACCESSOR_LIST; do
            # 현재 토큰은 건너뛰기
            if [ "$ACCESSOR" == "$CURRENT_ACCESSOR" ]; then
                continue
            fi

            COUNT=$((COUNT + 1))
            if [ $COUNT -gt $MAX_CHECK ]; then
                echo -e "${YELLOW}  ... (최대 $MAX_CHECK개만 표시)${NC}"
                break
            fi

            # 토큰 정보 조회
            TOKEN_DATA=$(vault token lookup -accessor "$ACCESSOR" -format=json 2>/dev/null) || continue

            if [ -z "$TOKEN_DATA" ]; then
                continue
            fi

            # 갱신 가능한 토큰만 표시
            RENEWABLE=$(echo "$TOKEN_DATA" | jq -r '.data.renewable // false')
            if [ "$RENEWABLE" != "true" ]; then
                continue
            fi

            DISPLAY_NAME=$(echo "$TOKEN_DATA" | jq -r '.data.display_name // "unknown"')
            POLICIES=$(echo "$TOKEN_DATA" | jq -r '.data.policies | join(", ")' 2>/dev/null || echo "-")
            TTL_SEC=$(echo "$TOKEN_DATA" | jq -r '.data.ttl // 0')
            PERIOD=$(echo "$TOKEN_DATA" | jq -r '.data.period // 0')

            # 숫자 검증
            if ! [[ "$TTL_SEC" =~ ^[0-9]+$ ]]; then TTL_SEC=0; fi
            if ! [[ "$PERIOD" =~ ^[0-9]+$ ]]; then PERIOD=0; fi

            # TTL 포맷
            if [ "$TTL_SEC" -gt 86400 ]; then
                TTL_FMT="$((TTL_SEC / 86400))일"
            elif [ "$TTL_SEC" -gt 3600 ]; then
                TTL_FMT="$((TTL_SEC / 3600))시간"
            elif [ "$TTL_SEC" -gt 60 ]; then
                TTL_FMT="$((TTL_SEC / 60))분"
            else
                TTL_FMT="${TTL_SEC}초"
            fi

            # 토큰 타입
            if [ "$PERIOD" -gt 0 ]; then
                TYPE_BADGE="${GREEN}[주기적]${NC}"
            else
                TYPE_BADGE="${YELLOW}[일반]${NC}"
            fi

            # TTL 경고 색상
            if [ "$TTL_SEC" -lt 86400 ]; then
                TTL_COLOR="${RED}"
            elif [ "$TTL_SEC" -lt 604800 ]; then
                TTL_COLOR="${YELLOW}"
            else
                TTL_COLOR="${GREEN}"
            fi

            IDX=${#TOKEN_ACCESSORS[@]}
            TOKEN_ACCESSORS+=("$ACCESSOR")
            TOKEN_INFOS+=("$DISPLAY_NAME|$POLICIES|$TTL_FMT")

            echo -e "  ${CYAN}$((IDX + 1)))${NC} ${TYPE_BADGE} ${CYAN}$DISPLAY_NAME${NC}"
            echo -e "     정책: $POLICIES"
            echo -e "     남은 TTL: ${TTL_COLOR}${TTL_FMT}${NC}"
            echo -e "     Accessor: ${ACCESSOR:0:20}..."
            echo
        done

        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo

        if [ ${#TOKEN_ACCESSORS[@]} -eq 0 ]; then
            echo -e "${YELLOW}갱신 가능한 토큰이 없습니다.${NC}"
            echo
            echo -e "${CYAN}토큰을 직접 입력하세요:${NC}"
            read -r TARGET_TOKEN
            USE_ACCESSOR=false
        else
            echo -e "${CYAN}갱신할 토큰 번호를 선택하세요 (1-${#TOKEN_ACCESSORS[@]}), 또는 토큰 직접 입력:${NC}"
            read -r SELECTION

            # 숫자인지 확인
            if [[ "$SELECTION" =~ ^[0-9]+$ ]] && [ "$SELECTION" -ge 1 ] && [ "$SELECTION" -le ${#TOKEN_ACCESSORS[@]} ]; then
                IDX=$((SELECTION - 1))
                TARGET_ACCESSOR="${TOKEN_ACCESSORS[$IDX]}"
                USE_ACCESSOR=true
                TARGET_TOKEN=""
            else
                # 직접 입력한 토큰
                TARGET_TOKEN="$SELECTION"
                USE_ACCESSOR=false
            fi
        fi
    fi
fi

# accessor 모드인 경우
if [ "$USE_ACCESSOR" = true ] && [ -n "$TARGET_ACCESSOR" ]; then
    echo
    echo -e "${YELLOW}🔍 토큰 정보 조회 중...${NC}"
    echo

    # accessor로 토큰 정보 조회
    TOKEN_INFO=$(vault token lookup -accessor "$TARGET_ACCESSOR" -format=json 2>&1) || true

    if [ -z "$TOKEN_INFO" ] || ! echo "$TOKEN_INFO" | jq -e '.data' > /dev/null 2>&1; then
        echo -e "${RED}❌ 토큰 조회 실패${NC}"
        echo "$TOKEN_INFO"
        exit 1
    fi
else
    # 토큰 직접 입력 모드
    if [ -z "$TARGET_TOKEN" ]; then
        echo -e "${RED}❌ 토큰이 입력되지 않았습니다${NC}"
        exit 1
    fi

    echo
    echo -e "${YELLOW}🔍 토큰 정보 조회 중...${NC}"
    echo

    # 토큰 정보 조회 (set -e 우회)
    TOKEN_INFO=$(vault token lookup "$TARGET_TOKEN" -format=json 2>&1) || true

    if [ -z "$TOKEN_INFO" ] || ! echo "$TOKEN_INFO" | jq -e '.data' > /dev/null 2>&1; then
        echo -e "${RED}❌ 토큰 조회 실패${NC}"
        echo "$TOKEN_INFO"
        exit 1
    fi
fi

# 토큰 정보 파싱
DISPLAY_NAME=$(echo "$TOKEN_INFO" | jq -r '.data.display_name // "unknown"')
POLICIES=$(echo "$TOKEN_INFO" | jq -r '.data.policies | join(", ")' 2>/dev/null || echo "unknown")
TTL=$(echo "$TOKEN_INFO" | jq -r '.data.ttl // 0')
CREATION_TTL=$(echo "$TOKEN_INFO" | jq -r '.data.creation_ttl // 0')
EXPIRE_TIME=$(echo "$TOKEN_INFO" | jq -r '.data.expire_time // "없음"')
RENEWABLE=$(echo "$TOKEN_INFO" | jq -r '.data.renewable // false')
PERIOD=$(echo "$TOKEN_INFO" | jq -r '.data.period // 0')

# 숫자가 아니면 0으로 설정 (null, 빈 문자열 등 처리)
if ! [[ "$TTL" =~ ^[0-9]+$ ]]; then
    TTL=0
fi
if ! [[ "$CREATION_TTL" =~ ^[0-9]+$ ]]; then
    CREATION_TTL=0
fi
if ! [[ "$PERIOD" =~ ^[0-9]+$ ]]; then
    PERIOD=0
fi

# TTL을 사람이 읽기 쉬운 형식으로 변환
format_duration() {
    local seconds=$1
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [ $days -gt 0 ]; then
        echo "${days}일 ${hours}시간 ${minutes}분"
    elif [ $hours -gt 0 ]; then
        echo "${hours}시간 ${minutes}분"
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}분 ${secs}초"
    else
        echo "${secs}초"
    fi
}

TTL_FORMATTED=$(format_duration $TTL)
CREATION_TTL_FORMATTED=$(format_duration $CREATION_TTL)

# 토큰 타입 판별
if [ "$PERIOD" -gt 0 ]; then
    PERIOD_FORMATTED=$(format_duration $PERIOD)
    TOKEN_TYPE="주기적 토큰 (Periodic)"
    TOKEN_TYPE_DESC="무한 갱신 가능"
else
    TOKEN_TYPE="일반 토큰"
    TOKEN_TYPE_DESC="max_ttl 제한 있음"
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}현재 토큰 정보${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  표시 이름: ${CYAN}$DISPLAY_NAME${NC}"
echo -e "  정책: ${CYAN}$POLICIES${NC}"
echo -e "  토큰 타입: ${CYAN}$TOKEN_TYPE${NC} ($TOKEN_TYPE_DESC)"
if [ "$PERIOD" -gt 0 ]; then
    echo -e "  갱신 주기: ${CYAN}$PERIOD_FORMATTED${NC}"
fi
echo -e "  초기 TTL: ${CYAN}$CREATION_TTL_FORMATTED${NC}"
echo -e "  남은 TTL: ${YELLOW}$TTL_FORMATTED${NC} (${TTL}초)"
echo -e "  만료 시간: ${CYAN}$EXPIRE_TIME${NC}"
echo -e "  갱신 가능: ${CYAN}$RENEWABLE${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# 갱신 가능 여부 확인
if [ "$RENEWABLE" != "true" ]; then
    echo -e "${RED}❌ 이 토큰은 갱신할 수 없습니다 (renewable=false)${NC}"
    exit 1
fi

# TTL 경고
if [ "$TTL" -lt 3600 ] 2>/dev/null; then
    echo -e "${RED}⚠️  경고: 토큰이 1시간 이내에 만료됩니다!${NC}"
elif [ "$TTL" -lt 86400 ] 2>/dev/null; then
    echo -e "${YELLOW}⚠️  주의: 토큰이 24시간 이내에 만료됩니다${NC}"
fi

echo
echo -e "${YELLOW}이 토큰을 갱신하시겠습니까? (Y/n)${NC}"
read -r CONFIRM
if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    echo -e "${BLUE}작업이 취소되었습니다${NC}"
    exit 0
fi

echo
echo -e "${YELLOW}🚀 토큰 갱신 중...${NC}"
echo

# 토큰 갱신 (set -e 우회)
if [ "$USE_ACCESSOR" = true ] && [ -n "$TARGET_ACCESSOR" ]; then
    RENEW_OUTPUT=$(vault token renew -accessor "$TARGET_ACCESSOR" -format=json 2>&1) || true
else
    RENEW_OUTPUT=$(vault token renew "$TARGET_TOKEN" -format=json 2>&1) || true
fi

if echo "$RENEW_OUTPUT" | jq -e '.auth' > /dev/null 2>&1; then
    # 갱신된 정보 파싱
    NEW_TTL=$(echo "$RENEW_OUTPUT" | jq -r '.auth.lease_duration // 0')
    if ! [[ "$NEW_TTL" =~ ^[0-9]+$ ]]; then
        NEW_TTL=0
    fi
    NEW_TTL_FORMATTED=$(format_duration $NEW_TTL)

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ 토큰이 성공적으로 갱신되었습니다!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo

    # 갱신 후 토큰 정보 다시 조회
    if [ "$USE_ACCESSOR" = true ] && [ -n "$TARGET_ACCESSOR" ]; then
        NEW_TOKEN_INFO=$(vault token lookup -accessor "$TARGET_ACCESSOR" -format=json 2>/dev/null) || true
    else
        NEW_TOKEN_INFO=$(vault token lookup "$TARGET_TOKEN" -format=json 2>/dev/null) || true
    fi
    NEW_EXPIRE_TIME=$(echo "$NEW_TOKEN_INFO" | jq -r '.data.expire_time // "없음"')

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}갱신된 토큰 정보${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  이전 TTL: ${YELLOW}$TTL_FORMATTED${NC}"
    echo -e "  새 TTL: ${GREEN}$NEW_TTL_FORMATTED${NC} (${NEW_TTL}초)"
    echo -e "  새 만료 시간: ${GREEN}$NEW_EXPIRE_TIME${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo

    if [ "$PERIOD" -gt 0 ]; then
        echo -e "${GREEN}💡 주기적 토큰입니다. 주기(${PERIOD_FORMATTED}) 내에 다시 갱신하면 계속 사용할 수 있습니다.${NC}"
    else
        echo -e "${YELLOW}💡 일반 토큰입니다. max_ttl 도달 시 더 이상 갱신할 수 없습니다.${NC}"
    fi
    echo

    echo -e "${BLUE}📝 자동 갱신 설정 (cron 예시):${NC}"
    echo
    if [ "$USE_ACCESSOR" = true ] && [ -n "$TARGET_ACCESSOR" ]; then
        echo "# 매일 자정에 토큰 갱신 (accessor 사용)"
        echo "0 0 * * * VAULT_ADDR=$VAULT_ADDR vault token renew -accessor $TARGET_ACCESSOR"
    else
        echo "# 매일 자정에 토큰 갱신"
        echo "0 0 * * * VAULT_ADDR=$VAULT_ADDR vault token renew $TARGET_TOKEN"
    fi
    echo

else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}❌ 토큰 갱신에 실패했습니다${NC}"
    echo -e "${RED}========================================${NC}"
    echo
    echo -e "${YELLOW}오류 메시지:${NC}"
    echo "$RENEW_OUTPUT"
    echo
    echo -e "${YELLOW}가능한 원인:${NC}"
    echo "  1. 토큰이 이미 만료됨"
    echo "  2. max_ttl에 도달하여 더 이상 갱신 불가"
    echo "  3. 토큰이 revoke됨"
    echo "  4. 네트워크 오류"
    echo
    exit 1
fi
