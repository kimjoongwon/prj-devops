#!/bin/bash

# container-builder-pvc 이미지 관리 스크립트
# Jenkins 빌드에서 사용하는 podman 컨테이너 이미지를 관리합니다.

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 설정
NAMESPACE="devops-tools"
PVC_NAME="container-builder-pvc"
POD_NAME="container-cleanup-$(date +%s)"
PODMAN_IMAGE="quay.io/podman/stable:v4.8.2"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Container Builder PVC 관리 스크립트${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# kubectl 확인
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl이 설치되지 않았습니다${NC}"
    exit 1
fi

# PVC 정보 조회
echo -e "${YELLOW}1. PVC 정보 조회${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

PVC_INFO=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    echo -e "${RED}PVC '$PVC_NAME'을 찾을 수 없습니다${NC}"
    exit 1
fi

PVC_CAPACITY=$(echo "$PVC_INFO" | jq -r '.status.capacity.storage')
PVC_STATUS=$(echo "$PVC_INFO" | jq -r '.status.phase')
PVC_STORAGECLASS=$(echo "$PVC_INFO" | jq -r '.spec.storageClassName')
PVC_VOLUME=$(echo "$PVC_INFO" | jq -r '.spec.volumeName')
PVC_ACCESS=$(echo "$PVC_INFO" | jq -r '.spec.accessModes[0]')
PVC_AGE=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.creationTimestamp}')

echo -e "${CYAN}PVC 이름:${NC}       $PVC_NAME"
echo -e "${CYAN}네임스페이스:${NC}   $NAMESPACE"
echo -e "${CYAN}상태:${NC}           $PVC_STATUS"
echo -e "${CYAN}용량:${NC}           $PVC_CAPACITY"
echo -e "${CYAN}스토리지 클래스:${NC} $PVC_STORAGECLASS"
echo -e "${CYAN}볼륨 이름:${NC}      $PVC_VOLUME"
echo -e "${CYAN}접근 모드:${NC}      $PVC_ACCESS"
echo -e "${CYAN}생성일:${NC}         $PVC_AGE"
echo

# PVC를 사용 중인 Pod 확인
echo -e "${YELLOW}2. PVC 사용 중인 Pod 확인${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

USING_PODS=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null | jq -r --arg pvc "$PVC_NAME" '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == $pvc) | .metadata.name' 2>/dev/null)

if [ -n "$USING_PODS" ]; then
    echo -e "${YELLOW}현재 PVC를 사용 중인 Pod:${NC}"
    echo "$USING_PODS" | while read pod; do
        POD_STATUS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
        echo -e "  - $pod (${POD_STATUS})"
    done
    echo
    echo -e "${RED}PVC를 사용 중인 Pod가 있습니다.${NC}"
    echo -e "${YELLOW}계속 진행하면 해당 Pod의 빌드에 영향을 줄 수 있습니다.${NC}"
    echo
    read -r -p "계속 진행하시겠습니까? (y/N): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}작업을 취소합니다.${NC}"
        exit 0
    fi
else
    echo -e "${GREEN}현재 PVC를 사용 중인 Pod가 없습니다.${NC}"
fi
echo

# 임시 Pod 생성하여 이미지 정보 조회
echo -e "${YELLOW}3. 컨테이너 이미지 목록 조회${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}임시 Pod를 생성하여 이미지 정보를 조회합니다...${NC}"
echo

# Pod 스펙 생성
cat <<EOF | kubectl apply -f - > /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
  namespace: $NAMESPACE
  labels:
    app: container-cleanup
spec:
  restartPolicy: Never
  containers:
  - name: podman
    image: $PODMAN_IMAGE
    command: ["sleep", "3600"]
    securityContext:
      privileged: true
    volumeMounts:
    - name: storage
      mountPath: /var/lib/containers
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: $PVC_NAME
EOF

# Pod가 Ready 상태가 될 때까지 대기
echo -e "${CYAN}Pod 준비 중...${NC}"
kubectl wait --for=condition=Ready pod/"$POD_NAME" -n "$NAMESPACE" --timeout=60s > /dev/null 2>&1

# cleanup 함수
cleanup() {
    echo
    echo -e "${CYAN}임시 Pod 삭제 중...${NC}"
    kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --grace-period=0 --force > /dev/null 2>&1 || true
}
trap cleanup EXIT

# 디스크 사용량 조회
echo
echo -e "${YELLOW}디스크 사용량:${NC}"
kubectl exec "$POD_NAME" -n "$NAMESPACE" -- df -h /var/lib/containers 2>/dev/null | tail -1 | awk '{print "  사용: "$3" / "$2" ("$5" 사용중), 남은공간: "$4}'
echo

# 이미지 목록 조회
echo -e "${YELLOW}저장된 이미지 목록:${NC}"
echo

# podman images를 테이블 형식으로 직접 조회 (JSON 파싱 문제 회피)
IMAGES_TABLE=$(kubectl exec "$POD_NAME" -n "$NAMESPACE" -- podman images --format "{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" 2>/dev/null)

if [ -z "$IMAGES_TABLE" ]; then
    echo -e "${GREEN}저장된 이미지가 없습니다.${NC}"
    echo
    exit 0
fi

# 헤더 출력
printf "%-4s  %-40s  %-10s  %-10s  %s\n" "번호" "리포지토리" "태그" "크기" "생성일"
printf "%-4s  %-40s  %-10s  %-10s  %s\n" "----" "----------------------------------------" "----------" "----------" "----------"

# 이미지 목록 출력
IMAGE_NUM=0
IMAGE_IDS=()
while IFS=$'\t' read -r id repo tag size created; do
    IMAGE_NUM=$((IMAGE_NUM + 1))
    IMAGE_IDS+=("$id")
    # 리포지토리 이름이 길면 자르기
    if [ ${#repo} -gt 40 ]; then
        repo="${repo:0:37}..."
    fi
    # 생성일에서 날짜만 추출
    created_date=$(echo "$created" | cut -d' ' -f1)
    printf "%-4s  %-40s  %-10s  %-10s  %s\n" "$IMAGE_NUM" "$repo" "$tag" "$size" "$created_date"
done <<< "$IMAGES_TABLE"

# 이미지 개수 및 총 크기 계산
IMAGE_COUNT=$IMAGE_NUM
TOTAL_SIZE_RAW=$(kubectl exec "$POD_NAME" -n "$NAMESPACE" -- podman system df --format "{{.TotalSize}}" 2>/dev/null | head -1)

echo
echo -e "${CYAN}총 이미지 수:${NC} ${IMAGE_COUNT}개"
echo -e "${CYAN}총 사용 공간:${NC} ${TOTAL_SIZE_RAW:-N/A}"
echo

# Dangling 이미지 확인
DANGLING_COUNT=$(kubectl exec "$POD_NAME" -n "$NAMESPACE" -- podman images -f "dangling=true" -q 2>/dev/null | wc -l | tr -d ' ')
if [ "$DANGLING_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}Dangling 이미지 (태그 없는 이미지):${NC} ${DANGLING_COUNT}개"
fi

echo
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}4. 정리 옵션 선택${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo "  1) 전체 삭제 (모든 이미지, 캐시, 볼륨 삭제)"
echo "  2) Dangling 이미지만 삭제 (태그 없는 이미지)"
echo "  3) 오래된 이미지 삭제 (특정 일수 이상)"
echo "  4) 선별 삭제 (이미지 번호 선택)"
echo "  5) 빌드 캐시만 삭제"
echo "  6) 취소"
echo
read -r -p "선택 (1-6): " CHOICE

case $CHOICE in
    1)
        echo
        echo -e "${RED}모든 이미지, 캐시, 볼륨을 삭제합니다.${NC}"
        read -r -p "정말 삭제하시겠습니까? (yes를 입력): " CONFIRM
        if [ "$CONFIRM" == "yes" ]; then
            echo
            echo -e "${YELLOW}전체 정리 실행 중...${NC}"
            kubectl exec "$POD_NAME" -n "$NAMESPACE" -- podman system prune -af --volumes
            echo
            echo -e "${GREEN}전체 정리가 완료되었습니다.${NC}"
        else
            echo -e "${BLUE}취소되었습니다.${NC}"
        fi
        ;;
    2)
        echo
        echo -e "${YELLOW}Dangling 이미지 삭제 중...${NC}"
        kubectl exec "$POD_NAME" -n "$NAMESPACE" -- podman image prune -f
        echo
        echo -e "${GREEN}Dangling 이미지 삭제가 완료되었습니다.${NC}"
        ;;
    3)
        echo
        read -r -p "몇 일 이상 된 이미지를 삭제하시겠습니까? (기본값: 7): " DAYS
        DAYS=${DAYS:-7}
        echo
        echo -e "${YELLOW}${DAYS}일 이상 된 이미지 삭제 중...${NC}"
        # 필터를 사용하여 오래된 이미지 삭제
        kubectl exec "$POD_NAME" -n "$NAMESPACE" -- sh -c "podman images --format '{{.ID}} {{.CreatedAt}}' | while read id created; do
            created_ts=\$(date -d \"\$created\" +%s 2>/dev/null || echo 0)
            now_ts=\$(date +%s)
            diff_days=\$(( (now_ts - created_ts) / 86400 ))
            if [ \$diff_days -ge $DAYS ]; then
                echo \"삭제: \$id (생성: \$created)\"
                podman rmi -f \$id 2>/dev/null || true
            fi
        done"
        echo
        echo -e "${GREEN}오래된 이미지 삭제가 완료되었습니다.${NC}"
        ;;
    4)
        echo
        echo -e "${CYAN}삭제할 이미지 번호를 입력하세요 (콤마로 구분, 예: 1,3,5):${NC}"
        read -r IMAGE_NUMS

        if [ -z "$IMAGE_NUMS" ]; then
            echo -e "${BLUE}취소되었습니다.${NC}"
            exit 0
        fi

        # 이미지 ID 목록 다시 가져오기
        IMAGE_ID_LIST=$(kubectl exec "$POD_NAME" -n "$NAMESPACE" -- podman images --format "{{.ID}}" 2>/dev/null)
        mapfile -t IMAGE_ARRAY <<< "$IMAGE_ID_LIST"

        IFS=',' read -ra NUMS <<< "$IMAGE_NUMS"
        echo
        for NUM in "${NUMS[@]}"; do
            NUM=$(echo "$NUM" | xargs)  # trim
            IDX=$((NUM - 1))
            if [ $IDX -ge 0 ] && [ $IDX -lt ${#IMAGE_ARRAY[@]} ]; then
                IMAGE_ID="${IMAGE_ARRAY[$IDX]}"
                echo -e "${YELLOW}삭제 중: $IMAGE_ID${NC}"
                kubectl exec "$POD_NAME" -n "$NAMESPACE" -- podman rmi -f "$IMAGE_ID" 2>/dev/null || echo -e "${RED}삭제 실패: $IMAGE_ID${NC}"
            else
                echo -e "${RED}잘못된 번호: $NUM${NC}"
            fi
        done
        echo
        echo -e "${GREEN}선택한 이미지 삭제가 완료되었습니다.${NC}"
        ;;
    5)
        echo
        echo -e "${YELLOW}빌드 캐시 삭제 중...${NC}"
        kubectl exec "$POD_NAME" -n "$NAMESPACE" -- podman builder prune -af
        echo
        echo -e "${GREEN}빌드 캐시 삭제가 완료되었습니다.${NC}"
        ;;
    6|*)
        echo -e "${BLUE}취소되었습니다.${NC}"
        exit 0
        ;;
esac

# 정리 후 디스크 사용량 표시
echo
echo -e "${YELLOW}정리 후 디스크 사용량:${NC}"
kubectl exec "$POD_NAME" -n "$NAMESPACE" -- df -h /var/lib/containers 2>/dev/null | tail -1 | awk '{print "  사용: "$3" / "$2" ("$5" 사용중), 남은공간: "$4}'
echo

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}작업이 완료되었습니다.${NC}"
echo -e "${GREEN}========================================${NC}"
