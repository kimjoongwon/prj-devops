#!/bin/bash

# Harbor 이미지 마이그레이션 스크립트
# 기존 Docker Hub 이미지들을 Harbor registry로 복사

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Harbor 설정
HARBOR_URL="harbor.cocdev.co.kr"
HARBOR_USER="admin"
HARBOR_PASSWORD="Harbor12345"
HARBOR_PROJECT="server-stg"  # 올바른 프로젝트 경로

echo -e "${BLUE}🚀 Harbor 이미지 마이그레이션 시작${NC}"
echo "Harbor URL: ${HARBOR_URL}"
echo "Project: ${HARBOR_PROJECT}"
echo ""

# Harbor 로그인
echo -e "${YELLOW}📝 Harbor 로그인 중...${NC}"
if docker login ${HARBOR_URL} -u ${HARBOR_USER} -p ${HARBOR_PASSWORD}; then
    echo -e "${GREEN}✅ Harbor 로그인 성공${NC}"
else
    echo -e "${RED}❌ Harbor 로그인 실패${NC}"
    exit 1
fi

echo ""

# 마이그레이션할 이미지 목록 (server 이미지만)
IMAGES=(
    "kimjoongwon/server:48"
)

# 성공/실패 카운터
SUCCESS_COUNT=0
TOTAL_COUNT=${#IMAGES[@]}

echo -e "${BLUE}📦 총 ${TOTAL_COUNT}개 이미지 마이그레이션 시작${NC}"
echo ""

# 각 이미지 처리
for image in "${IMAGES[@]}"; do
    echo -e "${YELLOW}🔄 처리 중: ${image}${NC}"
    
    # 이미지명에서 태그 분리
    if [[ $image == *":"* ]]; then
        image_name=${image%:*}  # 이미지명 (태그 제외)
        image_tag=${image#*:}   # 태그
    else
        image_name=$image
        image_tag="latest"
    fi
    
    # 기본 이미지명에서 앞의 부분 제거 (예: kimjoongwon/server -> server)
    base_name=$(basename $image_name)
    harbor_image="${HARBOR_URL}/${HARBOR_PROJECT}/${base_name}:${image_tag}"
    
    echo "  • 소스: ${image}"
    echo "  • 대상: ${harbor_image}"
    
    # 이미지 pull
    echo "  • Pulling image..."
    if docker pull $image; then
        echo -e "    ${GREEN}✅ Pull 성공${NC}"
    else
        echo -e "    ${RED}❌ Pull 실패${NC}"
        continue
    fi
    
    # Harbor 태그로 변경
    echo "  • Tagging image..."
    if docker tag $image $harbor_image; then
        echo -e "    ${GREEN}✅ Tag 성공${NC}"
    else
        echo -e "    ${RED}❌ Tag 실패${NC}"
        continue
    fi
    
    # Harbor에 push
    echo "  • Pushing to Harbor..."
    if docker push $harbor_image; then
        echo -e "    ${GREEN}✅ Push 성공${NC}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "    ${RED}❌ Push 실패${NC}"
        continue
    fi
    
    # 로컬 이미지 정리 (선택사항)
    echo "  • Cleaning up local tags..."
    docker rmi $harbor_image >/dev/null 2>&1 || true
    
    echo ""
done

# 결과 요약
echo -e "${BLUE}📊 마이그레이션 결과${NC}"
echo "성공: ${SUCCESS_COUNT}/${TOTAL_COUNT}"

if [ $SUCCESS_COUNT -eq $TOTAL_COUNT ]; then
    echo -e "${GREEN}🎉 모든 이미지 마이그레이션 완료!${NC}"
    echo ""
    echo -e "${BLUE}다음 단계:${NC}"
    echo "1. OpenBao에 Harbor 인증정보가 저장되어 있는지 확인"
    echo "2. ESO 리소스 배포: kubectl apply -f helm/shared-configs/harbor-auth/"
    echo "3. 애플리케이션 재배포하여 Harbor에서 이미지 pull 확인"
    exit 0
else
    echo -e "${YELLOW}⚠️  일부 이미지 마이그레이션 실패${NC}"
    echo "실패한 이미지들을 수동으로 확인해주세요."
    exit 1
fi