# DevOps 프로젝트 - 프로덕션 레디 Helm 차트

이 프로젝트는 Helm 차트를 사용한 프로덕션 준비된 Kubernetes 배포 구조를 제공하며, 다중 환경 배포를 위해 체계적으로 구성되어 있습니다.

## 🌟 프로젝트 개요

본 DevOps 프로젝트는 현대적인 클라우드 네이티브 애플리케이션 배포를 위한 완전한 Infrastructure as Code (IaC) 솔루션입니다. 

### 주요 특징
- **계층화된 아키텍처**: 클러스터 서비스, 개발 도구, 애플리케이션의 3계층 구조
- **멀티 환경 지원**: 스테이징과 프로덕션 환경의 완전한 분리
- **GitOps 통합**: ArgoCD를 통한 자동화된 배포 파이프라인
- **보안 강화**: 프로덕션급 보안 설정과 인증서 관리
- **자동화된 배포**: 원클릭 배포 스크립트와 롤백 지원

## 📁 프로젝트 구조

```
prj-devops/
├── helm/                           # 배포 계층별로 구성된 모든 Helm 차트
│   ├── cluster-services/          # 계층 1: 클러스터 레벨 인프라 (sync-wave: 1)
│   │   ├── cert-manager/          # SSL/TLS 인증서 관리
│   │   │   ├── Chart.yaml
│   │   │   ├── values.yaml
│   │   │   └── templates/
│   │   ├── metallb/               # 로드 밸런서
│   │   └── nfs-provisioner/       # 스토리지 프로비저너
│   ├── development-tools/         # 계층 2: 개발 및 운영 도구 (sync-wave: 2)
│   │   ├── jenkins/               # CI/CD 서버
│   │   │   ├── Chart.yaml
│   │   │   ├── values.yaml
│   │   │   └── templates/
│   │   ├── argocd/                # GitOps 도구
│   │   ├── harbor/                # 컨테이너 레지스트리
│   │   └── kubernetes-dashboard/  # 클러스터 관리 UI
│   └── applications/              # 계층 3: 비즈니스 애플리케이션 (sync-wave: 3)
│       └── fe/
│           └── web/               # 프론트엔드 웹 애플리케이션 (관리자 포함)
│               ├── Chart.yaml
│               ├── values.yaml
│               └── templates/
│                   ├── deployment.yaml
│                   ├── service.yaml
│                   ├── ingress.yaml
│                   ├── admin/
│                   │   └── admin-ingress.yaml
│                   └── _helpers.tpl
├── environments/                   # 환경별 설정 파일
│   ├── staging/
│   │   └── fe-web-values.yaml     # 스테이징 환경 설정
│   ├── production/
│   │   └── fe-web-values.yaml     # 프로덕션 환경 설정
│   └── shared/
│       └── common-values.yaml     # 공통 설정
├── scripts/                       # 배포 자동화 스크립트
│   ├── deploy-all.sh             # 메인 배포 오케스트레이터
│   ├── deploy-libraries.sh       # 클러스터 서비스 및 도구 배포
│   ├── deploy-stg.sh             # 스테이징 배포
│   └── deploy-prod.sh            # 프로덕션 배포 (안전 검사 포함)
└── backup/                       # 원본 파일 백업
    ├── 1-web/
    ├── 4-libs/
    └── helm/
```

## 🚀 빠른 시작

### 사전 준비사항

- Kubernetes 클러스터 접근 권한
- Helm 3.x 설치
- kubectl 설정 완료

### 1. 인프라 및 도구 배포

```bash
# 클러스터 서비스와 개발 도구 배포
./scripts/deploy-libraries.sh
```

다음 순서로 배포됩니다:

1. **클러스터 서비스** (계층 1): cert-manager, MetalLB, NFS 프로비저너
2. **개발 도구** (계층 2): Jenkins, ArgoCD, Harbor, Kubernetes 대시보드

### 2. 애플리케이션 배포

#### 스테이징 환경

```bash
# 스테이징 환경에 배포
./scripts/deploy-stg.sh

# 또는 메인 스크립트 사용
./scripts/deploy-all.sh staging
# 또는 간단하게 (기본값이 스테이징)
./scripts/deploy-all.sh
```

#### 프로덕션 환경

```bash
# 먼저 드라이런 실행 (권장)
./scripts/deploy-all.sh production --dry-run

# 프로덕션 배포
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
- **Applications**: Business logic applications (fe/web)

### Environment Values

- **shared/common-values.yaml**: Common settings across all environments
- **staging/fe-web-values.yaml**: Staging environment configuration
- **production/fe-web-values.yaml**: Production environment configuration

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
kubectl logs -n <namespace> -l app.kubernetes.io/name=fe-web

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

- **Original `1-web/`** → **`helm/applications/fe/web/`** (Helm templated)
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
