# DevOps 프로젝트 - Kubernetes 배포 자동화

GitOps 기반의 Kubernetes 배포 인프라로, Helm과 ArgoCD를 활용한 선언적 배포를 지원합니다.

## 🌟 프로젝트 개요

본 DevOps 프로젝트는 현대적인 클라우드 네이티브 애플리케이션 배포를 위한 완전한 Infrastructure as Code (IaC) 솔루션입니다.

### 주요 특징

- **계층화된 아키텍처**: 클러스터 서비스, 개발 도구, 애플리케이션의 3계층 구조
- **운영 정책 분리**: stg/prod 매니페스트는 유지하되, 기본 GitOps 경로는 prod-only로 운영
- **GitOps 통합**: ArgoCD를 통한 자동화된 배포 파이프라인
- **보안 강화**: OpenBao 시크릿 관리 및 Harbor 프라이빗 레지스트리
- **표준화된 구조**: 통일된 Helm 차트 패턴 및 명명 규칙

## 📌 현재 운영 모드 (2026-03-17)

- **도메인: 2026-09-18부터 `onjitda.com` (Cloudflare Tunnel)로 전환** 완료. 구 도메인(cocdev.co.kr)은 만료 전이라도 미해석 상태이며 전환 기간 없음. 복구/운영 절차: `docs/onjitda-recovery-runbook.md`
- Production Parent Application: `frontend-web-apps` (`argocd` namespace)
- Staging 매니페스트는 `environments/argocd/apps/*-stg.yaml`에만 유지하며, 별도 Parent Application은 운영하지 않습니다.
- Git 경로: `environments/argocd/apps`
- Production 모드: `prod only` (`environments/argocd/app-of-apps.yaml`)
- 변경 감지: GitHub Webhook + 폴링(`timeout.reconciliation: 60s`, 웹훅 끊김 시 감지 지연 상한)
- 운영 가이드: `docs/argocd-prod-only-webhook-manual.md`
- Jenkins 연계 가이드: `docs/jenkins-gitops-image-bump.md`
- Jenkinsfile 예시: `scripts/jenkins/Jenkinsfile.gitops-prod-example.groovy`
- 도구 chart 소스 정책: `helm/development-tools/README.md`

## ⚠️ 현재 운영 제약 (2026-03-17)

- staging child manifest는 repo에 존재하더라도 기본 운영 경로에서는 apply되지 않습니다.
- Staging IDP는 `idp-stg.onjitda.com` DNS와 OpenBao 시크릿 patch가 끝나야 정상 동작합니다.
- IDP 앱 정상화 선행 조건 — 아래 이미지가 각 앱 `values-prod.yaml`의 `image.tag`와 동일한 태그로 Harbor에 존재해야 함 (태그는 빌드 커밋 SHA 앞 12자 컨벤션):
  - `harbor.onjitda.com/prod/proposal-web`
  - `harbor.onjitda.com/stg/proposal-web`
  - `harbor.onjitda.com/prod/idp-api`
  - `harbor.onjitda.com/prod/idp-web`
  - `harbor.onjitda.com/stg/idp-api`
  - `harbor.onjitda.com/stg/idp-web`
- 이미지 미존재 시 `ImagePullBackOff`가 발생하며 ArgoCD 앱은 `Synced`여도 `Healthy`가 되지 않습니다.

## 📁 프로젝트 구조

```
prj-devops/
├── helm/                           # 모든 Helm 차트
│   ├── cluster-services/          # 계층 1: 클러스터 레벨 인프라
│   │   ├── cert-manager/          # SSL/TLS 인증서 관리
│   │   ├── metallb/               # 로드 밸런서
│   │   └── nfs-provisioner/       # 스토리지 프로비저너
│   ├── development-tools/         # 계층 2: 개발 및 운영 도구
│   │   ├── README.md              # upstream chart/values 관리 기준
│   │   ├── grafana/               # GitOps로 관리하는 Grafana 차트
│   │   ├── otel-collector/        # GitOps로 관리하는 OTel Collector 차트
│   │   ├── tempo/                 # GitOps로 관리하는 Tempo 차트
│   │   ├── argocd/                # upstream Argo CD values only
│   │   ├── harbor/                # upstream Harbor values only
│   │   ├── jenkins/               # upstream Jenkins values only
│   │   ├── openbao/               # upstream OpenBao values only
│   │   ├── openebs/               # upstream OpenEBS values only
│   │   └── prometheus/            # upstream Prometheus values only
│   ├── applications/              # 계층 3: Plate 애플리케이션
│   │   ├── core-api/          # Core API 백엔드
│   │   │   ├── Chart.yaml
│   │   │   ├── values.yaml        # 기본 설정
│   │   │   ├── values-stg.yaml    # 스테이징 오버라이드
│   │   │   ├── values-prod.yaml   # 프로덕션 오버라이드
│   │   │   └── templates/
│   │   ├── admin-web/             # Admin 웹 프론트엔드
│   │   │   ├── Chart.yaml
│   │   │   ├── values.yaml
│   │   │   ├── values-stg.yaml
│   │   │   ├── values-prod.yaml
│   │   │   └── templates/
│   │   ├── proposal-web/          # 퍼블릭 제안 웹 프론트엔드
│   │   │   ├── Chart.yaml
│   │   │   ├── values.yaml
│   │   │   ├── values-stg.yaml
│   │   │   ├── values-prod.yaml
│   │   │   └── templates/
│   │   ├── spring-api/            # Spring API 백엔드
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
│   │   ├── idp-api/               # IDP API 백엔드
│   │   │   ├── Chart.yaml
│   │   │   ├── values.yaml
│   │   │   ├── values-stg.yaml
│   │   │   ├── values-prod.yaml
│   │   │   └── templates/
│   │   ├── idp-web/               # IDP Web 프론트엔드
│   │   │   ├── Chart.yaml
│   │   │   ├── values.yaml
│   │   │   ├── values-stg.yaml
│   │   │   ├── values-prod.yaml
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
│       ├── openbao-secrets-manager/          # 앱 레벨 OpenBao 시크릿 동기화
│       │   ├── Chart.yaml
│       │   ├── values-staging.yaml
│       │   ├── values-production.yaml
│       │   └── templates/
│       └── openbao-cluster-secrets-manager/  # 클러스터 공통 OpenBao 시크릿 동기화
│           ├── Chart.yaml
│           ├── values.yaml
│           └── templates/
├── environments/                   # ArgoCD 설정
│   └── argocd/
│       ├── app-of-apps.yaml       # Production App of Apps (frontend-web-apps)
│       └── apps/                  # 개별 ArgoCD Application 정의
│           ├── core-api-stg.yaml
│           ├── core-api-prod.yaml
│           ├── admin-web-stg.yaml
│           ├── admin-web-prod.yaml
│           ├── proposal-web-stg.yaml
│           ├── proposal-web-prod.yaml
│           ├── spring-api-stg.yaml
│           ├── spring-api-prod.yaml
│           ├── plate-llm-stg.yaml
│           ├── idp-api-stg.yaml
│           ├── idp-api-prod.yaml
│           ├── idp-web-stg.yaml
│           ├── idp-web-prod.yaml
│           ├── plate-cache.yaml   # 환경 통합 (단일 PVC)
│           ├── ingress-stg.yaml
│           ├── ingress-prod.yaml
│           ├── openbao-secrets-manager-stg.yaml
│           ├── openbao-secrets-manager-prod.yaml
│           └── openbao-cluster-secrets-manager.yaml
└── scripts/                       # 배포 자동화 스크립트
    ├── deploy-all.sh             # 메인 배포 오케스트레이터
    ├── deploy-libraries.sh       # 클러스터 서비스 및 도구 배포
    ├── deploy-stg.sh             # 스테이징 배포
    ├── deploy-prod.sh            # 프로덕션 배포
    ├── rollback.sh               # 앱 이미지 롤백 (bump 커밋 revert)
    ├── deploy-harbor-auth.sh     # Harbor 인증 설정
    ├── verify-harbor-auth.sh     # Harbor 인증 검증
    ├── migrate-images-to-harbor.sh  # Harbor 이미지 마이그레이션
    ├── jenkins/                  # Jenkins 연계 스크립트
    │   ├── update-gitops-image-tag.sh  # values-prod.yaml 이미지 태그 범프 (yq)
    │   ├── Jenkinsfile.gitops-prod-example.groovy  # 파이프라인 예시
    │   └── cleanup-container-builder.sh
    └── openbao/                  # OpenBao 관리 스크립트
        ├── install-vault-cli.sh  # Vault CLI 설치
        ├── setup-esc.sh          # ESC(External Secrets) 설정
        ├── create-policy.sh      # 정책 생성
        ├── create-token.sh       # 토큰 생성
        ├── create-secrets.sh     # 시크릿 생성
        ├── patch-idp-endpoints.sh # IDP 도메인/내부 URL patch
        ├── migrate-infra-secrets.sh # infra 키를 devops/* 로 이관
        ├── migrate-idp-to-idp-api-web.sh # secret/idp -> idp-api,idp-web 마이그레이션
        ├── validate-idp-env-sync.sh # prj-core IDP API env와 OpenBao 키 동기화 점검
        └── revoke-non-root-tokens.sh  # 토큰 폐기
```

## 🏗️ 아키텍처 설계 원칙

### Helm 차트 명명 및 구조 표준

**애플리케이션 차트** (`helm/applications/`):

- 차트명 = 디렉토리명 = 릴리스명 = 컨테이너명
  - 예: `core-api`, `admin-web`, `proposal-web`, `spring-api`, `idp-api`, `idp-web`, `plate-llm`
- 헬퍼 템플릿 단순화: `.Release.Name` 직접 사용
- imagePullSecrets: Harbor 인증을 위한 `harbor-docker-secret` 포함
- Ingress: 별도 차트에서 중앙 관리 (`helm/ingress`)

**환경 구성**:

- `values.yaml`: 기본 설정 및 공통 값
- `values-stg.yaml`: 스테이징 환경 오버라이드
- `values-prod.yaml`: 프로덕션 환경 오버라이드
- 예외: `plate-cache`는 단일 `values.yaml` 사용 (환경 간 공유 리소스)
- `idp-api`, `idp-web`도 `values-stg.yaml`, `values-prod.yaml`을 모두 사용합니다.

### ArgoCD GitOps 전략

**App of Apps 패턴**:

- `environments/argocd/app-of-apps.yaml`: production child 전용 Parent Application
- `environments/argocd/apps/`: 각 서비스별 Application 정의
- 현재 운영 정책:
  - Production Parent: `exclude: "*-stg.yaml"`
  - staging manifest는 정의만 유지하고 기본 GitOps 경로에 포함하지 않음
- 자동 동기화: `prune: true`, `selfHeal: true`
- Sync Wave: 의존성 순서 보장

**배포 흐름**:

1. Git 저장소에 values 파일 수정 및 커밋
2. ArgoCD가 변경 감지 (GitHub webhook 즉시 + 1분 폴링 백업)
3. Helm 템플릿 렌더링 및 매니페스트 생성
4. Kubernetes 리소스 자동 적용
5. 상태 동기화 및 헬스 체크

## 🚀 빠른 시작

### 사전 준비사항

- Kubernetes 클러스터 (v1.25+)
- Helm 3.x
- kubectl 설정 완료
- Git 접근 권한

### 도메인/터널 사전 조건 (onjitda.com)

외부 접근은 Cloudflare Tunnel(remotely-managed)로 제공한다. 클러스터 배포 전 아래 시크릿과 DNS가 준비되어야 한다.

1. **cert-manager DNS-01용 Cloudflare API 토큰 시크릿** (ClusterIssuer가 `cert-manager` namespace에서 참조):

   ```bash
   kubectl -n cert-manager create secret generic cloudflare-dns01-api-token \
     --from-literal=api-token=<onjitda.com Zone DNS:Edit 권한 토큰>
   ```

2. **cloudflared 터널 토큰 시크릿** (Cloudflare Zero Trust에서 터널 생성 후 발급되는 토큰):

   ```bash
   kubectl create namespace cloudflared
   kubectl -n cloudflared create secret generic cloudflared-tunnel-token \
     --from-literal=token=<tunnel token>
   ```

3. **Cloudflare DNS CNAME 레코드**: 각 서비스 호스트(`onjitda.com`, `idp.`, `stg.`, `idp-stg.`, `argocd.`, `harbor.`, `jenkins.`, `grafana.`, `prometheus.`, `openbao.`, `db.onjitda.com`)를 `<tunnel-id>.cfargotunnel.com`으로 CNAME(proxy) 연결한다.
4. **터널 Public Hostname 라우팅**: 위 호스트들을 `https://192.168.0.20:443`(ingress-nginx LB)로 전달한다. 이때 반드시 아래 설정을 함께 지정한다(2026-09-18 검증값):
   - origin: `https://192.168.0.20:443` — HTTP(:80) origin은 ingress의 ssl-redirect와 리다이렉트 루프를 일으킨다
   - `noTLSVerify: true` + `originServerName: onjitda.com` — IP origin은 SNI가 비어 `tls: unrecognized name`으로 거부된다
5. **Harbor 어드민 시크릿 사전 생성** (`helm/development-tools/harbor/values.yaml`의 `existingSecretAdminPassword: harbor-admin` 참조). 없으면 helm upgrade 후 harbor-core 파드가 `CreateContainerConfigError`로 기동 실패한다:

   ```bash
   kubectl -n harbor create secret generic harbor-admin \
     --from-literal=HARBOR_ADMIN_PASSWORD=<harbor admin 비밀번호>
   ```

### 클러스터 재시작 후 복구 (필수 절차)

VM/서버 재부팅 후에는 OpenBao가 봉인 상태로 기동하여 ExternalSecret 전체가 실패한다. 복구 절차는 [docs/onjitda-recovery-runbook.md](docs/onjitda-recovery-runbook.md) 참조. 핵심만 요약하면:

```bash
# 1) VM 기동 (서버 192.168.0.97에서)
cd ~/prj-vagrant-k8s && vagrant up

# 2) OpenBao 봉인 해제 (Unseal Key는 안전한 곳에 보관)
kubectl exec -n openbao openbao-0 -- bao operator unseal <UNSEAL_KEY>
```

### 1. 인프라 및 도구 배포

```bash
# 클러스터 서비스와 개발 도구 배포
./scripts/deploy-libraries.sh
```

배포 순서:

1. **Cluster Services**: cert-manager, MetalLB
2. **Development Tools**: Grafana/Tempo/OTel은 GitOps, 나머지 운영 도구는 upstream chart + repo values 조합으로 관리

### 2. 애플리케이션 배포

> 현재 기본 GitOps 경로는 production only 입니다. staging manifest는 repo에 유지하지만 자동 배포하지 않습니다.

#### 프로덕션 환경

```bash
# 1) OpenBao 값 확인
./scripts/openbao/patch-idp-endpoints.sh production dry-run

# 2) OpenBao patch 적용
./scripts/openbao/patch-idp-endpoints.sh production apply

# 드라이런 실행 (권장)
./scripts/deploy-all.sh production --dry-run

# 프로덕션 배포
./scripts/deploy-all.sh production
```

#### IDP 동기화 점검 (권장)

```bash
# 1) Helm 값/시크릿 규칙 점검
./scripts/helm-sync-check.sh

# 2) prj-core IDP API env.example vs OpenBao(idp-api/production) 키 드리프트 점검
./scripts/openbao/validate-idp-env-sync.sh production
```

#### IDP 배포 상태 점검

```bash
# ArgoCD 앱 상태
kubectl -n argocd get applications idp-api-stg idp-web-stg idp-api-prod idp-web-prod \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status

# 이미지 pull 실패 확인
kubectl -n plate-prod get pods | rg 'idp-(api|web)-prod'
kubectl -n plate-stg get pods | rg 'idp-(api|web)-stg'
```

## 🔧 환경 설정

### Staging (개발/테스트)

- **Domain**: `stg.onjitda.com`
- **Namespace**: 서비스별 분리
- **Certificate**: Let's Encrypt Staging
- **Auto-scaling**: 활성화
- **Resources**: 개발 친화적 설정

### Production

- **Domain**: `onjitda.com`, `www.onjitda.com`
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

# 인프라 공통 키(AWS 등) 이관
./scripts/openbao/migrate-infra-secrets.sh all

# 라이브러리(인프라 + 도구)만 배포
./scripts/deploy-all.sh staging --libraries-only

# 라이브러리는 건너뛰고 애플리케이션만 배포
./scripts/deploy-all.sh staging --skip-libraries

# 프로덕션 드라이런(검증용, 실제 적용 X)
./scripts/deploy-all.sh production --dry-run
```

OpenBao 경로 원칙:
- 애플리케이션별: `secret/core-api/<env>`, `secret/idp-api/<env>`, `secret/idp-web/<env>`
- 인프라 공통: `secret/devops/<env>` (예: `OBJECT_STORAGE_ACCESS_KEY`, `OBJECT_STORAGE_SECRET_KEY`, `OBJECT_STORAGE_BUCKET`)

### deploy-libraries.sh

클러스터 공통 부트스트랩(cert-manager, Jenkins, MetalLB)을 배포:

- **1계층 (Cluster Services)**: cert-manager, MetalLB
- **2계층 (Development Tools)**: Jenkins

관리 원칙:

- 로컬 chart가 꼭 필요한 경우만 repo에 유지합니다. 현재 `grafana`, `otel-collector`, `tempo`만 해당합니다.
- upstream chart를 쓰는 도구는 repo에 chart 전체를 vendor하지 않고 `values.yaml`만 유지합니다.
- 부트스트랩 배포는 `./scripts/deploy-libraries.sh` 또는 Helm CLI(`helm upgrade --install <repo/chart> -f values.yaml`)로 수행합니다.

### Cluster Services & Development Tools 운영 원칙

- 차트 값 관리:
  - 로컬 chart: `helm/<영역>/<차트>/values*.yaml`
  - upstream chart: `helm/development-tools/<도구>/values.yaml`
- 배포 방식: 스크립트(`./scripts/deploy-libraries.sh`) 또는 Helm CLI(`helm upgrade --install`)로 수행합니다
- 변경 절차:
  - `values.yaml` 수정 → Pull Request/리뷰 → 스테이징 적용 → 프로덕션 적용
- 권장 검사:
  - 로컬 chart 린트: `helm lint helm/development-tools/<차트>`
  - upstream chart 렌더 확인: `helm template <release> <repo/chart> --version <version> -f helm/development-tools/<도구>/values.yaml`

### Applications 운영 원칙

- 관리 원칙:
  - 각 애플리케이션 차트는 서비스 운영 모드에 맞는 values 파일을 보관합니다 (`values-stg.yaml`, `values-prod.yaml` 또는 단일 `values.yaml`)
  - ArgoCD Application은 차트 경로(`helm/applications/<서비스>`)와 해당 환경 values만 지정하여 배포합니다
- 변경 절차:
  - 스테이징: `values-stg.yaml` 수정 → PR/리뷰 → ArgoCD 동기화로 적용 → 검증
  - 프로덕션: 검증 완료 후 `values-prod.yaml` 반영 → ArgoCD 동기화로 적용
  - CI 자동 반영: Jenkins 빌드/Harbor push 성공 → `scripts/jenkins/update-gitops-image-tag.sh`(yq 기반)로 `values-prod.yaml` 태그 자동 커밋/푸시
  - 이미지 태그 컨벤션: 빌드 커밋 **SHA 앞 12자** (immutable, Git 커밋과 1:1 추적). 범프 스크립트는 yq 기반이며 에이전트에 yq가 없으면 `scripts/jenkins/install-yq.sh`가 핀된 버전을 자동 설치
  - Jenkins의 `gitops-prod-image-bump` 잡은 `helm/development-tools/jenkins/values.yaml` 의 `JCasC + Job DSL`로 형상 관리
  - 템플릿(templates/\*.yaml) 변경 시 반드시 린트/렌더 확인 수행
- 권장 검사:
  - 린트: `helm lint helm/applications/<서비스>`
  - 렌더 확인(스테이징): `helm template helm/applications/<서비스> -f helm/applications/<서비스>/values-stg.yaml`
  - 렌더 확인(프로덕션): `helm template helm/applications/<서비스> -f helm/applications/<서비스>/values-prod.yaml`
- 롤백:
  - 앱 이미지 롤백: `./scripts/rollback.sh --app <앱명>` — 최신 bump 커밋(`ci(gitops): bump ...`)을 revert+push, ArgoCD가 자동 재배포 (먼저 `--dry-run`으로 결과 확인 권장)
  - 그 외 변경: Git에서 이전 커밋으로 되돌린 뒤 ArgoCD 재동기화(실제 상태는 Git이 단일 진실 원천)

### deploy-stg.sh

레거시 스테이징 배포 스크립트입니다. 현재는 staging Parent Application을 운영하지 않으며, 필요 시에만 별도 절차로 수동 검증용 배포를 수행합니다.

기존 스크립트 특징:

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
- 운영 도구 관리자 비밀번호는 Git에 커밋하지 않고 기존 Secret 또는 운영 시 주입값으로 관리
- Jenkins agent는 전용 ServiceAccount를 사용하고 토큰 자동 마운트를 기본 비활성화

### 인증서 관리

- cert-manager 기반 자동 SSL/TLS 발급
- Let’s Encrypt 통합 (Staging / Production 분리)
- Staging 환경: 시험용 인증서 사용
- Production 환경: 실서명 인증서 적용

## 📊 운영 및 모니터링

### 배포 상태 확인

```bash
# 프로덕션 상태 확인
kubectl -n argocd get applications frontend-web-apps proposal-web-prod idp-api-prod idp-web-prod admin-web-prod core-api-prod plate-ingress-prod openbao-secrets-manager-prod

# ArgoCD를 통한 확인
kubectl get applications -n argocd

# Pod 상태 확인
kubectl get pods -A
```

### 애플리케이션 접속

배포 완료 후 접근 URL:

- **Staging**: https://stg.onjitda.com
- **Staging IDP**: https://idp-stg.onjitda.com
- **Production**: https://onjitda.com 또는 https://www.onjitda.com
- **Production IDP**: https://idp.onjitda.com

## 🗂️ File Organization

### 계층 구조 요약

- **Cluster Services**: 클러스터 레벨 인프라 구성요소
- **Development Tools**: CI/CD, 레지스트리, 대시보드 등 운영 도구
- **Applications**: 비즈니스 로직(프론트/백엔드) 애플리케이션

### 환경별 Values 파일

- Plate 애플리케이션: 각 차트 디렉토리의 환경별 파일을 사용합니다
  - 스테이징: `helm/applications/<서비스>/values-stg.yaml` (예: `core-api/values-stg.yaml`, `admin-web/values-stg.yaml`, `proposal-web/values-stg.yaml`, `spring-api/values-stg.yaml`)
  - 프로덕션: `helm/applications/<서비스>/values-prod.yaml` (예: `core-api/values-prod.yaml`, `admin-web/values-prod.yaml`, `proposal-web/values-prod.yaml`, `spring-api/values-prod.yaml`, `idp-api/values-prod.yaml`, `idp-web/values-prod.yaml`)
- 인프라/도구:
  - 로컬 chart: `helm/cluster-services/*/values.yaml`, `helm/development-tools/grafana/values.yaml`
  - upstream chart values: `helm/development-tools/<도구>/values.yaml`

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
  name: plate-cache
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/kimjoongwon/prj-devops
    path: helm/applications/plate-cache
    targetRevision: main
    helm:
      valueFiles:
        - values.yaml
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

참고: Cluster Services는 로컬 chart로 관리하고, Development Tools는 `grafana/tempo/otel-collector`만 로컬 chart를 유지합니다. 그 외 운영 도구는 upstream chart + repo `values.yaml` 조합으로 관리합니다.

### 장점 요약

- **명확한 계층 분리**: 인프라(cluster-services) / 도구(development-tools) / 앱(applications)의 책임 경계 명확
- **경로 일관성**: 모든 차트를 `helm/` 트리 하위에 배치 → ArgoCD 설정 단순화
- **환경별 설정 관리**: `environments/` 디렉토리에서 스테이징/프로덕션 values 중앙 관리
- **GitOps 통합**: ArgoCD를 통한 선언적 배포 및 자동 동기화
- **멀티 애플리케이션 지원**: core-api, admin-web, proposal-web, spring-api, plate-llm, plate-cache, idp-api, idp-web 통합 관리

### ArgoCD Application 구조

이 프로젝트는 ArgoCD의 App-of-Apps 패턴을 활용하여 모든 애플리케이션을 관리합니다:

- **App of Apps**: `environments/argocd/app-of-apps.yaml`이 production child를 관리
- **개별 Application**: `environments/argocd/apps/` 디렉토리에 각 서비스별 ArgoCD Application 정의
- **환경 선택**: stg/prod Application 정의는 유지하지만, 현재 Parent App은 `directory.exclude`로 staging을 제외한 prod-only 운영
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

### 2026-09-21

- **이미지 태그 컨벤션 SHA-12 전환 + 롤백 헬퍼**:
  - `update-gitops-image-tag.sh`의 awk YAML 치환을 yq로 교체 (하이픈 키 브래킷 표기, 따옴표 스타일 보존)
  - `scripts/rollback.sh` 추가 — bump 커밋(`ci(gitops): bump ...`) revert 기반 롤백, `--steps N`/`--dry-run` 지원
  - `scripts/jenkins/install-yq.sh` 추가 — 휘발성 Jenkins 에이전트용 yq 부트스트랩(v4.53.6, sha256 핀)
  - prj-core 빌드 Jenkinsfile이 태그를 빌드 커밋 SHA 앞 12자로 생성하도록 전환

### 2025-12-12

- **OpenBao 정책 보안 수정**: `esc-policy.hcl`에 `secret/data/cluster/secrets` 경로 읽기 권한 추가
  - 문제: ClusterExternalSecret이 `cluster/secrets` 경로 접근 시 403 Permission Denied 오류 발생
  - 원인: ESC 정책에 해당 경로에 대한 권한이 누락되어 있었음
  - 해결: `scripts/openbao/policies/esc-policy.hcl`에 cluster 경로 권한 추가 후 정책 업데이트
