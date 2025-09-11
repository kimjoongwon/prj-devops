#!/bin/bash

# Harbor 인증 ESO 리소스 ArgoCD 배포 스크립트
# ArgoCD를 통한 GitOps 방식의 배포

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ARGOCD_APP_FILE="$PROJECT_ROOT/argocd/harbor-auth.yaml"
HARBOR_AUTH_DIR="$PROJECT_ROOT/helm/shared-configs/harbor-auth"

echo -e "${BLUE}🚀 ArgoCD를 통한 Harbor 인증 ESO 리소스 배포 시작${NC}"
echo "프로젝트 루트: $PROJECT_ROOT"
echo "ArgoCD Application 파일: $ARGOCD_APP_FILE"
echo ""

# 필수 파일 존재 확인
REQUIRED_FILES=(
    "serviceaccount.yaml"
    "openbao-token-secret.yaml" 
    "secret-store.yaml"
    "external-secret.yaml"
)

echo -e "${YELLOW}📋 필수 파일 확인${NC}"
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$HARBOR_AUTH_DIR/$file" ]; then
        echo -e "  ${GREEN}✅ $file${NC}"
    else
        echo -e "  ${RED}❌ $file (없음)${NC}"
        exit 1
    fi
done
echo ""

# OpenBao 토큰 설정 확인
echo -e "${YELLOW}🔑 OpenBao 토큰 설정 확인${NC}"
if grep -q "REPLACE_WITH_BASE64_ENCODED_OPENBAO_TOKEN" "$HARBOR_AUTH_DIR/openbao-token-secret.yaml"; then
    echo -e "${RED}❌ OpenBao 토큰이 아직 설정되지 않았습니다!${NC}"
    echo ""
    echo -e "${BLUE}설정 방법:${NC}"
    echo "1. OpenBao에서 토큰 생성:"
    echo "   bao write auth/token/create policies=\"default\" ttl=\"8760h\""
    echo ""
    echo "2. 토큰을 base64 인코딩:"
    echo "   echo -n \"your_token_here\" | base64"
    echo ""
    echo "3. openbao-token-secret.yaml 파일에서 REPLACE_WITH_BASE64_ENCODED_OPENBAO_TOKEN을 실제 값으로 변경"
    echo ""
    exit 1
else
    echo -e "${GREEN}✅ OpenBao 토큰이 설정되었습니다${NC}"
fi
echo ""

# 네임스페이스 생성
echo -e "${YELLOW}🏠 네임스페이스 생성${NC}"
NAMESPACES=("plate-stg" "plate-prod")

for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ $ns (이미 존재)${NC}"
    else
        echo -e "  ${YELLOW}🔄 $ns 생성 중...${NC}"
        kubectl create namespace "$ns"
        echo -e "  ${GREEN}✅ $ns 생성 완료${NC}"
    fi
done
echo ""

# ESO 설치 확인
echo -e "${YELLOW}📦 ESO 설치 상태 확인${NC}"
if kubectl get namespace external-secrets-system >/dev/null 2>&1; then
    ESO_STATUS=$(kubectl get pods -n external-secrets-system -l app.kubernetes.io/name=external-secrets -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
    if [ "$ESO_STATUS" = "Running" ]; then
        echo -e "${GREEN}✅ ESO가 실행 중입니다${NC}"
    else
        echo -e "${RED}❌ ESO가 실행되지 않고 있습니다 (상태: $ESO_STATUS)${NC}"
        echo "ESO 설치가 필요합니다:"
        echo "  helm install external-secrets external-secrets/external-secrets --namespace external-secrets-system --create-namespace --set installCRDs=true"
        exit 1
    fi
else
    echo -e "${RED}❌ ESO가 설치되지 않았습니다${NC}"
    echo "ESO 설치가 필요합니다:"
    echo "  helm repo add external-secrets https://charts.external-secrets.io"
    echo "  helm install external-secrets external-secrets/external-secrets --namespace external-secrets-system --create-namespace --set installCRDs=true"
    exit 1
fi
echo ""

# ArgoCD Application 배포
echo -e "${YELLOW}🔧 ArgoCD Application 배포${NC}"

# ArgoCD Application 파일 존재 확인
if [ ! -f "$ARGOCD_APP_FILE" ]; then
    echo -e "${RED}❌ ArgoCD Application 파일이 없습니다: $ARGOCD_APP_FILE${NC}"
    exit 1
fi

# ArgoCD CLI 설치 확인
if ! command -v argocd &> /dev/null; then
    echo -e "${YELLOW}⚠️  ArgoCD CLI가 설치되지 않았습니다. kubectl을 사용합니다.${NC}"
    USE_KUBECTL=true
else
    USE_KUBECTL=false
fi

# ArgoCD Application 배포
echo -e "  ${YELLOW}🔄 ArgoCD Application 생성 중...${NC}"
if kubectl apply -f "$ARGOCD_APP_FILE"; then
    echo -e "  ${GREEN}✅ ArgoCD Application 생성 완료${NC}"
else
    echo -e "  ${RED}❌ ArgoCD Application 생성 실패${NC}"
    exit 1
fi

# ArgoCD 동기화
echo -e "  ${YELLOW}🔄 ArgoCD 동기화 중...${NC}"
if [ "$USE_KUBECTL" = true ]; then
    # kubectl을 사용한 동기화 (ArgoCD CLI가 없는 경우)
    echo -e "    ${BLUE}ArgoCD에서 자동 동기화를 기다립니다...${NC}"
    sleep 15
else
    # ArgoCD CLI를 사용한 동기화
    if argocd app sync harbor-auth-eso; then
        echo -e "  ${GREEN}✅ ArgoCD 동기화 완료${NC}"
    else
        echo -e "  ${YELLOW}⚠️  ArgoCD 동기화 실패 - 자동 동기화를 기다립니다...${NC}"
        sleep 15
    fi
fi
echo ""

# 배포 상태 확인
echo -e "${YELLOW}🔍 배포 상태 확인${NC}"

for ns in "${NAMESPACES[@]}"; do
    echo -e "  ${BLUE}네임스페이스: $ns${NC}"
    
    # SecretStore 상태
    if kubectl get secretstore openbao-harbor -n "$ns" >/dev/null 2>&1; then
        STORE_STATUS=$(kubectl get secretstore openbao-harbor -n "$ns" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
        if [ "$STORE_STATUS" = "True" ]; then
            echo -e "    ${GREEN}✅ SecretStore 연결됨${NC}"
        else
            echo -e "    ${YELLOW}⚠️  SecretStore 상태: $STORE_STATUS${NC}"
        fi
    fi
    
    # ExternalSecret 상태
    if kubectl get externalsecret harbor-registry-secret -n "$ns" >/dev/null 2>&1; then
        EXT_STATUS=$(kubectl get externalsecret harbor-registry-secret -n "$ns" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
        if [ "$EXT_STATUS" = "True" ]; then
            echo -e "    ${GREEN}✅ ExternalSecret 동기화됨${NC}"
        else
            echo -e "    ${YELLOW}⚠️  ExternalSecret 상태: $EXT_STATUS${NC}"
        fi
    fi
    
    # Harbor Docker Secret 생성 확인
    if kubectl get secret harbor-docker-secret -n "$ns" >/dev/null 2>&1; then
        echo -e "    ${GREEN}✅ Harbor Docker Secret 생성됨${NC}"
    else
        echo -e "    ${RED}❌ Harbor Docker Secret 생성되지 않음${NC}"
    fi
    
    echo ""
done

# 최종 결과
echo -e "${BLUE}🎉 ArgoCD를 통한 Harbor 인증 ESO 리소스 배포 완료!${NC}"
echo ""
echo -e "${BLUE}ArgoCD 관리:${NC}"
echo "• ArgoCD UI에서 harbor-auth-eso 애플리케이션 확인"
echo "• 동기화 상태 및 리소스 상태 모니터링"
echo ""
echo -e "${BLUE}다음 단계:${NC}"
echo "1. Harbor Robot Account가 생성되어 있는지 확인"
echo "2. OpenBao에 Harbor 인증정보가 저장되어 있는지 확인:"
echo "   bao kv-get secret/harbor/staging"
echo "   bao kv-get secret/harbor/production"
echo "3. 검증 스크립트 실행:"
echo "   $SCRIPT_DIR/verify-harbor-auth.sh"
echo "4. 애플리케이션 재배포하여 Harbor 이미지 pull 확인"