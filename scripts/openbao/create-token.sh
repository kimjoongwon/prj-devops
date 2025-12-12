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

# 기존 토큰 무효화 옵션
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}기존 토큰 관리${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

echo -e "${YELLOW}기존 토큰을 검색하고 무효화하시겠습니까? (y/N)${NC}"
echo -e "${CYAN}(토큰이 많으면 시간이 오래 걸릴 수 있습니다)${NC}"
read -r CHECK_EXISTING

if [[ "$CHECK_EXISTING" =~ ^[Yy]$ ]]; then
    # 동일한 정책을 사용하는 기존 토큰 조회
    echo -e "${YELLOW}🔍 정책 '$POLICY_NAME'을 사용하는 기존 토큰 검색 중...${NC}"
    
    # 토큰 accessor 목록 조회 (권한이 없으면 건너뛰)
    EXISTING_TOKENS=$(vault list -format=json auth/token/accessors 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$EXISTING_TOKENS" ] || [ "$EXISTING_TOKENS" == "null" ]; then
        echo -e "${YELLOW}⚠️  토큰 목록 조회 권한이 없거나 토큰이 없습니다${NC}"
        echo -e "${BLUE}→ 새 토큰 생성을 계속합니다${NC}"
        echo
    else
        # jq로 배열 파싱
        ACCESSOR_LIST=$(echo "$EXISTING_TOKENS" | jq -r '.[]' 2>/dev/null)
        
        if [ -z "$ACCESSOR_LIST" ]; then
            echo -e "${GREEN}✓${NC} 기존 토큰이 없습니다"
            echo
        else
            MATCHING_ACCESSORS=()
            MATCHING_INFO=()
            
            # 현재 토큰 accessor 미리 조회
            CURRENT_ACCESSOR=$(vault token lookup -format=json 2>/dev/null | jq -r '.data.accessor' 2>/dev/null)
            
            # 최대 20개만 검색 (성능 문제 방지)
            COUNT=0
            MAX_CHECK=20
            
            for ACCESSOR in $ACCESSOR_LIST; do
                # 현재 토큰은 건너뛰
                if [ "$ACCESSOR" == "$CURRENT_ACCESSOR" ]; then
                    continue
                fi
                
                COUNT=$((COUNT + 1))
                if [ $COUNT -gt $MAX_CHECK ]; then
                    echo -e "${YELLOW}⚠️  토큰이 많아 처음 $MAX_CHECK개만 검색합니다${NC}"
                    break
                fi
                
                TOKEN_INFO=$(vault token lookup -accessor "$ACCESSOR" -format=json 2>/dev/null)
                if [ $? -eq 0 ] && [ -n "$TOKEN_INFO" ]; then
                    TOKEN_POLICIES=$(echo "$TOKEN_INFO" | jq -r '.data.policies | join(",")' 2>/dev/null)
                    if echo "$TOKEN_POLICIES" | grep -q "$POLICY_NAME"; then
                        TOKEN_DISPLAY=$(echo "$TOKEN_INFO" | jq -r '.data.display_name // "unknown"' 2>/dev/null)
                        TOKEN_TTL_LEFT=$(echo "$TOKEN_INFO" | jq -r '.data.ttl' 2>/dev/null)
                        
                        MATCHING_ACCESSORS+=("$ACCESSOR")
                        MATCHING_INFO+=("$TOKEN_DISPLAY (TTL: ${TOKEN_TTL_LEFT}s)")
                    fi
                fi
            done
            
            if [ ${#MATCHING_ACCESSORS[@]} -gt 0 ]; then
                echo -e "${CYAN}정책 '$POLICY_NAME'을 사용하는 기존 토큰 ${#MATCHING_ACCESSORS[@]}개 발견:${NC}"
                echo
                for i in "${!MATCHING_INFO[@]}"; do
                    echo "  $((i+1)). ${MATCHING_INFO[$i]}"
                    echo "     Accessor: ${MATCHING_ACCESSORS[$i]:0:20}..."
                done
                echo
                
                echo -e "${YELLOW}기존 토큰을 무효화(revoke)하시겠습니까?${NC}"
                echo "  1) 모든 기존 토큰 무효화"
                echo "  2) 선택적으로 무효화"
                echo "  3) 무효화하지 않음 (기본값)"
                echo
                read -r -p "선택 (1-3): " REVOKE_CHOICE
                
                case $REVOKE_CHOICE in
                    1)
                        echo
                        echo -e "${YELLOW}🚨 모든 기존 토큰을 무효화합니다...${NC}"
                        for ACCESSOR in "${MATCHING_ACCESSORS[@]}"; do
                            if vault token revoke -accessor "$ACCESSOR" 2>/dev/null; then
                                echo -e "${GREEN}✓${NC} 토큰 무효화됨"
                            else
                                echo -e "${RED}✗${NC} 토큰 무효화 실패"
                            fi
                        done
                        echo
                        ;;
                    2)
                        echo
                        echo -e "${CYAN}무효화할 토큰 번호를 입력하세요 (콤마로 구분, 예: 1,3):${NC}"
                        read -r REVOKE_NUMS
                        IFS=',' read -ra NUMS <<< "$REVOKE_NUMS"
                        echo
                        for NUM in "${NUMS[@]}"; do
                            NUM=$(echo "$NUM" | xargs)  # trim
                            IDX=$((NUM - 1))
                            if [ $IDX -ge 0 ] && [ $IDX -lt ${#MATCHING_ACCESSORS[@]} ]; then
                                ACCESSOR="${MATCHING_ACCESSORS[$IDX]}"
                                if vault token revoke -accessor "$ACCESSOR" 2>/dev/null; then
                                    echo -e "${GREEN}✓${NC} 토큰 무효화됨: ${MATCHING_INFO[$IDX]}"
                                else
                                    echo -e "${RED}✗${NC} 토큰 무효화 실패: ${MATCHING_INFO[$IDX]}"
                                fi
                            fi
                        done
                        echo
                        ;;
                    *)
                        echo -e "${BLUE}기존 토큰을 유지합니다${NC}"
                        echo
                        ;;
                esac
            else
                echo -e "${GREEN}✓${NC} 정책 '$POLICY_NAME'을 사용하는 기존 토큰이 없습니다"
                echo
            fi
        fi
    fi
else
    echo -e "${BLUE}→ 기존 토큰 검색을 건너뛰니다${NC}"
    echo
fi

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

    # Kubernetes Secret 생성 옵션
    echo
    echo -e "${YELLOW}Kubernetes에 openbao-token Secret을 생성하시겠습니까? (Y/n)${NC}"
    read -r CREATE_K8S_SECRET
    if [[ ! "$CREATE_K8S_SECRET" =~ ^[Nn]$ ]]; then
        echo
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}Kubernetes Secret 생성${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo

        # kubectl 설치 확인
        if ! command -v kubectl &> /dev/null; then
            echo -e "${RED}❌ kubectl이 설치되지 않았습니다${NC}"
            echo "수동으로 Secret을 생성하세요:"
            echo "  kubectl create secret generic openbao-token --from-literal=token=\"$TOKEN\" -n <namespace>"
        else
            # 네임스페이스 선택
            echo -e "${CYAN}Secret을 생성할 네임스페이스를 선택하세요:${NC}"
            echo "  1) external-secrets (클러스터 레벨 시크릿용)"
            echo "  2) plate-stg (Staging 환경용)"
            echo "  3) plate-prod (Production 환경용)"
            echo "  4) 모두 생성 (권장)"
            echo "  5) 직접 입력"
            echo
            read -r -p "선택 (1-5, 기본값: 4): " NS_CHOICE
            NS_CHOICE=${NS_CHOICE:-4}

            case $NS_CHOICE in
                1) NAMESPACES=("external-secrets") ;;
                2) NAMESPACES=("plate-stg") ;;
                3) NAMESPACES=("plate-prod") ;;
                4) NAMESPACES=("external-secrets" "plate-stg" "plate-prod") ;;
                5)
                    echo -e "${CYAN}네임스페이스를 입력하세요 (콤마로 구분):${NC}"
                    read -r CUSTOM_NS
                    IFS=',' read -ra NAMESPACES <<< "$CUSTOM_NS"
                    ;;
                *) NAMESPACES=("external-secrets" "plate-stg" "plate-prod") ;;
            esac

            echo
            echo -e "${YELLOW}🚀 Kubernetes Secret 생성 중...${NC}"
            echo

            for NS in "${NAMESPACES[@]}"; do
                NS=$(echo "$NS" | xargs)  # trim whitespace
                
                # 네임스페이스 존재 확인
                if ! kubectl get namespace "$NS" &> /dev/null; then
                    echo -e "${YELLOW}⚠️  네임스페이스 '$NS'가 없습니다. 생성하시겠습니까? (y/N)${NC}"
                    read -r CREATE_NS
                    if [[ "$CREATE_NS" =~ ^[Yy]$ ]]; then
                        kubectl create namespace "$NS"
                        echo -e "${GREEN}✓${NC} 네임스페이스 '$NS' 생성됨"
                    else
                        echo -e "${RED}✗${NC} 네임스페이스 '$NS' 건너뛰"
                        continue
                    fi
                fi

                # 기존 Secret 확인
                if kubectl get secret openbao-token -n "$NS" &> /dev/null; then
                    echo -e "${YELLOW}⚠️  Secret 'openbao-token'이 '$NS'에 이미 존재합니다. 덮어쓰시겠습니까? (y/N)${NC}"
                    read -r OVERWRITE
                    if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
                        echo -e "${BLUE}→${NC} '$NS' 건너뛰"
                        continue
                    fi
                    # 기존 Secret 삭제
                    kubectl delete secret openbao-token -n "$NS" &> /dev/null
                fi

                # Secret 생성
                if kubectl create secret generic openbao-token \
                    --from-literal=token="$TOKEN" \
                    -n "$NS" \
                    --dry-run=client -o yaml | \
                    kubectl label -f - --local -o yaml \
                    app.kubernetes.io/managed-by=create-token-script \
                    app.kubernetes.io/component=openbao-token | \
                    kubectl apply -f - &> /dev/null; then
                    echo -e "${GREEN}✓${NC} Secret 'openbao-token' 생성됨: $NS"
                else
                    # 단순 생성 시도
                    if kubectl create secret generic openbao-token \
                        --from-literal=token="$TOKEN" \
                        -n "$NS" 2>/dev/null; then
                        echo -e "${GREEN}✓${NC} Secret 'openbao-token' 생성됨: $NS"
                    else
                        echo -e "${RED}✗${NC} Secret 생성 실패: $NS"
                    fi
                fi
            done

            echo
            echo -e "${GREEN}========================================${NC}"
            echo -e "${GREEN}✅ Kubernetes Secret 생성 완료!${NC}"
            echo -e "${GREEN}========================================${NC}"
            echo
            echo -e "${CYAN}생성된 Secret 확인:${NC}"
            for NS in "${NAMESPACES[@]}"; do
                NS=$(echo "$NS" | xargs)
                if kubectl get secret openbao-token -n "$NS" &> /dev/null; then
                    echo "  kubectl get secret openbao-token -n $NS"
                fi
            done
            echo
            echo -e "${BLUE}💡 다음 단계:${NC}"
            echo "  1. ArgoCD에서 openbao-secrets-manager sync"
            echo "  2. ArgoCD에서 openbao-cluster-secrets-manager sync"
            echo "  3. SecretStore/ClusterSecretStore 상태 확인:"
            echo "     kubectl get secretstore -A"
            echo "     kubectl get clustersecretstore"
            echo
        fi
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
