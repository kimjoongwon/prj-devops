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

환경(스테이징/프로덕션) 관리와 선택적 배포 옵션을 제공하는 메인 오케스트레이션 스크립트:

```bash
# (기본값) 스테이징 전체 배포
./scripts/deploy-all.sh

# 라이브러리(인프라 + 도구)만 배포
./scripts/deploy-all.sh staging --libraries-only

# 라이브러리는 건너뛰고 애플리케이션만 배포
./scripts/deploy-all.sh staging --skip-libraries

# 프로덕션 드라이런(검증용, 실제 적용 X)
./scripts/deploy-all.sh production --dry-run
```

### deploy-libraries.sh

인프라 및 개발 도구를 계층 순서대로 배포:

- **1계층 (Cluster Services)**: cert-manager, MetalLB, NFS Provisioner
- **2계층 (Development Tools)**: Jenkins, ArgoCD, Harbor, Kubernetes Dashboard

### deploy-stg.sh

스테이징 전용 배포 스크립트 (특징):

- 빠른 반복 배포
- 상태 모니터링 지원
- 손쉬운 정리: `./deploy-stg.sh delete`

### deploy-prod.sh

프로덕션 안전장치 포함:

- 사용자 확인 프롬프트(오작동 예방)
- 자동 백업 생성
- 헬스 체크 검증
- 롤백 지원: `./deploy-prod.sh rollback [revision]`

## 🛡️ Security Features

### Production 보안 적용 항목

- 비루트(Non-root) 컨테이너 실행
- ReadOnly Root 파일시스템 구성 (가능한 경우)
- 리소스 Requests/Limits 강제
- (옵션) NetworkPolicy로 트래픽 제한
- 관리자 인터페이스 IP 제한(확장 시 적용)
- SSL/TLS 종료 및 강제 HTTPS

### 인증서 관리

- cert-manager 기반 자동 SSL/TLS 발급
- Let’s Encrypt 통합 (Staging / Production 분리)
- Staging 환경: 시험용 인증서 사용
- Production 환경: 실서명 인증서 적용

## 🔍 Monitoring & Operations

### 배포 상태 확인

```bash
# Check staging status
./scripts/deploy-stg.sh status

# Check production status
./scripts/deploy-prod.sh status
```

### 애플리케이션 접속

배포 완료 후 접근 URL:

- **Staging**: https://cocdev.co.kr 또는 https://stg.cocdev.co.kr
- **Production**: https://cocdev.co.kr 또는 https://www.cocdev.co.kr

## 🗂️ File Organization

### 계층 구조 요약

- **Cluster Services**: 클러스터 레벨 인프라 구성요소
- **Development Tools**: CI/CD, 레지스트리, 대시보드 등 운영 도구
- **Applications**: 비즈니스 로직(프론트/백엔드) 애플리케이션

### 환경별 Values 파일

- **shared/common-values.yaml**: 환경 공통 기본값
- **staging/fe-web-values.yaml**: 스테이징 전용 설정
- **production/fe-web-values.yaml**: 프로덕션 전용 설정

## 🚨 Safety & Best Practices

### 프로덕션 배포 모범 절차

1. 항상 드라이런(dry-run) 선 실행
2. 스테이징에서 기능/성능 검증
3. 점검 창(또는 저부하 시간대)에 적용
4. 배포 직후/초기 구간 모니터링
5. 롤백 시나리오 및 이전 리비전 번호 메모

### 백업 전략

- 프로덕션 배포 직전 자동 백업
- 원본/이전 파일 `backup/` 디렉터리에 보존
- Helm Release History 활용한 롤백 지원

## 🔧 Customization

### 새 환경 추가 방법

1. `environments/` 아래 새 디렉터리 생성
2. 환경 전용 values 파일 작성
3. 필요 시 스크립트 분기/조건 추가

### 새 애플리케이션 추가 절차

1. `helm/applications/` 이하 새 차트 생성
2. 환경별 values 파일 작성
3. 스크립트/ArgoCD Application 정의 추가

### 인프라 수정 절차

1. `helm/cluster-services/` 또는 `helm/development-tools/` 내 차트 수정
2. 스테이징 검증 (기능/성능/보안)
3. 프로덕션 반영 및 추적 기록

## 🐛 Troubleshooting

### 빈번한 이슈 & 점검 포인트

1. **인증서 문제**: cert-manager Pod 로그 / Certificate, Order, Challenge 리소스 확인
2. **Ingress 문제**: DNS A/CNAME 레코드 → Ingress Controller LB IP 매칭 여부
3. **Pod 문제**: 리소스 부족(OOMKilled / CrashLoopBackOff) / 이미지 Pull 오류

### 추가 진단 명령 예시

```bash
# Show deployment logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=fe-web

# Check ingress status
kubectl get ingress -A

# Verify certificates
kubectl get certificates -A
```

## 🔄 ArgoCD Integration

### 계층형(App-of-Apps) 배포 전략

이 구조는 ArgoCD App-of-Apps 패턴 및 sync-wave 어노테이션을 활용하여 의존 순서를 보장합니다:

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

### 장점 요약

- **의존성 순서 보장**: sync-wave 로 서비스 초기화 순서 제어
- **경로 일관성**: 모든 차트를 `helm/` 트리 하위에 배치 → ArgoCD 설정 단순화
- **명확한 계층 분리**: 인프라 / 도구 / 앱 코드의 책임 경계 명확

### 마이그레이션 노트

기존 평면(flat) YAML 배포 구조를 프로덕션 지향 계층형 Helm 구조로 전환:

- **기존 `1-web/`** → **`helm/applications/fe/web/`** (Helm 템플릿화)
- **기존 `4-libs/`** → **`helm/cluster-services/`** (인프라 계층)
- **기존 루트 `helm/`** → **`helm/development-tools/`** (도구 계층)
- **정적 YAML** → **환경별 values 지원 Helm 템플릿**
- **단일 배포 흐름** → **ArgoCD sync-wave 기반 다계층/다환경 지원**

---

## 🎯 향후 개선 로드맵

1. CI/CD 파이프라인(빌드/이미지 스캔/배포 자동화) 통합
2. 모니터링 스택(Prometheus/Grafana/Alertmanager) 도입
3. 백업/복구 전략 구현 (예: Velero, 스냅샷)
4. 통합 테스트/부하 테스트 파이프라인 추가
5. 운영 Runbook 및 장애 대응 절차 문서화
