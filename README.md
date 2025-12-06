# DevOps 프로젝트 - Kubernetes 배포 자동화

GitOps 기반의 Kubernetes 배포 인프라로, Helm과 ArgoCD를 활용한 선언적 배포를 지원합니다.

## 🌟 프로젝트 개요

현대적인 클라우드 네이티브 애플리케이션 배포를 위한 완전한 Infrastructure as Code (IaC) 솔루션입니다.

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
│   │   ├── plate-api/             # Plate API 백엔드
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
│           ├── plate-api-stg.yaml
│           ├── plate-api-prod.yaml
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
  - 예: `plate-api`, `plate-web`, `plate-llm`
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

# ESC(External Secrets Controller) 설정
./scripts/openbao/setup-esc.sh

# 정책 생성
./scripts/openbao/create-policy.sh

# 시크릿 생성
./scripts/openbao/create-secrets.sh

# 토큰 생성
./scripts/openbao/create-token.sh
```

### Harbor 프라이빗 레지스트리

컨테이너 이미지 보안 관리:

```bash
# Harbor 인증 설정
./scripts/deploy-harbor-auth.sh

# Harbor 인증 검증
./scripts/verify-harbor-auth.sh

# 이미지 마이그레이션
./scripts/migrate-images-to-harbor.sh
```

### 보안 기능

- **비루트 컨테이너**: 모든 컨테이너 비루트 실행
- **ReadOnly 파일시스템**: 가능한 경우 적용
- **리소스 제한**: Requests/Limits 강제
- **SSL/TLS**: cert-manager 자동 인증서 관리
- **시크릿 암호화**: OpenBao를 통한 중앙 관리
- **이미지 검증**: Harbor 레지스트리 스캔

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

- **Staging**: https://stg.cocdev.co.kr
- **Production**: https://cocdev.co.kr

### 관리 도구 접속

- **ArgoCD**: https://argocd.cocdev.co.kr
- **Harbor**: https://harbor.cocdev.co.kr
- **Grafana**: https://grafana.cocdev.co.kr
- **Prometheus**: https://prometheus.cocdev.co.kr
- **Kubernetes Dashboard**: https://dashboard.cocdev.co.kr

## 🔄 운영 절차

### Cluster Services & Development Tools

**관리 방식**:
- 설정: 각 차트의 `values.yaml`에서 관리
- 배포: 스크립트 또는 Helm CLI 사용
- 형상 관리: Git 커밋으로 이력 관리

**변경 절차**:
1. `values.yaml` 수정
2. Pull Request 및 리뷰
3. 스테이징 적용 및 검증
4. 프로덕션 적용

**검증**:
```bash
# 린트
helm lint helm/development-tools/<차트명>

# 템플릿 렌더링 확인
helm template <차트명> helm/development-tools/<차트명>
```

### Plate Applications

**관리 방식**:
- 환경별 values 파일로 설정 관리
- ArgoCD를 통한 자동 배포
- Git이 단일 진실 원천(Single Source of Truth)

**변경 절차**:
1. **스테이징**: `values-stg.yaml` 수정 → PR/리뷰 → ArgoCD 동기화 → 검증
2. **프로덕션**: 검증 완료 후 `values-prod.yaml` 반영 → ArgoCD 동기화

**검증**:
```bash
# 린트
helm lint helm/applications/<서비스명>

# 스테이징 렌더링
helm template <서비스명> helm/applications/<서비스명> \
  -f helm/applications/<서비스명>/values-stg.yaml

# 프로덕션 렌더링
helm template <서비스명> helm/applications/<서비스명> \
  -f helm/applications/<서비스명>/values-prod.yaml
```

**롤백**:
```bash
# Git에서 이전 커밋으로 되돌리기
git revert <commit-hash>
git push

# ArgoCD가 자동으로 이전 상태로 동기화
```

## 🐛 트러블슈팅

### 일반적인 문제

**1. ArgoCD 동기화 실패**
```bash
# Application 상태 확인
kubectl get application -n argocd <app-name>

# 상세 로그 확인
kubectl describe application -n argocd <app-name>

# 수동 동기화
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"operation":{"sync":{}}}'
```

**2. 인증서 문제**
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

# DNS 확인
nslookup <domain>

# Ingress Controller 로그
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

**4. Pod 문제**
```bash
# Pod 상태 확인
kubectl get pods -n <namespace>

# 로그 확인
kubectl logs -n <namespace> <pod-name>

# 이벤트 확인
kubectl describe pod -n <namespace> <pod-name>
```

**5. 시크릿 동기화 문제**
```bash
# ExternalSecret 상태 확인
kubectl get externalsecrets -A

# SecretStore 상태 확인
kubectl get secretstores -A

# OpenBao 연결 확인
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

## 🎯 모범 사례

### 프로덕션 배포

1. **항상 드라이런 먼저 실행**
2. **스테이징에서 충분한 검증**
3. **점검 창 또는 저부하 시간대 적용**
4. **배포 직후 모니터링**
5. **롤백 계획 준비**

### 보안

1. **시크릿은 절대 Git에 커밋하지 않음**
2. **OpenBao를 통해 중앙 관리**
3. **Harbor를 통한 이미지 스캔**
4. **최소 권한 원칙 적용**
5. **정기적인 보안 업데이트**

### 백업

- **Helm Release History**: 자동 보관
- **Git 이력**: 모든 변경사항 추적
- **볼륨 스냅샷**: 정기적인 데이터 백업

## 🔧 확장 및 커스터마이징

### 새 애플리케이션 추가

1. `helm/applications/` 아래 새 차트 생성
2. 표준 템플릿 구조 적용 (deployment, service, _helpers.tpl)
3. 환경별 values 파일 작성
4. ArgoCD Application 정의 생성
5. App-of-Apps에 등록 (자동 감지됨)

### 새 환경 추가

1. `environments/` 아래 새 디렉터리 생성
2. 환경별 ArgoCD Application 정의 작성
3. 필요한 경우 스크립트 수정

### 모니터링 추가

1. Prometheus ServiceMonitor 정의
2. Grafana 대시보드 작성
3. Alertmanager 알림 규칙 설정

## 📚 추가 문서

- [OpenBao 설정 가이드](./scripts/openbao/README.md)
- [Harbor 사용 가이드](./docs/harbor-guide.md) (예정)
- [ArgoCD 운영 가이드](./docs/argocd-guide.md) (예정)

## 🎯 향후 개선 사항

1. **CI/CD 파이프라인 통합**
   - 자동 이미지 빌드 및 배포
   - 자동화된 테스트 실행

2. **고급 모니터링**
   - Distributed Tracing (Jaeger/Tempo)
   - 로그 집계 (Loki/Elasticsearch)

3. **재해 복구**
   - Velero 백업/복구
   - 멀티 클러스터 구성

4. **보안 강화**
   - Policy as Code (OPA/Kyverno)
   - 이미지 서명 검증

5. **운영 자동화**
   - 자동 스케일링 튜닝
   - 비용 최적화
   - SLO/SLI 모니터링

---

**라이센스**: MIT
**관리자**: DevOps Team
**문의**: devops@cocdev.co.kr
