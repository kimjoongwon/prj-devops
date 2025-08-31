#!/bin/bash

# Deploy All Components Script
# This script orchestrates the deployment of libraries and applications

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT=${1:-staging}

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

log_section() {
    echo
    echo -e "${PURPLE}=====================================${NC}"
    echo -e "${PURPLE} $1 ${NC}"
    echo -e "${PURPLE}=====================================${NC}"
}

# Show usage
show_usage() {
    echo "Usage: $0 [environment] [options]"
    echo ""
    echo "Environments:"
    echo "  staging      - Deploy to staging environment (default)"
    echo "  production   - Deploy to production environment"
    echo ""
    echo "Options:"
    echo "  --skip-libraries    - Skip library deployment"
    echo "  --libraries-only    - Deploy only libraries"
    echo "  --dry-run          - Perform dry run (production only)"
    echo "  --help             - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Deploy to staging (default)"
    echo "  $0 staging                   # Deploy to staging"
    echo "  $0 production --dry-run      # Dry run for production"
    echo "  $0 staging --skip-libraries  # Skip libraries, deploy app only"
}

# Parse command line arguments
parse_arguments() {
    SKIP_LIBRARIES=false
    LIBRARIES_ONLY=false
    DRY_RUN=false
    
    while [[ $# -gt 1 ]]; do
        case $2 in
            --skip-libraries)
                SKIP_LIBRARIES=true
                shift
                ;;
            --libraries-only)
                LIBRARIES_ONLY=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                export DRY_RUN=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $2"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Validate environment
validate_environment() {
    case "$ENVIRONMENT" in
        staging|stg|stage)
            ENVIRONMENT="staging"
            ;;
        production|prod)
            ENVIRONMENT="production"
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT"
            log_error "Valid environments: staging, production"
            exit 1
            ;;
    esac
    
    log_info "Target environment: $ENVIRONMENT"
}

# Deploy libraries
deploy_libraries() {
    log_section "DEPLOYING LIBRARIES"
    
    if [ ! -f "$SCRIPT_DIR/deploy-libraries.sh" ]; then
        log_error "deploy-libraries.sh not found"
        exit 1
    fi
    
    "$SCRIPT_DIR/deploy-libraries.sh"
    
    log_info "Libraries deployment completed"
}

# Deploy application based on environment
deploy_application() {
    log_section "DEPLOYING APPLICATION TO $ENVIRONMENT"
    
    case "$ENVIRONMENT" in
        staging)
            if [ ! -f "$SCRIPT_DIR/deploy-stg.sh" ]; then
                log_error "deploy-stg.sh not found"
                exit 1
            fi
            "$SCRIPT_DIR/deploy-stg.sh"
            ;;
        production)
            if [ ! -f "$SCRIPT_DIR/deploy-prod.sh" ]; then
                log_error "deploy-prod.sh not found"
                exit 1
            fi
            "$SCRIPT_DIR/deploy-prod.sh"
            ;;
    esac
    
    log_info "Application deployment to $ENVIRONMENT completed"
}

# Show final status
show_final_status() {
    log_section "DEPLOYMENT SUMMARY"
    
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
    echo
    echo "Environment: $ENVIRONMENT"
    echo "Libraries deployed: $([ "$SKIP_LIBRARIES" = "true" ] && echo "No" || echo "Yes")"
    echo "Application deployed: $([ "$LIBRARIES_ONLY" = "true" ] && echo "No" || echo "Yes")"
    
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}Mode: DRY RUN (no actual changes made)${NC}"
    fi
    
    echo
    log_info "🎉 All components deployed successfully to $ENVIRONMENT!"
    
    if [ "$ENVIRONMENT" = "production" ]; then
        echo
        log_warn "📊 Remember to:"
        echo "  - Monitor application metrics"
        echo "  - Check logs for any issues"
        echo "  - Verify all endpoints are working"
        echo "  - Update documentation if needed"
    fi
}

# Health check
perform_health_check() {
    log_section "PERFORMING HEALTH CHECK"
    
    # Check if kubectl is working
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    # Check cert-manager if libraries were deployed
    if [ "$SKIP_LIBRARIES" != "true" ]; then
        log_debug "Checking cert-manager..."
        kubectl get pods -n cert-manager -l app.kubernetes.io/name=cert-manager | grep Running || log_warn "cert-manager pods not running"
    fi
    
    # Check application based on environment
    case "$ENVIRONMENT" in
        staging)
            NAMESPACE="stg"
            ;;
        production)
            NAMESPACE="prod"
            ;;
    esac
    
    if [ "$LIBRARIES_ONLY" != "true" ]; then
        log_debug "Checking application in $NAMESPACE namespace..."
        kubectl get pods -n "$NAMESPACE" | grep Running || log_warn "Application pods not running in $NAMESPACE"
    fi
    
    log_info "Health check completed"
}

# Main function
main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Validate environment
    validate_environment
    
    # Show deployment plan
    log_section "DEPLOYMENT PLAN"
    echo "Environment: $ENVIRONMENT"
    echo "Deploy libraries: $([ "$SKIP_LIBRARIES" = "true" ] && echo "No" || echo "Yes")"
    echo "Deploy application: $([ "$LIBRARIES_ONLY" = "true" ] && echo "No" || echo "Yes")"
    echo "Dry run: $([ "$DRY_RUN" = "true" ] && echo "Yes" || echo "No")"
    
    # Confirmation for production
    if [ "$ENVIRONMENT" = "production" ] && [ "$DRY_RUN" != "true" ]; then
        echo
        log_warn "⚠️  PRODUCTION DEPLOYMENT ⚠️"
        read -p "Are you sure you want to deploy to production? (type 'yes'): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    # Deploy libraries first (if not skipped)
    if [ "$SKIP_LIBRARIES" != "true" ]; then
        deploy_libraries
        
        # If libraries only, stop here
        if [ "$LIBRARIES_ONLY" = "true" ]; then
            log_info "Libraries-only deployment completed"
            exit 0
        fi
        
        # Wait a bit for libraries to be ready
        log_info "Waiting for libraries to be ready..."
        sleep 30
    fi
    
    # Deploy application (if not libraries-only)
    if [ "$LIBRARIES_ONLY" != "true" ]; then
        deploy_application
    fi
    
    # Health check
    if [ "$DRY_RUN" != "true" ]; then
        perform_health_check
    fi
    
    # Show final status
    show_final_status
}

# Handle help request
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
fi

# Run main function
main "$@"