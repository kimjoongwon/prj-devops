#!/bin/bash
# Helm Values 싱크 검증 스크립트
# 모든 앱의 values 파일 일관성을 검사합니다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_DIR="${SCRIPT_DIR}/../helm/applications"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 검사 결과 카운터
PASS=0
FAIL=0
WARN=0

# 유틸리티 함수
log_pass() { echo -e "${GREEN}✓${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}✗${NC} $1"; ((FAIL++)); }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; ((WARN++)); }
log_info() { echo -e "  $1"; }

# appSecrets가 필요한 앱 목록 (nginx 프록시, PVC만 관리하는 앱 제외)
APPS_WITH_SECRETS=("plate-server" "plate-admin")
# 모든 앱 목록
ALL_APPS=("plate-server" "plate-admin" "plate-web" "plate-llm" "plate-cache")

echo "========================================"
echo " Helm Values 싱크 검증"
echo "========================================"
echo ""

# 1. 파일 존재 여부 검사
echo "📁 파일 존재 여부 검사"
echo "----------------------------------------"
for app in "${ALL_APPS[@]}"; do
    app_dir="${HELM_DIR}/${app}"

    if [[ ! -d "$app_dir" ]]; then
        log_fail "${app}: 디렉토리 없음"
        continue
    fi

    # values.yaml 필수
    if [[ -f "${app_dir}/values.yaml" ]]; then
        log_pass "${app}/values.yaml"
    else
        log_fail "${app}/values.yaml 없음"
    fi

    # stg/prod는 선택적이지만 권장
    for env in stg prod; do
        if [[ -f "${app_dir}/values-${env}.yaml" ]]; then
            log_pass "${app}/values-${env}.yaml"
        else
            log_warn "${app}/values-${env}.yaml 없음 (선택사항)"
        fi
    done
done
echo ""

# 2. appSecrets 설정 검사
echo "🔐 appSecrets 설정 검사"
echo "----------------------------------------"
EXPECTED_SECRET="app-env-secrets"

for app in "${APPS_WITH_SECRETS[@]}"; do
    app_dir="${HELM_DIR}/${app}"

    for values_file in values.yaml values-stg.yaml values-prod.yaml; do
        file_path="${app_dir}/${values_file}"

        if [[ ! -f "$file_path" ]]; then
            continue
        fi

        # secretName 추출
        secret_name=$(grep -E "^\s*secretName:" "$file_path" | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'")

        if [[ "$secret_name" == "$EXPECTED_SECRET" ]]; then
            log_pass "${app}/${values_file}: secretName=${secret_name}"
        elif [[ -n "$secret_name" ]]; then
            log_fail "${app}/${values_file}: secretName=${secret_name} (예상: ${EXPECTED_SECRET})"
        else
            log_warn "${app}/${values_file}: secretName 없음"
        fi
    done
done
echo ""

# 3. 이미지 저장소 규칙 검사
echo "🐳 이미지 저장소 규칙 검사"
echo "----------------------------------------"
for app in "${ALL_APPS[@]}"; do
    app_dir="${HELM_DIR}/${app}"

    # values-stg.yaml 검사
    stg_file="${app_dir}/values-stg.yaml"
    if [[ -f "$stg_file" ]]; then
        stg_repo=$(grep -E "^\s*repository:" "$stg_file" | head -1 | awk '{print $2}')
        if [[ "$stg_repo" == *"/stg/"* ]] || [[ "$stg_repo" == *"/stg-"* ]] || [[ "$stg_repo" == "nginx" ]]; then
            log_pass "${app}/values-stg.yaml: ${stg_repo}"
        elif [[ -n "$stg_repo" ]]; then
            log_fail "${app}/values-stg.yaml: ${stg_repo} (stg 경로 필요)"
        fi
    fi

    # values-prod.yaml 검사
    prod_file="${app_dir}/values-prod.yaml"
    if [[ -f "$prod_file" ]]; then
        prod_repo=$(grep -E "^\s*repository:" "$prod_file" | head -1 | awk '{print $2}')
        if [[ "$prod_repo" == *"/prod/"* ]] || [[ "$prod_repo" == *"/prod-"* ]] || [[ "$prod_repo" == "nginx" ]]; then
            log_pass "${app}/values-prod.yaml: ${prod_repo}"
        elif [[ -n "$prod_repo" ]]; then
            log_fail "${app}/values-prod.yaml: ${prod_repo} (prod 경로 필요)"
        fi
    fi
done
echo ""

# 4. Helm Lint 검사
echo "🔍 Helm Lint 검사"
echo "----------------------------------------"
for app in "${ALL_APPS[@]}"; do
    app_dir="${HELM_DIR}/${app}"

    if [[ ! -f "${app_dir}/Chart.yaml" ]]; then
        log_warn "${app}: Chart.yaml 없음 (lint 스킵)"
        continue
    fi

    # 기본 lint
    if helm lint "$app_dir" > /dev/null 2>&1; then
        log_pass "${app}: helm lint 통과"
    else
        log_fail "${app}: helm lint 실패"
        log_info "$(helm lint "$app_dir" 2>&1 | grep -E '(ERROR|WARNING)')"
    fi

    # 환경별 lint
    for env in stg prod; do
        values_file="${app_dir}/values-${env}.yaml"
        if [[ -f "$values_file" ]]; then
            if helm lint "$app_dir" -f "$values_file" > /dev/null 2>&1; then
                log_pass "${app} (${env}): helm lint 통과"
            else
                log_fail "${app} (${env}): helm lint 실패"
            fi
        fi
    done
done
echo ""

# 결과 요약
echo "========================================"
echo " 검사 결과 요약"
echo "========================================"
echo -e "${GREEN}통과: ${PASS}${NC}"
echo -e "${RED}실패: ${FAIL}${NC}"
echo -e "${YELLOW}경고: ${WARN}${NC}"
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo -e "${RED}❌ 싱크 검사 실패${NC}"
    exit 1
else
    echo -e "${GREEN}✅ 싱크 검사 통과${NC}"
    exit 0
fi
