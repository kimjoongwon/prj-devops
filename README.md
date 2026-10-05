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

## 📌 현재 운영 모드 (2026-10-05 갱신)

- **도메인: 2026-09-18부터 `onjitda.com` (Cloudflare Tunnel)로 전환** 완료. 구 도메인(cocdev.co.kr)은 만료 전이라도 미해석 상태이며 전환 기간 없음. 복구/운영 절차: `docs/onjitda-recovery-runbook.md`
- Production Parent Application: `frontend-web-apps` (`argocd` namespace)
- **Staging 재활성화 (2026-10-04)**: 서비스 4앱(core-api·admin-web·idp-api·idp-web) + plate-db·ingress·openbao-secrets-manager가 plate-stg에서 운영 중. 스코프 원칙: proposal-web·tool-storybook·plate-llm 등 서비스가 아닌 구성은 운영만 존재. 상세: `docs/stg-reactivation-runbook.md`
- Git 경로: `environments/argocd/apps`
- Production 모드: `prod + stg` (`environments/argocd/app-of-apps.yaml` — 부모 앱은 부트스트랩 객체이므로 스펙 변경 시 `kubectl apply` 재적용 필요)
- **이미지 태그: prj-deploy 저장소로 분리 (2026-09-27)** — 각 앱 Application은 multi-source로 차트·values는 이 저장소에서, 이미지 태그는 prj-deploy `prod/<앱>.yaml`에서 읽습니다
- 변경 감지: GitHub Webhook(웹훅 시크릿 서명 검증) + 폴링(`timeout.reconciliation: 60s`, 웹훅 끊김 시 감지 지연 상한). 훅 URL은 저장소별로 다르다 — prj-devops는 `https://argocd.onjitda.com/api/webhook`(직접, 현재 정상), prj-deploy는 우회 경로 `https://onjitda.com/api/webhook` (상세: `docs/argocd-prod-only-webhook-manual.md`)
- **관측 스택 전면 GitOps 운영**: Grafana·Loki·Tempo·OTel Collector·Alloy + postgres/redis exporter (모두 `environments/argocd/apps/*-prod.yaml`)
- 운영 가이드: `docs/argocd-prod-only-webhook-manual.md`
- Jenkins 연계 가이드: `docs/jenkins-gitops-image-bump.md`
- Jenkinsfile 예시: `scripts/jenkins/Jenkinsfile.gitops-prod-example.groovy`
- **CI/CD 알림(Buzz)**: 빌드/범프/배포 완료 알림을 Buzz `#cicd` 채널로 — `docs/buzz-ci-integration.md` · [아키텍처 비주얼 가이드](docs/buzz-architecture-visual.md)
- **AI 자율 파이프라인 (Phase 0 완료·Phase 1 구축 완료, 2026-10-05)**: 브랜치 보호(stg/main PR 필수) + pr-agent 리뷰 게이트(클러스터 서비스, 웹훅 `/api/pr-agent/`, LLM=GLM-5.2) 구축 — z.ai 잔액 충전 후 재검증 대기. `docs/ai-autonomous-pipeline.md`
- 도구 chart 소스 정책: `helm/development-tools/README.md`

## ⚠️ 현재 운영 제약 (2026-10-04 갱신)

- 앱 정상화 선행 조건 — **prj-deploy `prod|stg/<앱>.yaml`의 태그**와 동일한 이미지가 Harbor에 존재해야 함 (태그는 빌드 커밋 SHA 앞 12자 컨벤션). 대상: `harbor.onjitda.com/prod/{core-api, admin-web, proposal-web, idp-api, idp-web, tool-storybook}`, `harbor.onjitda.com/stg/{core-api, admin-web, idp-api, idp-web}` (stg는 서비스 앱만 존재)
- 이미지 미존재 시 `ImagePullBackOff`가 발생하며 ArgoCD 앱은 `Synced`여도 `Healthy`가 되지 않습니다.
- 운용 DB(plate-db) Service가 LoadBalancer(5432)로 노출되어 있고 허용 대역(`loadBalancerSourceRanges`)이 비어 있어 내부망 전체에 열려 있음 — 사무실/VPN CIDR 확인 후 `helm/applications/plate-db/values-prod.yaml`에 지정 권장 (2026-10-03 검토, 값 예시 주석 참고)

## 📁 프로젝트 구조

```
prj-devops/
├── helm/                           # 모든 Helm 차트
│   ├── cluster-services/          # 계층 1: 클러스터 레벨 인프라
│   │   ├── cert-manager/          # SSL/TLS 인증서 관리 (upstream + 로컬 config 차트)
│   │   ├── metallb/               # 로드 밸런서
│   │   └── nfs-provisioner/       # 스토리지 프로비저너
│   ├── development-tools/         # 계층 2: 개발 및 운영 도구
│   │   ├── README.md              # upstream chart/values 관리 기준
│   │   ├── alloy/                 # GitOps — 메트릭/로그 수집 에이전트
│   │   ├── grafana/               # GitOps — 모니터링 대시보드
│   │   ├── loki/                  # GitOps — 로그 저장
│   │   ├── otel-collector/        # GitOps — 텔레메트리 파이프라인
│   │   ├── tempo/                 # GitOps — 분산 트레이싱 백엔드
│   │   ├── postgres-exporter/     # GitOps — PostgreSQL 메트릭
│   │   ├── redis-exporter/        # GitOps — Redis 메트릭
│   │   ├── buildkitd/             # BuildKit 데몬 (컨테이너 빌드)
│   │   ├── buzz-gateway/          # CI/CD 알림 게이트웨이 (로컬 관리 차트)
│   │   ├── cloudflared/           # Cloudflare Tunnel (외부 노출)
│   │   ├── argocd/                # upstream values only
│   │   ├── github-runner/         # 미사용(빈 디렉터리만 존재)
│   │   ├── harbor/                # upstream values only
│   │   ├── jenkins/               # upstream values only
│   │   ├── openbao/               # upstream values only
│   │   ├── openebs/               # upstream values only
│   │   └── prometheus/            # upstream values only
│   ├── applications/              # 계층 3: Plate 애플리케이션
│   │   ├── core-api/              # Core API 백엔드
│   │   ├── admin-web/             # Admin 웹 프론트엔드
│   │   ├── proposal-web/          # 퍼블릭 제안 웹 프론트엔드
│   │   ├── idp-api/               # IDP API 백엔드
│   │   ├── idp-web/               # IDP Web 프론트엔드
│   │   ├── tool-storybook/        # Storybook 정적 서비스
│   │   ├── plate-db/              # 클러스터 내 PostgreSQL
│   │   ├── plate-llm/             # Plate LLM 서비스 (운영만 — stg Application 삭제됨, 차트는 유지)
│   │   └── plate-cache/           # 컨테이너 빌드 캐시 PVC
│   ├── ingress/                   # 통합 Ingress + ArgoCD 웹훅 프록시
│   └── shared-configs/
│       ├── openbao-secrets-manager/          # 앱 레벨 OpenBao 시크릿 동기화
│       └── openbao-cluster-secrets-manager/  # 클러스터 공통 OpenBao 시크릿 동기화
├── docker/                         # 자체 서비스 이미지 소스
│   └── buzz-gateway/               # CI/CD 알림 게이트웨이 이미지 (block/buzz CLI 포함)
├── environments/                   # ArgoCD 설정
│   └── argocd/
│       ├── app-of-apps.yaml       # Production App of Apps (frontend-web-apps)
│       └── apps/                  # 개별 ArgoCD Application 정의
│               # prod 앱: admin-web, core-api, idp-api, idp-web,
│               #   proposal-web, tool-storybook, plate-db
│               # prod 관측/인프라: grafana, loki, tempo, otel-collector,
│               #   alloy, postgres-exporter, redis-exporter, cloudflared, buildkitd,
│               #   buzz-gateway
│               # 공용(환경 무관): plate-cache, pgadmin, pgadmin-ingress,
│               #   ingress, openbao-cluster-secrets-manager
│               # stg: admin-web, core-api, idp-api, idp-web,
│               #   plate-db, ingress, openbao-secrets-manager
│               #   (proposal-web/tool-storybook/plate-llm은 운영만 — stg 매니페스트 없음)
└── scripts/                       # 배포 자동화 스크립트
    ├── deploy-libraries.sh       # 클러스터 서비스 및 부트스트랩 도구 배포
    ├── rollback.sh               # 앱 이미지 롤백 (prj-deploy 범프 커밋 revert)
    ├── helm-sync-check.sh        # Helm 값/시크릿 규칙 점검
    ├── get-jenkins-password.sh   # Jenkins 초기 비밀번호 조회
    ├── migrate-images-to-harbor.sh  # Harbor 이미지 마이그레이션 (자격증명은 환경변수로 전달)
    ├── jenkins/                  # Jenkins 연계 스크립트
    │   ├── update-gitops-image-tag.sh  # prj-deploy prod/<앱>.yaml 이미지 태그 범프 (yq)
    │   ├── install-yq.sh         # 휘발성 에이전트용 yq 부트스트랩 (핀 버전)
    │   ├── Jenkinsfile.gitops-prod-example.groovy  # 파이프라인 예시
    │   └── cleanup-container-builder.sh
    └── openbao/                  # OpenBao 관리 스크립트
        ├── install-vault-cli.sh  # Vault CLI 설치
        ├── setup-esc.sh          # ESC(External Secrets) 설정
        ├── create-policy.sh      # 정책 생성
        ├── create-token.sh       # 토큰 생성
        ├── create-secrets.sh     # 시크릿 생성
        ├── put-kv.sh             # KV 쓰기
        ├── renew-token.sh        # 토큰 갱신
        ├── revoke-non-root-tokens.sh  # 토큰 폐기
        ├── patch-idp-endpoints.sh # IDP 도메인/내부 URL patch
        ├── migrate-infra-secrets.sh # infra 키를 devops/* 로 이관
        ├── migrate-server-to-core-api.sh # secret/server -> core-api 마이그레이션
        ├── migrate-idp-to-idp-api-web.sh # secret/idp -> idp-api,idp-web 마이그레이션
        └── validate-idp-env-sync.sh # prj-core IDP API env와 OpenBao 키 동기화 점검
```

> **📝 참고**: 각 애플리케이션 차트는 `values.yaml`(공통) + `values-stg.yaml` / `values-prod.yaml`(환경 오버라이드) 구성입니다. 예외: `plate-cache`는 환경 공유 단일 `values.yaml`, `pgadmin`은 단일 values + 별도 ingress values를 사용합니다.

## 🏗️ 아키텍처 설계 원칙

### 네이밍 규칙 — 도메인(onjitda)과 서비스 코드명(plate)

외부에 노출되는 **도메인/브랜드는 `onjitda.com`** 이고, 클러스터 내부 리소스의 **서비스 코드명은 `plate`** 다.
두 이름은 다르지만 아래 규칙으로 일관되게 사용한다:

| 계층 | 이름 | 예시 |
|---|---|---|
| 외부 도메인 | `onjitda.com` | `onjitda.com`, `idp.onjitda.com`, `stg.onjitda.com` |
| 네임스페이스 | `plate-{env}` | `plate-prod`, `plate-stg` |
| 플랫폼 인프라 앱 | `plate-*` | `plate-db`, `plate-cache`, `plate-llm`, `plate-ingress(-stg)` |
| 데이터베이스 | `plate*` | `plate`(로컬), `plate_prod`, `plate_stg` |
| Harbor 프로젝트 | 환경명 | `prod`, `stg`, `stg-llm`, `devops` |

레거시 이름 흔적(혼용 주의): ingress 리소스명 `cocdev-ingress`(구 도메인 cocdev.co.kr 시절 명명),
prj-core 워크스페이스 스코프 `@cocrepo/*`(구 조직명). 동작에는 영향 없으나 신규 리소스에는
`onjitda`(외부)/`plate`(내부) 규칙을 따른다.

### Helm 차트 명명 및 구조 표준

**애플리케이션 차트** (`helm/applications/`):

- 차트명 = 디렉토리명 = 릴리스명 = 컨테이너명
  - 예: `core-api`, `admin-web`, `proposal-web`, `idp-api`, `idp-web`, `tool-storybook`, `plate-db`, `pgadmin`
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

1. **Cluster Services**: cert-manager(upstream + 로컬 config 차트), MetalLB
2. **Development Tools**: Jenkins — 관측 스택(Grafana/Loki/Tempo/OTel/Alloy/exporters)과 cloudflared/buildkitd는 GitOps 앱으로 관리

### 2. 애플리케이션 배포

> 현재 기본 GitOps 경로는 production only 입니다. staging manifest는 repo에 유지하지만 자동 배포하지 않습니다.

#### 프로덕션 환경

```bash
# 1) OpenBao 값 확인
./scripts/openbao/patch-idp-endpoints.sh production dry-run

# 2) OpenBao patch 적용
./scripts/openbao/patch-idp-endpoints.sh production apply

# 3) GitOps 배포 — 이 저장소에 커밋/푸시하면 ArgoCD가 자동 동기화합니다
#    (웹훅 즉시 반영 + 60초 폴링 백업). 기존 deploy-all.sh 계열 스크립트는
#    참조 경로 소실로 2026-10-03 삭제되었습니다(아래 레거시 노트 참고).
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

- **Domain**: `stg.onjitda.com`, `idp-stg.onjitda.com`
- **Namespace**: `plate-stg`
- **Certificate**: Let's Encrypt `letsencrypt-prod` issuer 공유 (`helm/ingress/values-stg.yaml` — 필요 시 스테이징 issuer로 교체 가능)
- **Replica**: 서비스 4앱 각 1 (고정 — 최소 리소스 운영)
- **Resources**: requests 합계 약 705m/1.8Gi
- **배포 흐름**: Jenkins 앱 빌드 잡 `BRANCH_NAME=stg` 수동 실행 → harbor/stg push + prj-deploy `stg/<앱>.yaml` 자동 범프 → ArgoCD 자동 배포 (prod 전 검증 용도)

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

# 라이브러리(인프라 + 도구) 배포
./scripts/deploy-libraries.sh
```

OpenBao 경로 원칙:
- 애플리케이션별: `secret/core-api/<env>`, `secret/idp-api/<env>`, `secret/idp-web/<env>`
- 데이터/도구: `secret/plate-db/<env>` (ExternalSecret이 plate-db-secrets 소유), `secret/harbor/<env>`, `secret/pgadmin/<env>`
- 인프라 공통: `secret/devops/<env>` (예: `OBJECT_STORAGE_ACCESS_KEY`, `OBJECT_STORAGE_SECRET_KEY`, `OBJECT_STORAGE_BUCKET`)
- OpenBao 감사 로그: `/openbao/data/audit.log` (선언적 audit stanza, 2026-10-04 활성)

### deploy-libraries.sh

클러스터 공통 부트스트랩(cert-manager, Jenkins, MetalLB)을 배포:

- **1계층 (Cluster Services)**: cert-manager, MetalLB
- **2계층 (Development Tools)**: Jenkins

관리 원칙:

- 로컬 chart가 꼭 필요한 경우만 repo에 유지합니다. 현재 `grafana`, `loki`, `tempo`, `otel-collector`, `alloy`, `postgres-exporter`, `redis-exporter`, `cloudflared`, `buildkitd`, `buzz-gateway`가 해당합니다(모두 GitOps로 배포).
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
  - ArgoCD Application은 multi-source로 배포합니다 — 차트 경로(`helm/applications/<서비스>`)와 환경 values는 이 저장소(prj-devops)에서, 이미지 태그는 **prj-deploy**의 `$values/prod/<앱>.yaml`에서 읽습니다 (2026-09-27 분리)
- 변경 절차:
  - 스테이징: `values-stg.yaml` 수정 → PR/리뷰 → ArgoCD 동기화로 적용 → 검증
  - 프로덕션: 검증 완료 후 `values-prod.yaml` 반영 → ArgoCD 동기화로 적용
  - CI 자동 반영: Jenkins 빌드/Harbor push 성공 → `scripts/jenkins/update-gitops-image-tag.sh`(yq 기반)가 **prj-deploy** `prod/<앱>.yaml`에 태그 자동 커밋/푸시 (범프 커밋이 이 저장소 히스토리를 오염시키지 않으며, 배포 기록은 prj-deploy의 git log가 담당)
  - 이미지 태그 컨벤션: 빌드 커밋 **SHA 앞 12자** (immutable, Git 커밋과 1:1 추적). 범프 스크립트는 yq 기반이며 에이전트에 yq가 없으면 `scripts/jenkins/install-yq.sh`가 핀된 버전을 자동 설치
  - Jenkins의 `gitops-prod-image-bump` 잡은 `helm/development-tools/jenkins/values.yaml` 의 `JCasC + Job DSL`로 형상 관리
  - 템플릿(templates/\*.yaml) 변경 시 반드시 린트/렌더 확인 수행
- 권장 검사:
  - 린트: `helm lint helm/applications/<서비스>`
  - 렌더 확인(스테이징): `helm template helm/applications/<서비스> -f helm/applications/<서비스>/values-stg.yaml`
  - 렌더 확인(프로덕션): `helm template helm/applications/<서비스> -f helm/applications/<서비스>/values-prod.yaml`
- 롤백:
  - 앱 이미지 롤백: `./scripts/rollback.sh --app <앱명>` — prj-deploy의 최신 bump 커밋(`ci(gitops): bump ...`)을 revert+push, ArgoCD가 자동 재배포 (먼저 `--dry-run`으로 결과 확인 권장)
  - 그 외 변경: Git에서 이전 커밋으로 되돌린 뒤 ArgoCD 재동기화(실제 상태는 Git이 단일 진실 원천)

### 레거시 배포 스크립트 삭제 (2026-10-03)

`deploy-all.sh`, `deploy-stg.sh`, `deploy-prod.sh`, `deploy-harbor-auth.sh`, `verify-harbor-auth.sh`는 참조하던 차트/환경 경로(`helm/applications/fe/web`, `environments/{staging,production}/` 등)가 저장소 구조 변경으로 사라져 실행 시 항상 실패하는 죽은 스크립트였므로 삭제했다. 앱 배포는 GitOps(ArgoCD) 경로가 단일 채널이며, 라이브러리 배포는 `deploy-libraries.sh`를 사용한다.

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

### 관측 스택 (Observability)

- **메트릭**: Alloy 수집 → Grafana 대시보드. postgres-exporter/redis-exporter로 DB·캐시 메트릭 확보
- **로그**: Alloy 수집 → Loki 저장 → Grafana 탐색
- **트레이스**: 앱 컨테이너에 OTel Node.js 자동계측 주입 → OTel Collector → Tempo → Grafana
- **알림**: Grafana SMTP(ExternalSecret) 이메일 알림, 이벤트 수집·홈 대시보드 구성
- OTel 자동계측은 5개 앱(core-api, admin-web, proposal-web, idp-api, idp-web)에 적용되어 있으며, 계측 이미지는 Docker Hub rate limit 대비 Harbor 미러를 사용합니다
- config 변경 감지: alloy/loki 등은 checksum annotation으로 config 변경 시 자동 롤아웃

### 배포 상태 확인

```bash
# 프로덕션 상태 확인 (앱)
kubectl -n argocd get applications frontend-web-apps core-api-prod admin-web-prod proposal-web-prod idp-api-prod idp-web-prod tool-storybook-prod plate-db-prod plate-ingress-prod openbao-secrets-manager-prod

# 관측/인프라 스택 상태 확인
kubectl -n argocd get applications grafana-prod loki-prod tempo-prod otel-collector-prod alloy-prod postgres-exporter-prod redis-exporter-prod cloudflared-prod

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
  - 스테이징: `helm/applications/<서비스>/values-stg.yaml` (예: `core-api/values-stg.yaml`, `admin-web/values-stg.yaml`, `proposal-web/values-stg.yaml`)
  - 프로덕션: `helm/applications/<서비스>/values-prod.yaml` (예: `core-api/values-prod.yaml`, `admin-web/values-prod.yaml`, `proposal-web/values-prod.yaml`, `idp-api/values-prod.yaml`, `idp-web/values-prod.yaml`)
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

참고: Cluster Services는 로컬 chart로 관리하고, Development Tools는 관측 스택(`grafana/loki/tempo/otel-collector/alloy` + exporter)과 `cloudflared/buildkitd/buzz-gateway`만 로컬 chart(GitOps)로 유지합니다. 그 외 운영 도구(argocd, harbor, jenkins, openbao, openebs, prometheus)는 upstream chart + repo `values.yaml` 조합으로 관리합니다.

### 장점 요약

- **명확한 계층 분리**: 인프라(cluster-services) / 도구(development-tools) / 앱(applications)의 책임 경계 명확
- **경로 일관성**: 모든 차트를 `helm/` 트리 하위에 배치 → ArgoCD 설정 단순화
- **환경별 설정 관리**: `environments/` 디렉토리에서 스테이징/프로덕션 values 중앙 관리
- **GitOps 통합**: ArgoCD를 통한 선언적 배포 및 자동 동기화
- **멀티 애플리케이션 지원**: core-api, admin-web, proposal-web, idp-api, idp-web, tool-storybook, plate-db, plate-cache 통합 관리

### ArgoCD Application 구조

이 프로젝트는 ArgoCD의 App-of-Apps 패턴을 활용하여 모든 애플리케이션을 관리합니다:

- **App of Apps**: `environments/argocd/app-of-apps.yaml`이 production child를 관리
- **개별 Application**: `environments/argocd/apps/` 디렉토리에 각 서비스별 ArgoCD Application 정의
- **환경 선택**: stg/prod Application 정의는 유지하지만, 현재 Parent App은 `directory.exclude`로 staging을 제외한 prod-only 운영
- **Values 오버라이드**: 각 Application은 `helm.valueFiles`를 통해 환경별 설정 적용
- **자동 동기화**: `syncPolicy.automated`로 Git 저장소 변경 시 자동 배포

---

## 🎯 향후 개선 로드맵

1. 이미지 취약점 스캔(Trivy 등) 파이프라인 통합
2. 알림 라우팅 고도화(Alertmanager 도입, 채널 확장) 및 SLO 정의
3. 백업/복구 전략 구현 (예: Velero, 스냅샷)
4. 통합 테스트/부하 테스트 파이프라인 추가
5. 운영 Runbook 커버리지 확대 (현재: 클러스터 복구, 빌드 속도, GitOps 이미지 범프, ArgoCD 웹훅 운영 가이드)

---

## 📝 변경 이력

### 2026-10-04

- **스테이징 재활성화 (prod + stg 운영 전환)**: 서비스 4앱(core-api·admin-web·idp-api·idp-web) + plate-db·ingress·secrets-manager가 plate-stg에서 운영 중. 스코프 원칙(운영만: proposal-web·tool-storybook·plate-llm)에 따라 stg 매니페스트 정리. 이미지 태그는 prod와 동일한 SHA-12 GitOps(prj-deploy `stg/<앱>.yaml` + ArgoCD multi-source). 상세: `docs/stg-reactivation-runbook.md`
- **시크릿 통합 관리 Phase 1**: prod `openbao-token`에서 root 토큰 제거(esc-policy period 토큰으로 교체, stg 동일 패턴), plate-db 비밀번호를 OpenBao KV로 이관하고 `plate-db-secrets`를 ExternalSecret 소유로 전환(수동 시크릿 폐지), OpenBao 감사 로그 활성(선언적 audit stanza), esc-policy를 OpenBao에 실제 적용
- **도구**: `update-gitops-image-tag.sh`/`rollback.sh`에 `--env stg` 지원, stg 범프 커밋(`bump stg/<앱>`)과 prod 롤백 매칭 분리
- **시크릿 통합 Phase 2/3**: 인프라 토큰(harbor-admin·cloudflare dns01/tunnel)을 ClusterExternalSecret으로 이관(기존 시크릿 인계, 값 불변 검증), Harbor `robot$jenkins-ci` 재생성(시크릿 원본 `secret/harbor/jenkins-ci`), buzz-gateway 환경값 `secret/devops/buzz-gateway` 기록, ArgoCD admin 통일값 재설정. grafana-prod 영구 OutOfSync 해소(ESO 기본필드 ignoreDifferences)

### 2026-10-03

- **보안·정확성 수정**: migrate-images-to-harbor.sh 하드코딩 자격증명 제거(환경변수 + `--password-stdin`), revoke-non-root-tokens.sh `set -e`+`((x++))` 즉사 버그 수정, OpenBao 시크릿 관리자 sync-wave 역전 해소("1"/"0" → "-1", 앱보다 먼저 배포), ingress-prod의 어노테이션 전체 무시(ignoreDifferences + RespectIgnoreDifferences) 제거로 Git→인그레스 어노테이션 반영 복원
- **빌드 안정성**: buildkitd 롤아웃 전략 maxSurge 0(RWO 캐시 PVC 보호, loki 사고 패턴 방지), Jenkins 플러그인 고정(`initializeOnce`/`installLatestPlugins: false`) + JVM 힙·리소스 지정 + pullPolicy IfNotPresent, Harbor registry PVC 5Gi→50Gi
- **관측 스택**: Prometheus `retentionSize: 6GB` + 리소스 지정(디스크 포화 방지), OTel Collector 자체 메트릭(8888) 스크레이프 노출 + Tempo exporter `sending_queue`/`retry_on_failure`, Tempo·Grafana 스크레이프 추가(Grafana `up{}` 알림 사각 제거), OTel/Tempo checksum annotation으로 config 변경 시 자동 롤아웃, cloudflared 2복제(외부 트래픽 SPOF 제거)
- **인그레스**: `nginx.ingress.kubernetes.io/ssl-redirect` 올바른 키로 수정(prod/pgadmin "true", stg "false" — 문서화된 의도 실제 적용), `proxy-read/send-timeout: 120`, `proxy-body-size: 10m`(pgadmin 50m) 추가
- **plate-db**: startupProbe(pg_isready, 300s 예산) 추가로 initdb/WAL replay 중 liveness kill 루프 방지
- **레거시 정리**: 죽은 배포 스크립트 5종 삭제(deploy-all/stg/prod, deploy-harbor-auth, verify-harbor-auth)

### 2026-09-27

- **관측 스택 구축(LGTM 완성)**: Loki + Alloy 추가로 로그 파이프라인 확보, Grafana SMTP 이메일 알림·이벤트 수집·홈 대시보드, postgres/redis exporter로 DB 메트릭 확보
- **OTel 자동계측**: 5개 앱(core-api, admin-web, proposal-web, idp-api, idp-web)에 Node.js 자동계측 주입 — 트레이스 축 부활 (계측 이미지는 Harbor 미러)
- **prj-deploy 분리**: 6개 prod 앱 이미지 태그를 prj-deploy 저장소로 이관(ArgoCD multi-source), 범프/롤백 가이드·예제 파이프라인 갱신
- **ArgoCD 웹훅 우회 체인**: Cloudflare Access가 argocd 도메인을 보호하므로 `onjitda.com/api/webhook` Exact 경로 + 초소형 nginx 프록시로 웹훅 노출, 웹훅 시크릿 서명 검증 적용
- **plate-db 안정화**: TLS 인증서 commonName 지정(Java JDBC `Empty issuer DN` 오류 해결), values-prod resources 구조 수정, 실측 기반 메모리 rightsizing
- **spring-api 폐기**: 관련 구성 전면 제거
- 기타: idp-api liveness/tcpSocket 프로브 추가, app-of-apps 영구 OutOfSync 제거 및 rollout restart 재발 방지(restartedAt ignoreDifferences), OpenBao ClusterSecretStore 토큰 ns 수정

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
