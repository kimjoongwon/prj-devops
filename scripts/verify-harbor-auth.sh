#!/bin/bash

# Harbor + ESO + OpenBao 통합 검증 스크립트
# ESO가 OpenBao에서 Harbor 인증정보를 가져와 Docker secret을 생성하는지 확인

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 네임스페이스 정의
NAMESPACES=("plate-stg" "plate-prod")

echo -e "${BLUE}🔍 Harbor 인증 검증 시작${NC}"
echo ""

# 전체 검증 결과 추적
TOTAL_CHECKS=0
PASSED_CHECKS=0

# 헬퍼 함수: 검증 결과 출력
check_result() {
    local test_name="$1"
    local result="$2"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if [ "$result" = "pass" ]; then
        echo -e "  ${GREEN}✅ ${test_name}${NC}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "  ${RED}❌ ${test_name}${NC}"
    fi
}

# 1. ESO 설치 확인
echo -e "${YELLOW}📦 ESO (External Secrets Operator) 상태 확인${NC}"
if kubectl get pods -n external-secrets-system -l app.kubernetes.io/name=external-secrets >/dev/null 2>&1; then
    ESO_READY=$(kubectl get pods -n external-secrets-system -l app.kubernetes.io/name=external-secrets -o jsonpath='{.items[0].status.phase}')
    if [ "$ESO_READY" = "Running" ]; then
        check_result "ESO Pod 실행 상태" "pass"
    else
        check_result "ESO Pod 실행 상태" "fail"
        echo -e "    ${RED}ESO Pod 상태: $ESO_READY${NC}"
    fi
else
    check_result "ESO 설치 상태" "fail"
    echo -e "    ${RED}ESO가 설치되지 않았습니다${NC}"
fi

echo ""

# 2. 네임스페이스별 검증
for ns in "${NAMESPACES[@]}"; do
    echo -e "${YELLOW}🏠 네임스페이스: ${ns}${NC}"
    
    # 네임스페이스 존재 확인
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
        check_result "네임스페이스 존재" "pass"
    else
        check_result "네임스페이스 존재" "fail"
        echo -e "    ${RED}네임스페이스 $ns가 존재하지 않습니다${NC}"
        continue
    fi
    
    # OpenBao 토큰 Secret 확인
    if kubectl get secret openbao-token -n "$ns" >/dev/null 2>&1; then
        check_result "OpenBao 토큰 Secret" "pass"
    else
        check_result "OpenBao 토큰 Secret" "fail"
        echo -e "    ${RED}openbao-token secret이 존재하지 않습니다${NC}"
    fi
    
    # ServiceAccount 확인
    if kubectl get serviceaccount harbor-secret-reader -n "$ns" >/dev/null 2>&1; then
        check_result "ServiceAccount 존재" "pass"
    else
        check_result "ServiceAccount 존재" "fail"
    fi
    
    # SecretStore 확인
    if kubectl get secretstore openbao-harbor -n "$ns" >/dev/null 2>&1; then
        check_result "SecretStore 생성" "pass"
        
        # SecretStore 상태 확인
        STORE_STATUS=$(kubectl get secretstore openbao-harbor -n "$ns" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
        if [ "$STORE_STATUS" = "True" ]; then
            check_result "SecretStore 연결 상태" "pass"
        else
            check_result "SecretStore 연결 상태" "fail"
            echo -e "    ${RED}SecretStore 상태: $STORE_STATUS${NC}"
        fi
    else
        check_result "SecretStore 생성" "fail"
    fi
    
    # ExternalSecret 확인
    if kubectl get externalsecret harbor-registry-secret -n "$ns" >/dev/null 2>&1; then
        check_result "ExternalSecret 생성" "pass"
        
        # ExternalSecret 상태 확인
        EXT_STATUS=$(kubectl get externalsecret harbor-registry-secret -n "$ns" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
        if [ "$EXT_STATUS" = "True" ]; then
            check_result "ExternalSecret 동기화 상태" "pass"
        else
            check_result "ExternalSecret 동기화 상태" "fail"
            echo -e "    ${RED}ExternalSecret 상태: $EXT_STATUS${NC}"
        fi
    else
        check_result "ExternalSecret 생성" "fail"
    fi
    
    # Harbor Docker Secret 생성 확인
    if kubectl get secret harbor-docker-secret -n "$ns" >/dev/null 2>&1; then
        check_result "Harbor Docker Secret 생성" "pass"
        
        # Secret 타입 확인
        SECRET_TYPE=$(kubectl get secret harbor-docker-secret -n "$ns" -o jsonpath='{.type}')
        if [ "$SECRET_TYPE" = "kubernetes.io/dockerconfigjson" ]; then
            check_result "Docker Secret 타입" "pass"
        else
            check_result "Docker Secret 타입" "fail"
            echo -e "    ${RED}예상 타입: kubernetes.io/dockerconfigjson, 실제: $SECRET_TYPE${NC}"
        fi
        
        # Secret 내용 검증 (harbor.onjitda.com 포함 여부)
        if kubectl get secret harbor-docker-secret -n "$ns" -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | grep -q "harbor.onjitda.com"; then
            check_result "Harbor 레지스트리 URL 확인" "pass"
        else
            check_result "Harbor 레지스트리 URL 확인" "fail"
        fi
    else
        check_result "Harbor Docker Secret 생성" "fail"
    fi
    
    echo ""
done

# 3. Harbor 이미지 Pull 테스트
echo -e "${YELLOW}🐳 Harbor 이미지 Pull 테스트${NC}"

# 테스트용 Pod 생성 및 확인
TEST_POD="harbor-auth-test-$(date +%s)"
TEST_IMAGE="harbor.onjitda.com/harbor/stg-server/server:48"

echo "테스트 Pod: $TEST_POD"
echo "테스트 이미지: $TEST_IMAGE"

# plate-stg 네임스페이스에서 테스트
cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: $TEST_POD
  namespace: plate-stg
spec:
  restartPolicy: Never
  imagePullSecrets:
  - name: harbor-docker-secret
  containers:
  - name: test
    image: $TEST_IMAGE
    command: ['echo', 'Harbor authentication successful']
EOF

# Pod 상태 대기 및 확인
echo "Pod 생성 대기 중..."
sleep 10

POD_STATUS=$(kubectl get pod $TEST_POD -n plate-stg -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [ "$POD_STATUS" = "Running" ] || [ "$POD_STATUS" = "Succeeded" ]; then
    check_result "Harbor 이미지 Pull 테스트" "pass"
else
    check_result "Harbor 이미지 Pull 테스트" "fail"
    echo -e "    ${RED}Pod 상태: $POD_STATUS${NC}"
    
    # 실패 원인 분석
    echo -e "    ${YELLOW}Pod 이벤트 확인:${NC}"
    kubectl describe pod $TEST_POD -n plate-stg | grep -A5 "Events:" | tail -5 | sed 's/^/      /'
fi

# 테스트 Pod 정리
kubectl delete pod $TEST_POD -n plate-stg >/dev/null 2>&1 || true

echo ""

# 4. 최종 결과 요약
echo -e "${BLUE}📊 검증 결과 요약${NC}"
echo "통과: ${PASSED_CHECKS}/${TOTAL_CHECKS}"

if [ $PASSED_CHECKS -eq $TOTAL_CHECKS ]; then
    echo -e "${GREEN}🎉 모든 검증 통과! Harbor 인증이 정상적으로 작동합니다.${NC}"
    echo ""
    echo -e "${BLUE}다음 단계:${NC}"
    echo "1. 애플리케이션 재배포하여 Harbor에서 이미지 pull 확인"
    echo "2. ArgoCD에서 배포 상태 모니터링"
    exit 0
else
    FAILED_CHECKS=$((TOTAL_CHECKS - PASSED_CHECKS))
    echo -e "${YELLOW}⚠️  $FAILED_CHECKS 개의 검증 실패${NC}"
    echo ""
    echo -e "${BLUE}문제 해결 가이드:${NC}"
    echo "1. OpenBao 토큰이 올바르게 설정되었는지 확인"
    echo "2. Harbor Robot Account가 활성화되어 있는지 확인"
    echo "3. ESO 로그 확인: kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets"
    echo "4. SecretStore와 ExternalSecret 상태 확인"
    exit 1
fi