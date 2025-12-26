#!/bin/bash
# Jenkins 관리자 비밀번호 조회 스크립트

set -e

# 기본 설정
NAMESPACE="${1:-devops-tools}"
SECRET_NAME="${2:-jenkins}"

echo "==================================="
echo "  Jenkins 비밀번호 조회"
echo "==================================="
echo ""

# Secret 존재 여부 확인
if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "오류: Secret '$SECRET_NAME'을(를) '$NAMESPACE' 네임스페이스에서 찾을 수 없습니다."
    echo ""
    echo "사용 가능한 Jenkins 관련 Secret:"
    kubectl get secrets --all-namespaces | grep -i jenkins || echo "  Jenkins Secret이 없습니다."
    exit 1
fi

# 비밀번호 조회
PASSWORD=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath="{.data.jenkins-admin-password}" | base64 -d)

if [ -z "$PASSWORD" ]; then
    echo "오류: 비밀번호를 조회할 수 없습니다."
    exit 1
fi

# 결과 출력
echo "네임스페이스: $NAMESPACE"
echo "Secret 이름:  $SECRET_NAME"
echo "-----------------------------------"
echo "사용자명:     admin"
echo "비밀번호:     $PASSWORD"
echo ""
echo "==================================="
