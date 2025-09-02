# DevOps Project - Production-Ready Helm Charts

This project provides a production-ready Kubernetes deployment structure using Helm charts, organized for multi-environment deployments.

## 📁 Project Structure

```
prj-devops/
├── helm/                           # All Helm charts organized by deployment layers
│   ├── cluster-services/          # Layer 1: Cluster-level infrastructure (sync-wave: 1)
│   │   ├── cert-manager/          # SSL/TLS certificate management
│   │   │   ├── Chart.yaml
│   │   │   ├── values.yaml
│   │   │   └── templates/
│   │   ├── metallb/               # Load balancer
│   │   └── nfs-provisioner/       # Storage provisioner
│   ├── development-tools/         # Layer 2: Development & Operations tools (sync-wave: 2)
│   │   ├── jenkins/               # CI/CD server
│   │   │   ├── Chart.yaml
│   │   │   ├── values.yaml
│   │   │   └── templates/
│   │   ├── argocd/                # GitOps tool
│   │   ├── harbor/                # Container registry
│   │   └── kubernetes-dashboard/  # Cluster management UI
│   └── applications/              # Layer 3: Business applications (sync-wave: 3)
│       └── frontend/
│           └── web/               # Frontend web application with admin
│               ├── Chart.yaml
│               ├── values.yaml
│               └── templates/
│                   ├── deployment.yaml
│                   ├── service.yaml
│                   ├── ingress.yaml
│                   ├── admin/
│                   │   └── admin-ingress.yaml
│                   └── _helpers.tpl
├── environments/                   # Environment-specific configurations
│   ├── staging/
│   │   └── frontend-web-values.yaml
│   ├── production/
│   │   └── frontend-web-values.yaml
│   └── shared/
│       └── common-values.yaml
├── scripts/                       # Deployment automation
│   ├── deploy-all.sh             # Main deployment orchestrator
│   ├── deploy-libraries.sh       # Cluster services & tools deployment
│   ├── deploy-stg.sh             # Staging deployment
│   └── deploy-prod.sh            # Production deployment (with safety checks)
└── backup/                       # Backup of original files
    ├── 1-web/
    ├── 4-libs/
    └── helm/
```

## 🚀 Quick Start

### Prerequisites

- Kubernetes cluster access
- Helm 3.x installed
- kubectl configured

### 1. Deploy Infrastructure & Tools

```bash
# Deploy cluster services and development tools
./scripts/deploy-libraries.sh
```

This deploys in order:

1. **Cluster Services** (Layer 1): cert-manager, MetalLB, NFS provisioner
2. **Development Tools** (Layer 2): Jenkins, ArgoCD, Harbor, Kubernetes Dashboard

### 2. Deploy Applications

#### Staging Environment

```bash
# Deploy to staging
./scripts/deploy-stg.sh

# Or use the main script
./scripts/deploy-all.sh staging
# or simply (staging is default)
./scripts/deploy-all.sh
```

#### Production Environment

```bash
# Dry run first (recommended)
./scripts/deploy-all.sh production --dry-run

# Deploy to production
./scripts/deploy-all.sh production
```

## 🔧 Environment Configuration

### Staging (Development/Testing)

- **Domain**: `cocdev.co.kr`, `stg.cocdev.co.kr`
- **Certificate**: Let's Encrypt Staging
- **Replicas**: 2
- **Auto-scaling**: Enabled
- **Resources**: Development-friendly
- **SSL**: Optional (HTTP allowed)

### Production

- **Domain**: `cocdev.co.kr`, `www.cocdev.co.kr`
- **Certificate**: Let's Encrypt Production
- **Replicas**: 3+
- **Auto-scaling**: Enabled
- **Security**: Hardened
- **SSL**: Enforced

## 📊 Deployment Scripts

### deploy-all.sh

Main orchestrator script with environment management:

```bash
# Deploy everything to staging (default)
./scripts/deploy-all.sh

# Deploy only libraries
./scripts/deploy-all.sh staging --libraries-only

# Skip libraries, deploy only application
./scripts/deploy-all.sh staging --skip-libraries

# Production dry run
./scripts/deploy-all.sh production --dry-run
```

### deploy-libraries.sh

Deploys infrastructure and development tools in layers:

- **Layer 1 (Cluster Services)**: cert-manager, MetalLB, NFS provisioner
- **Layer 2 (Development Tools)**: Jenkins, ArgoCD, Harbor, Kubernetes Dashboard

### deploy-stg.sh

Staging deployment with features:

- Quick deployment
- Status monitoring
- Easy cleanup: `./deploy-stg.sh delete`

### deploy-prod.sh

Production deployment with safety features:

- Confirmation prompts
- Automatic backup
- Health verification
- Rollback support: `./deploy-prod.sh rollback [revision]`

## 🛡️ Security Features

### Production Security

- Non-root containers
- Read-only root filesystem
- Resource limits enforced
- Network policies (when enabled)
- Admin interface IP restrictions
- SSL/TLS termination

### Certificate Management

- Automatic SSL/TLS certificates via cert-manager
- Let's Encrypt integration
- Staging certificates for dev/staging
- Production certificates for production

## 🔍 Monitoring & Operations

### Deployment Status

```bash
# Check staging status
./scripts/deploy-stg.sh status

# Check production status
./scripts/deploy-prod.sh status
```

### Accessing Applications

After deployment, applications are available at:

- **Staging**: https://cocdev.co.kr or https://stg.cocdev.co.kr
- **Production**: https://cocdev.co.kr or https://www.cocdev.co.kr

## 🗂️ File Organization

### Layered Architecture

- **Cluster Services**: Infrastructure components that run at cluster level
- **Development Tools**: CI/CD, monitoring, and management tools
- **Applications**: Business logic applications (frontend/web)

### Environment Values

- **shared/common-values.yaml**: Common settings across all environments
- **staging/frontend-web-values.yaml**: Staging environment configuration
- **production/frontend-web-values.yaml**: Production environment configuration

## 🚨 Safety & Best Practices

### Production Deployments

1. Always run dry-run first
2. Verify in staging environment
3. Deploy during maintenance windows
4. Monitor post-deployment
5. Keep rollback plan ready

### Backup Strategy

- Automatic backup before production deployments
- Original files preserved in `backup/` directory
- Helm release history for rollbacks

## 🔧 Customization

### Adding New Environments

1. Create directory in `environments/`
2. Add environment-specific values
3. Update deployment scripts if needed

### Adding New Applications

1. Create chart in `helm/applications/`
2. Add environment-specific values
3. Update deployment scripts

### Modifying Infrastructure

1. Update charts in `helm/cluster-services/` or `helm/development-tools/`
2. Test in staging first
3. Update all environments

## 🐛 Troubleshooting

### Common Issues

1. **Certificate Issues**: Check cert-manager logs
2. **Ingress Issues**: Verify DNS and ingress controller
3. **Pod Issues**: Check resources and limits

### Getting Help

```bash
# Show deployment logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=frontend-web

# Check ingress status
kubectl get ingress -A

# Verify certificates
kubectl get certificates -A
```

## 🔄 ArgoCD Integration

### Layered Deployment Strategy

The new structure supports ArgoCD App-of-Apps pattern with sync-waves:

```yaml
# Example ArgoCD Application for cluster services
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: metallb
  annotations:
    argocd.argoproj.io/sync-wave: "1"  # Deploy first
spec:
  source:
    repoURL: https://github.com/company/prj-devops
    path: helm/cluster-services/metallb
    targetRevision: HEAD

# Example ArgoCD Application for development tools
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: jenkins
  annotations:
    argocd.argoproj.io/sync-wave: "2"  # Deploy after cluster services
spec:
  source:
    repoURL: https://github.com/company/prj-devops
    path: helm/development-tools/jenkins
    targetRevision: HEAD
```

### Benefits

- **Dependency Management**: sync-waves ensure proper deployment order
- **Simple Paths**: All charts under `helm/` for consistent ArgoCD configuration
- **Layer Separation**: Clear separation between infrastructure, tools, and applications

## 📝 Migration Notes

This structure migrates from the original flat YAML structure to a production-ready, layered Helm deployment:

- **Original `1-web/`** → **`helm/applications/frontend/web/`** (Helm templated)
- **Original `4-libs/`** → **`helm/cluster-services/`** (infrastructure layer)
- **Original `helm/`** → **`helm/development-tools/`** (tools layer)
- **Static YAML** → **Helm templates** with environment-specific values
- **Single deployment** → **Layered multi-environment support with ArgoCD sync-waves**

---

## 🎯 Next Steps

1. Set up CI/CD pipeline integration
2. Add monitoring (Prometheus/Grafana)
3. Implement backup strategies
4. Add more comprehensive testing
5. Document runbooks and procedures
