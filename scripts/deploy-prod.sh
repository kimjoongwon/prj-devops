#!/bin/bash

# Deploy Production Environment Script
# This script deploys the fe-web application to production environment with safety checks

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="fe-web-prod"
RELEASE_NAME="fe-web-prod"
CHART_PATH="./helm/applications/fe/web"
VALUES_FILE="./environments/production/fe-web-values.yaml"
COMMON_VALUES="./environments/shared/common-values.yaml"

# Safety flags
DRY_RUN=${DRY_RUN:-false}
SKIP_BACKUP=${SKIP_BACKUP:-false}

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

# Safety confirmation
confirm_production_deploy() {
    echo
    log_warn "⚠️  PRODUCTION DEPLOYMENT WARNING ⚠️"
    echo
    echo -e "${RED}You are about to deploy to PRODUCTION environment!${NC}"
    echo -e "${RED}This may impact live users and services.${NC}"
    echo
    echo "Release: $RELEASE_NAME"
    echo "Namespace: $NAMESPACE"
    echo "Chart: $CHART_PATH"
    echo
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "DRY RUN MODE - No actual changes will be made"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
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
    
    # Verify we're connected to production cluster
    CLUSTER_NAME=$(kubectl config current-context)
    log_info "Connected to cluster: $CLUSTER_NAME"
    
    if [[ ! "$CLUSTER_NAME" =~ prod|production ]]; then
        log_warn "Cluster name doesn't contain 'prod' or 'production'. Please verify you're connected to the correct cluster."
        read -p "Continue anyway? (y/N): " continue_deploy
        if [[ ! "$continue_deploy" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Validate chart thoroughly
validate_chart() {
    log_info "Performing thorough chart validation..."
    
    if [ ! -f "$CHART_PATH/Chart.yaml" ]; then
        log_error "Chart.yaml not found in $CHART_PATH"
        exit 1
    fi
    
    # Lint the chart
    helm lint "$CHART_PATH" --values "$VALUES_FILE" --values "$COMMON_VALUES"
    
    # Template the chart to check for errors
    helm template "$RELEASE_NAME" "$CHART_PATH" \
        --values "$COMMON_VALUES" \
        --values "$VALUES_FILE" \
        --namespace "$NAMESPACE" > /dev/null
    
    log_info "Chart validation passed"
}

# Backup current deployment
backup_deployment() {
    if [ "$SKIP_BACKUP" = "true" ]; then
        log_info "Skipping backup (SKIP_BACKUP=true)"
        return 0
    fi
    
    log_info "Creating backup of current deployment..."
    
    BACKUP_DIR="./backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup current values
    helm get values "$RELEASE_NAME" -n "$NAMESPACE" > "$BACKUP_DIR/current-values.yaml" 2>/dev/null || log_warn "No existing release to backup"
    
    # Backup current manifests
    helm get manifest "$RELEASE_NAME" -n "$NAMESPACE" > "$BACKUP_DIR/current-manifest.yaml" 2>/dev/null || log_warn "No existing manifests to backup"
    
    log_info "Backup saved to: $BACKUP_DIR"
}

# Create namespace if not exists
create_namespace() {
    log_info "Ensuring namespace: $NAMESPACE"
    
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace "$NAMESPACE" environment=production --overwrite
}

# Deploy application
deploy_app() {
    log_info "Deploying $RELEASE_NAME to $NAMESPACE namespace..."
    
    DEPLOY_ARGS=(
        "$RELEASE_NAME" "$CHART_PATH"
        --namespace "$NAMESPACE"
        --values "$COMMON_VALUES"
        --values "$VALUES_FILE"
        --wait
        --timeout=600s
        --atomic  # Rollback on failure
    )
    
    if [ "$DRY_RUN" = "true" ]; then
        DEPLOY_ARGS+=(--dry-run)
        log_info "DRY RUN: Would execute: helm upgrade --install ${DEPLOY_ARGS[*]}"
    fi
    
    helm upgrade --install "${DEPLOY_ARGS[@]}"
    
    if [ "$DRY_RUN" != "true" ]; then
        log_info "Production deployment completed successfully"
    else
        log_info "DRY RUN completed successfully"
    fi
}

# Verify deployment health
verify_deployment() {
    if [ "$DRY_RUN" = "true" ]; then
        return 0
    fi
    
    log_info "Verifying deployment health..."
    
    # Wait for pods to be ready
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance="$RELEASE_NAME" -n "$NAMESPACE" --timeout=300s
    
    # Check rollout status
    kubectl rollout status deployment -l app.kubernetes.io/instance="$RELEASE_NAME" -n "$NAMESPACE" --timeout=300s
    
    log_info "Deployment verification passed"
}

# Show deployment status
show_status() {
    log_info "Production Deployment Status:"
    echo
    
    # Show release status
    helm status "$RELEASE_NAME" -n "$NAMESPACE"
    echo
    
    # Show pods with more details
    log_debug "Pods in $NAMESPACE namespace:"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" -o wide
    echo
    
    # Show services
    log_debug "Services in $NAMESPACE namespace:"
    kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME"
    echo
    
    # Show ingresses
    log_debug "Ingresses in $NAMESPACE namespace:"
    kubectl get ingress -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME"
    echo
    
    # Show HPA if enabled
    kubectl get hpa -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" 2>/dev/null || true
}

# Show access information
show_access_info() {
    log_info "Production Access Information:"
    echo
    
    # Get ingress information
    INGRESS_HOST=$(kubectl get ingress -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[0].spec.rules[0].host}')
    ADMIN_HOST=$(kubectl get ingress -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME",app.kubernetes.io/component="admin" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "N/A")
    
    if [ ! -z "$INGRESS_HOST" ] && [ "$INGRESS_HOST" != "null" ]; then
        echo -e "${GREEN}🌐 Web Application:${NC} https://$INGRESS_HOST"
        echo -e "${GREEN}🌐 Web Application (www):${NC} https://www.$INGRESS_HOST"
    fi
    
    if [ ! -z "$ADMIN_HOST" ] && [ "$ADMIN_HOST" != "null" ] && [ "$ADMIN_HOST" != "N/A" ]; then
        echo -e "${GREEN}🔧 Admin Interface:${NC} https://$ADMIN_HOST"
    fi
    
    echo
    log_info "🚀 Production deployment is live!"
}

# Main deployment function
main() {
    log_info "Starting PRODUCTION environment deployment..."
    
    # Safety confirmation
    confirm_production_deploy
    
    # Pre-flight checks
    check_helm
    check_kubectl
    validate_chart
    
    # Backup current deployment
    backup_deployment
    
    # Deploy
    create_namespace
    deploy_app
    verify_deployment
    
    # Show results
    show_status
    show_access_info
    
    log_info "🎉 Production deployment completed successfully!"
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "status")
        show_status
        ;;
    "rollback")
        REVISION=${2:-1}
        log_warn "Rolling back $RELEASE_NAME to revision $REVISION..."
        helm rollback "$RELEASE_NAME" "$REVISION" -n "$NAMESPACE"
        log_info "Rollback completed"
        ;;
    "delete")
        log_error "Production deletion must be done manually for safety"
        log_info "If you really need to delete, use: helm uninstall $RELEASE_NAME -n $NAMESPACE"
        exit 1
        ;;
    *)
        echo "Usage: $0 [deploy|status|rollback [revision]]"
        echo "  deploy   - Deploy the application (default)"
        echo "  status   - Show deployment status"
        echo "  rollback - Rollback to previous revision (specify revision number)"
        echo ""
        echo "Environment variables:"
        echo "  DRY_RUN=true      - Perform dry run without actual deployment"
        echo "  SKIP_BACKUP=true  - Skip backup creation"
        exit 1
        ;;
esac