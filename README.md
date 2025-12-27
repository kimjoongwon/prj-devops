# DevOps 프로젝트 - Kubernetes 배포 자동화

GitOps 기반의 Kubernetes 배포 인프라로, Helm과 ArgoCD를 활용한 선언적 배포를 지원합니다.

## 🌟 프로젝트 개요

본 DevOps 프로젝트는 현대적인 클라우드 네이티브 애플리케이션 배포를 위한 완전한 Infrastructure as Code (IaC) 솔루션입니다.

### 주요 특징

- **계층화된 아키텍처**: 클러스터 서비스, 개발 도구, 애플리케이션의 3계층 구조
- **멀티 환경 지원**: 스테이징과 프로덕션 환경의 완전한 분리
- **GitOps 통합**: ArgoCD를 통한 자동화된 배포 파이프라인
- **보안 강화**: OpenBao 시크릿 관리 및 Harbor 프라이빗 레지스트리
- **표준화된 구조**: 통일된 Helm 차트 패턴 및 명명 규칙

## 📁 프로젝트 구조

```
prj-devops/
├── helm/                           # 모든 Helm 차트
│   ├── cluster-services/          # 계층 1: 클러스터 레벨 인프라
│   │   ├── cert-manager/          # SSL/TLS 인증서 관리
│   │   ├── metallb/               # 로드 밸런서
│   │   └── nfs-provisioner/       # 스토리지 프로비저너
│   ├── development-tools/         # 계층 2: 개발 및 운영 도구
│   │   ├── argocd/                # GitOps 도구
│   │   ├── harbor/                # 컨테이너 레지스트리
│   │   ├── grafana/               # 모니터링 대시보드
│   │   ├── prometheus/            # 메트릭 수집
│   │   ├── promtail/              # 로그 수집 에이전트
│   │   ├── fluentd/               # 로그 수집
│   │   ├── jenkins/               # CI/CD
│   │   ├── openbao/               # 시크릿 관리
│   │   ├── openebs/               # 스토리지 오케스트레이션
│   │   └── kubernetes-dashboard/  # 클러스터 관리 UI
│   ├── applications/              # 계층 3: Plate 애플리케이션
│   │   ├── plate-server/          # Plate Server 백엔드
│   │   │   ├── Chart.yaml
│   │   │   ├── values.yaml        # 기본 설정
│   │   │   ├── values-stg.yaml    # 스테이징 오버라이드
│   │   │   ├── values-prod.yaml   # 프로덕션 오버라이드
│   │   │   └── templates/
│   │   ├── plate-web/             # Plate 웹 프론트엔드
│   │   │   ├── Chart.yaml
│   │   │   ├── values.yaml
│   │   │   ├── values-stg.yaml
│   │   │   ├── values-prod.yaml
│   │   │   └── templates/
│   │   ├── plate-llm/             # Plate LLM 서비스
│   │   │   ├── Chart.yaml
│   │   │   ├── values.yaml
│   │   │   ├── values-stg.yaml
│   │   │   └── templates/
│   │   └── plate-cache/           # 컨테이너 빌드 캐시 PVC
│   │       ├── Chart.yaml
│   │       ├── values.yaml        # 통합 설정 (환경 공통)
│   │       └── templates/
│   ├── ingress/                   # 통합 Ingress 설정
│   │   ├── Chart.yaml
│   │   ├── values-stg.yaml
│   │   ├── values-prod.yaml
│   │   └── templates/
│   └── shared-configs/
│       └── openbao-secrets-manager/  # OpenBao 시크릿 동기화
│           ├── Chart.yaml
│           ├── values-staging.yaml
│           ├── values-production.yaml
│           └── templates/
├── environments/                   # ArgoCD 설정
│   └── argocd/
│       ├── app-of-apps.yaml       # App of Apps 패턴 메인
│       └── apps/                  # 개별 ArgoCD Application 정의
│           ├── plate-server-stg.yaml
│           ├── plate-server-prod.yaml
│           ├── plate-web-stg.yaml
│           ├── plate-web-prod.yaml
│           ├── plate-llm-stg.yaml
│           ├── plate-cache.yaml   # 환경 통합 (단일 PVC)
│           ├── ingress-stg.yaml
│           ├── ingress-prod.yaml
│           ├── openbao-secrets-manager-stg.yaml
│           └── openbao-secrets-manager-prod.yaml
└── scripts/                       # 배포 자동화 스크립트
    ├── deploy-all.sh             # 메인 배포 오케스트레이터
    ├── deploy-libraries.sh       # 클러스터 서비스 및 도구 배포
    ├── deploy-stg.sh             # 스테이징 배포
    ├── deploy-prod.sh            # 프로덕션 배포
    ├── deploy-harbor-auth.sh     # Harbor 인증 설정
    ├── verify-harbor-auth.sh     # Harbor 인증 검증
    ├── migrate-images-to-harbor.sh  # Harbor 이미지 마이그레이션
    └── openbao/                  # OpenBao 관리 스크립트
        ├── install-vault-cli.sh  # Vault CLI 설치
        ├── setup-esc.sh          # ESC(External Secrets) 설정
        ├── create-policy.sh      # 정책 생성
        ├── create-token.sh       # 토큰 생성
        ├── create-secrets.sh     # 시크릿 생성
        └── revoke-non-root-tokens.sh  # 토큰 폐기
```

## 🏗️ 아키텍처 설계 원칙

### Helm 차트 명명 및 구조 표준

**애플리케이션 차트** (`helm/applications/`):

- 차트명 = 디렉토리명 = 릴리스명 = 컨테이너명
  - 예: `plate-server`, `plate-web`, `plate-llm`
- 헬퍼 템플릿 단순화: `.Release.Name` 직접 사용
- imagePullSecrets: Harbor 인증을 위한 `harbor-docker-secret` 포함
- Ingress: 별도 차트에서 중앙 관리 (`helm/ingress`)

**환경 구성**:

- `values.yaml`: 기본 설정 및 공통 값
- `values-stg.yaml`: 스테이징 환경 오버라이드
- `values-prod.yaml`: 프로덕션 환경 오버라이드
- 예외: `plate-cache`는 단일 `values.yaml` 사용 (환경 간 공유 리소스)

### ArgoCD GitOps 전략

**App of Apps 패턴**:

- `environments/argocd/app-of-apps.yaml`: 최상위 Application
- `environments/argocd/apps/`: 각 서비스별 Application 정의
- 자동 동기화: `prune: true`, `selfHeal: true`
- Sync Wave: 의존성 순서 보장

**배포 흐름**:

1. Git 저장소에 values 파일 수정 및 커밋
2. ArgoCD가 변경 감지 (3분 폴링 또는 webhook)
3. Helm 템플릿 렌더링 및 매니페스트 생성
4. Kubernetes 리소스 자동 적용
5. 상태 동기화 및 헬스 체크

## 🚀 빠른 시작

### 사전 준비사항

- Kubernetes 클러스터 (v1.25+)
- Helm 3.x
- kubectl 설정 완료
- Git 접근 권한

### 1. 인프라 및 도구 배포

```bash
# 클러스터 서비스와 개발 도구 배포
./scripts/deploy-libraries.sh
```

배포 순서:

1. **Cluster Services**: cert-manager, MetalLB, NFS 프로비저너
2. **Development Tools**: ArgoCD, Harbor, OpenBao, Prometheus, Grafana 등

### 2. 애플리케이션 배포

#### 스테이징 환경

```bash
# 스테이징 환경에 배포
./scripts/deploy-stg.sh

# 또는 메인 스크립트 사용
./scripts/deploy-all.sh staging
```

#### 프로덕션 환경

```bash
# 드라이런 실행 (권장)
./scripts/deploy-all.sh production --dry-run

# 프로덕션 배포
./scripts/deploy-all.sh production
```

## 🔧 환경 설정

### Staging (개발/테스트)

- **Domain**: `stg.cocdev.co.kr`
- **Namespace**: 서비스별 분리
- **Certificate**: Let's Encrypt Staging
- **Auto-scaling**: 활성화
- **Resources**: 개발 친화적 설정

### Production

- **Domain**: `cocdev.co.kr`, `www.cocdev.co.kr`
- **Namespace**: 서비스별 분리
- **Certificate**: Let's Encrypt Production
- **Auto-scaling**: 활성화
- **Security**: 강화된 보안 정책
- **SSL**: HTTPS 강제

## 🛡️ 보안 및 시크릿 관리

### OpenBao 통합

OpenBao를 통한 중앙화된 시크릿 관리:

```bash
# Vault CLI 설치
./scripts/openbao/install-vault-cli.sh

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
- **2계층 (Development Tools)**: ArgoCD, Harbor, Kubernetes Dashboard

관리 원칙:

- 설정값은 각 차트 디렉토리의 `values.yaml`로 형상 관리 (예: `helm/cluster-services/*/values.yaml`, `helm/development-tools/*/values.yaml`)
- 배포는 `./scripts/deploy-libraries.sh` 또는 Helm CLI(`helm upgrade --install`)로 수행

### Cluster Services & Development Tools 운영 원칙

- 차트 값 관리: 각 차트 디렉토리의 `values.yaml`에 저장하고 Git에 커밋하여 형상 관리합니다
- 배포 방식: 스크립트(`./scripts/deploy-libraries.sh`) 또는 Helm CLI(`helm upgrade --install`)로 수행합니다
- 변경 절차:
  - `values.yaml` 수정 → Pull Request/리뷰 → 스테이징 적용 → 프로덕션 적용
- 권장 검사:
  - 린트: `helm lint helm/development-tools/<차트>` 또는 `helm lint helm/cluster-services/<차트>`
  - 렌더 확인: `helm template helm/development-tools/<차트> -f values.yaml`

### Plate Applications 운영 원칙

- 관리 원칙:
  - 각 애플리케이션 차트(plate-web, plate-server, plate-llm, plate-cache)는 차트 루트에 환경별 values(`values-stg.yaml`, `values-prod.yaml`)를 보관합니다
  - ArgoCD Application은 차트 경로(`helm/applications/<서비스>`)와 해당 환경 values만 지정하여 배포합니다
- 변경 절차:
  - 스테이징: `values-stg.yaml` 수정 → PR/리뷰 → ArgoCD 동기화로 적용 → 검증
  - 프로덕션: 검증 완료 후 `values-prod.yaml` 반영 → ArgoCD 동기화로 적용
  - 템플릿(templates/\*.yaml) 변경 시 반드시 린트/렌더 확인 수행
- 권장 검사:
  - 린트: `helm lint helm/applications/<서비스>`
  - 렌더 확인(스테이징): `helm template helm/applications/<서비스> -f helm/applications/<서비스>/values-stg.yaml`
  - 렌더 확인(프로덕션): `helm template helm/applications/<서비스> -f helm/applications/<서비스>/values-prod.yaml`
- 롤백:
  - Git에서 이전 커밋으로 되돌린 뒤 ArgoCD 재동기화(실제 상태는 Git이 단일 진실 원천)

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

## 📊 운영 및 모니터링

### 배포 상태 확인

```bash
# 스테이징 상태 확인
./scripts/deploy-stg.sh status

# 프로덕션 상태 확인
./scripts/deploy-prod.sh status

# ArgoCD를 통한 확인
kubectl get applications -n argocd

# Pod 상태 확인
kubectl get pods -A
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

- Plate 애플리케이션: 각 차트 디렉토리의 환경별 파일을 사용합니다
  - 스테이징: `helm/applications/<서비스>/values-stg.yaml` (예: `plate-web/values-stg.yaml`, `plate-server/values-stg.yaml`)
  - 프로덕션: `helm/applications/<서비스>/values-prod.yaml` (예: `plate-web/values-prod.yaml`, `plate-server/values-prod.yaml`)
- 인프라/도구(클러스터 서비스, 개발 도구): 각 차트 디렉토리의 `values.yaml`로 형상 관리합니다. 예: `helm/cluster-services/cert-manager/values.yaml`, `helm/development-tools/harbor/values.yaml`

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
# Certificate 리소스 확인
kubectl get certificates -A

# cert-manager 로그 확인
kubectl logs -n cert-manager -l app=cert-manager

# Challenge 상태 확인
kubectl get challenges -A
```

**3. Ingress 문제**

```bash
# Ingress 상태 확인
kubectl get ingress -A

# Verify certificates
kubectl get certificates -A
```

## 🔄 ArgoCD Integration

### 계층형(App-of-Apps) 배포 전략

이 구조는 ArgoCD App-of-Apps 패턴 및 sync-wave 어노테이션을 활용하여 의존 순서를 보장합니다:

```yaml
# Example ArgoCD Application for applications
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: plate-cache-stg
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/kimjoongwon/prj-devops
    path: helm/applications/plate-cache
    targetRevision: main
    helm:
      valueFiles:
        - values-stg.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: devops-tools
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

참고: Cluster Services(예: cert-manager, MetalLB)와 Development Tools(예: Harbor, Grafana)는 Helm 차트의 `values.yaml`로 형상 관리하며, 스크립트 또는 Helm CLI로 배포합니다.

### 장점 요약

- **명확한 계층 분리**: 인프라(cluster-services) / 도구(development-tools) / 앱(applications)의 책임 경계 명확
- **경로 일관성**: 모든 차트를 `helm/` 트리 하위에 배치 → ArgoCD 설정 단순화
- **환경별 설정 관리**: `environments/` 디렉토리에서 스테이징/프로덕션 values 중앙 관리
- **GitOps 통합**: ArgoCD를 통한 선언적 배포 및 자동 동기화
- **멀티 애플리케이션 지원**: plate-web, plate-server, plate-admin, plate-llm, plate-cache 등 Plate 서비스 통합 관리

### ArgoCD Application 구조

이 프로젝트는 ArgoCD의 App-of-Apps 패턴을 활용하여 모든 애플리케이션을 관리합니다:

- **App of Apps**: `environments/argocd/app-of-apps.yaml`이 모든 하위 Application을 관리
- **개별 Application**: `environments/argocd/apps/` 디렉토리에 각 서비스별 ArgoCD Application 정의
- **환경 분리**: 스테이징과 프로덕션 환경이 별도의 Application으로 관리됨
- **Values 오버라이드**: 각 Application은 `helm.valueFiles`를 통해 환경별 설정 적용
- **자동 동기화**: `syncPolicy.automated`로 Git 저장소 변경 시 자동 배포

---

## 🎯 향후 개선 로드맵

1. CI/CD 파이프라인(빌드/이미지 스캔/배포 자동화) 통합
2. 모니터링 스택(Prometheus/Grafana/Alertmanager) 도입
3. 백업/복구 전략 구현 (예: Velero, 스냅샷)
4. 통합 테스트/부하 테스트 파이프라인 추가
5. 운영 Runbook 및 장애 대응 절차 문서화

---

## 📝 변경 이력

### 2025-12-12

- **OpenBao 정책 보안 수정**: `esc-policy.hcl`에 `secret/data/server/cluster` 경로 읽기 권한 추가
  - 문제: ClusterExternalSecret이 `server/cluster` 경로 접근 시 403 Permission Denied 오류 발생
  - 원인: ESC 정책에 해당 경로에 대한 권한이 누락되어 있었음
  - 해결: `scripts/openbao/policies/esc-policy.hcl`에 cluster 경로 권한 추가 후 정책 업데이트
