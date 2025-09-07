#!/bin/bash

# 라이브러리 배포 스크립트
# 이 스크립트는 모든 라이브러리 컴포넌트들(Jenkins, Cert-Manager, MetalLB)을 배포합니다

set -e

# 출력용 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 유틸리티 함수들
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Helm 설치 확인
check_helm() {
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed. Please install Helm first."
        exit 1
    fi
}

# kubectl 연결 상태 확인
check_kubectl() {
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Unable to connect to Kubernetes cluster."
        exit 1
    fi
}

# cert-manager 배포
deploy_cert_manager() {
    log_info "Deploying cert-manager..."
    
    # jetstack 저장소 추가
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    
    # cert-manager CRDs 설치
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.crds.yaml
    
    # cert-manager 설치
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version v1.13.0 \
        --set installCRDs=true
    
    # cert-manager 준비 대기
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cert-manager -n cert-manager --timeout=300s
    
    # cert-manager 설정 적용
    helm upgrade --install cert-manager-config ./helm/cluster-services/cert-manager \
        --namespace cert-manager \
        --values ./environments/shared/common-values.yaml
    
    log_info "cert-manager deployed successfully"
}

# Jenkins 배포
deploy_jenkins() {
    log_info "Deploying Jenkins..."
    
    helm upgrade --install jenkins ./helm/development-tools/jenkins \
        --namespace jenkins \
        --create-namespace \
        --values ./environments/shared/common-values.yaml
    
    log_info "Jenkins deployed successfully"
}

# MetalLB 배포
deploy_metallb() {
    log_info "Deploying MetalLB..."
    
    # Add MetalLB repository
    helm repo add metallb https://metallb.github.io/metallb
    helm repo update
    
    # Install MetalLB
    helm upgrade --install metallb metallb/metallb \
        --namespace metallb-system \
        --create-namespace
    
    # Apply MetalLB configuration
    log_info "Applying MetalLB configuration..."
    kubectl apply -f ./helm/cluster-services/metallb/
    
    log_info "MetalLB deployed successfully"
}

# 메인 배포 함수
main() {
    log_info "Starting libraries deployment..."
    
    # Pre-flight checks
    check_helm
    check_kubectl
    
    # Deploy libraries
    deploy_cert_manager
    deploy_jenkins
    deploy_metallb
    
    log_info "All libraries deployed successfully!"
    
    # Show deployment status
    echo
    log_info "Deployment Status:"
    kubectl get pods -n cert-manager
    kubectl get pods -n jenkins
    kubectl get pods -n metallb-system
}

# 메인 함수 실행
main "$@"