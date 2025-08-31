#!/bin/bash

# Deploy Libraries Script
# This script deploys all library components (Jenkins, Cert-Manager, MetalLB)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if helm is installed
check_helm() {
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed. Please install Helm first."
        exit 1
    fi
}

# Check if kubectl is available
check_kubectl() {
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Unable to connect to Kubernetes cluster."
        exit 1
    fi
}

# Deploy cert-manager
deploy_cert_manager() {
    log_info "Deploying cert-manager..."
    
    # Add jetstack repository
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    
    # Install cert-manager CRDs
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.crds.yaml
    
    # Install cert-manager
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version v1.13.0 \
        --set installCRDs=true
    
    # Wait for cert-manager to be ready
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cert-manager -n cert-manager --timeout=300s
    
    # Install cert-manager configuration
    helm upgrade --install cert-manager-config ./helm/cluster-services/cert-manager \
        --namespace cert-manager \
        --values ./environments/shared/common-values.yaml
    
    log_info "cert-manager deployed successfully"
}

# Deploy Jenkins
deploy_jenkins() {
    log_info "Deploying Jenkins..."
    
    helm upgrade --install jenkins ./helm/development-tools/jenkins \
        --namespace jenkins \
        --create-namespace \
        --values ./environments/shared/common-values.yaml
    
    log_info "Jenkins deployed successfully"
}

# Deploy MetalLB
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

# Main deployment function
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

# Run main function
main "$@"