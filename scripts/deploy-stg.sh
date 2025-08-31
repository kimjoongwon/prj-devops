#!/bin/bash

# Deploy Staging Environment Script
# This script deploys the frontend-web application to staging environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="stg"
RELEASE_NAME="fe-web-stg"
CHART_PATH="./helm/applications/fe/web"
VALUES_FILE="./environments/staging/fe-web-values.yaml"
COMMON_VALUES="./environments/shared/common-values.yaml"

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

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
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

# Validate chart
validate_chart() {
    log_info "Validating Helm chart..."
    
    if [ ! -f "$CHART_PATH/Chart.yaml" ]; then
        log_error "Chart.yaml not found in $CHART_PATH"
        exit 1
    fi
    
    helm lint "$CHART_PATH" --values "$VALUES_FILE" --values "$COMMON_VALUES"
    
    log_info "Chart validation passed"
}

# Create namespace if not exists
create_namespace() {
    log_info "Creating namespace: $NAMESPACE"
    
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace "$NAMESPACE" environment=development --overwrite
}

# Deploy application
deploy_app() {
    log_info "Deploying $RELEASE_NAME to $NAMESPACE namespace..."
    
    helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
        --namespace "$NAMESPACE" \
        --values "$COMMON_VALUES" \
        --values "$VALUES_FILE" \
        --wait \
        --timeout=600s
    
    log_info "Deployment completed successfully"
}

# Show deployment status
show_status() {
    log_info "Deployment Status:"
    echo
    
    # Show release status
    helm status "$RELEASE_NAME" -n "$NAMESPACE"
    echo
    
    # Show pods
    log_debug "Pods in $NAMESPACE namespace:"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME"
    echo
    
    # Show services
    log_debug "Services in $NAMESPACE namespace:"
    kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME"
    echo
    
    # Show ingresses
    log_debug "Ingresses in $NAMESPACE namespace:"
    kubectl get ingress -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME"
}

# Show access information
show_access_info() {
    log_info "Access Information:"
    echo
    
    # Get ingress information
    INGRESS_HOST=$(kubectl get ingress -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[0].spec.rules[0].host}')
    ADMIN_HOST=$(kubectl get ingress -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME",app.kubernetes.io/component="admin" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "N/A")
    
    if [ ! -z "$INGRESS_HOST" ] && [ "$INGRESS_HOST" != "null" ]; then
        echo -e "${GREEN}Web Application:${NC} https://$INGRESS_HOST"
    fi
    
    if [ ! -z "$ADMIN_HOST" ] && [ "$ADMIN_HOST" != "null" ] && [ "$ADMIN_HOST" != "N/A" ]; then
        echo -e "${GREEN}Admin Interface:${NC} https://$ADMIN_HOST"
    fi
}

# Main deployment function
main() {
    log_info "Starting staging environment deployment..."
    
    # Pre-flight checks
    check_helm
    check_kubectl
    validate_chart
    
    # Deploy
    create_namespace
    deploy_app
    
    # Show results
    show_status
    show_access_info
    
    log_info "Staging deployment completed successfully!"
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "status")
        show_status
        ;;
    "delete")
        log_warn "Deleting $RELEASE_NAME from $NAMESPACE namespace..."
        helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"
        log_info "Application deleted"
        ;;
    *)
        echo "Usage: $0 [deploy|status|delete]"
        echo "  deploy - Deploy the application (default)"
        echo "  status - Show deployment status"
        echo "  delete - Delete the application"
        exit 1
        ;;
esac