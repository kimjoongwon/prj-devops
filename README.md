# prj-devops — Kubernetes 배포 인프라

Helm 차트·환경 values·ArgoCD Application과 Jenkins 설정을 관리합니다. 애플리케이션 소스는
`prj-core`, 이미지 태그 상태는 `prj-deploy`가 소유합니다.

> 2026-10-22 형상 소스 기준으로 갱신했습니다. 클러스터·Jenkins·Harbor·Buzz의 현재 실행 상태를
> 확인한 기록은 아닙니다. 과거 구축·검증 결과는 아래 변경 이력과 각 문서의 날짜를 따릅니다.

## 배포 구조

```text
prj-core main → push-router(변경 경로 매칭) → 앱 빌드 → Harbor prod/<앱>:<SHA-12>
prj-core stg  → 앱 빌드 잡 수동 실행(BRANCH_NAME=stg) → Harbor stg/<앱>:<SHA-12>
                         ↓ gitops-prod-image-bump(DEPLOY_ENV=prod|stg)
prj-deploy main의 prod|stg/<앱>.yaml 태그 변경
                         ↓ ArgoCD multi-source
prj-devops main의 차트·values + prj-deploy main의 태그 → Kubernetes → Buzz #cicd
```

- 부모 Application은 [`frontend-web-apps`](environments/argocd/app-of-apps.yaml)입니다.
  `environments/argocd/apps/*.yaml`을 재귀적으로 읽으며 **환경 제외 규칙이 없습니다**.
- 부모와 자식 Application의 Git 소스는 `main`을 추적합니다. `stg` 디렉터리는 배포 환경이며
  Git 브랜치가 아닙니다. `prj-devops`에 `stg` 브랜치를 동기화해도 ArgoCD 추적 대상은 바뀌지 않습니다.
- 앱 이미지 태그는 마지막 value file인 `$values/prod|stg/<앱>.yaml`이 덮어씁니다.
  차트 기본 태그를 직접 고쳐 배포하지 않습니다.
- `main`에 반영된 GitOps 형상 변경은 자동 동기화 대상입니다. Jenkins·ArgoCD 등 upstream
  도구의 values 변경은 해당 Helm 릴리스에 별도로 반영해야 합니다.
- 변경 감지는 GitHub webhook과 `timeout.reconciliation: 60s` 폴링을 사용합니다.
  실제 감지·동기화 완료 시간은 실행 시 확인합니다.

앱별 연결·지원 경계의 기준은 **[배포 연결 지도](docs/deployment-map.md)**입니다.

## 현재 연결된 앱

| 앱 | prod | stg | 외부 진입 경로 |
|---|---|---|---|
| core-api | ✅ | ✅ | `onjitda.com/api`, `stg.onjitda.com/api` |
| admin-web | ✅ | ✅ | `onjitda.com/`, `/admin` · `stg.onjitda.com/`, `/admin` |
| idp-api | ✅ | ✅ | `idp.onjitda.com/api`, `/oidc` · `idp-stg.onjitda.com/api`, `/oidc` |
| idp-web | ✅ | ✅ | `idp.onjitda.com/`, `idp-stg.onjitda.com/` |
| proposal-web | ✅ | — | `onjitda.com/proposal` |
| design-web | ✅ | — | `onjitda.com/design` |
| live-web | ✅ | — | `onjitda.com/live` |
| tool-storybook | ✅ | — | `onjitda.com/story`, `/storybook` |
| dolmen-api | — | ✅ | dolmen-web의 API Route Handler를 통해 내부 서비스 호출 |
| dolmen-web | — | ✅ | `stg.onjitda.com/dolmen` |

`prj-deploy` 태그를 소비하는 Application은 **prod 8개, stg 6개**입니다. 이 외 `plate-db`,
`ingress`, OpenBao 시크릿 동기화, 관측·개발 도구가 함께 정의되어 있습니다.
`live-web`의 미디어 백엔드인 `srs-server-prod`는 upstream 고정 이미지이며 태그 범프 대상이 아닙니다.
`plate-llm`은 차트만 남아 있고 Application은 없습니다. 과거 `plate-cache` 차트/Application도 현재 없습니다.

## 빌드·롤백의 현재 한계

- Job DSL은 앱 빌드 잡 10개를 선언합니다. `push-router`는 `prj-core main` push만 처리하고
  Storybook을 제외한 9개 잡을 경로로 매칭합니다. Storybook과 stg 빌드는 수동 실행합니다.
- Dolmen 두 잡은 main 라우터에도 있으나 **prod 태그 파일/Application이 없습니다**.
  main 빌드가 실행되어도 prod 배포 경로가 완성되지 않으며 범프는 파일 부재로 실패합니다.
- 범프 스크립트의 앱 allowlist는 10개지만 실제 환경 지원은 위 표의 파일·Application 쌍으로
  판단합니다. `live-web --env stg`도 태그 파일이 없어 실패합니다.
- `scripts/rollback.sh`는 prod 기존 6앱(core-api/admin-web/idp-api/idp-web/proposal-web/tool-storybook),
  stg 기존 4서비스앱만 지원합니다. design/live/Dolmen은 `prj-deploy`의 해당 범프 커밋을
  직접 검토하고 revert합니다. [범프·롤백 가이드](docs/jenkins-gitops-image-bump.md)에 절차가 있습니다.
- 같은 SHA 태그로 재범프하면 no-op입니다. 범프 잡 재실행만으로 파드 재시작을 보장하지 않습니다.

## 저장소 구조

| 경로 | 소유 책임 |
|---|---|
| `helm/cluster-services/` | cert-manager·MetalLB 등 클러스터 기반 구성 |
| `helm/development-tools/` | Jenkins·ArgoCD upstream values, BuildKit·Buzz·관측 로컬 차트 |
| `helm/applications/` | 앱별 차트와 `values.yaml`, 사용 환경의 `values-prod|stg.yaml` |
| `helm/ingress/` | 환경별 통합 Ingress와 webhook 프록시 |
| `helm/shared-configs/` | OpenBao 기반 ExternalSecret·ClusterExternalSecret |
| `environments/argocd/app-of-apps.yaml` | 부트스트랩 부모 Application |
| `environments/argocd/apps/` | 앱·인프라 자식 Application |
| `docker/buzz-gateway/` | 알림 게이트웨이 이미지 소스 |
| `scripts/jenkins/` | 태그 범프·yq 설치·빌드 캐시 정리 |
| `scripts/rollback.sh` | 지원 앱의 prj-deploy 범프 커밋 revert |
| `scripts/deploy-libraries.sh` | 과거 cert-manager·MetalLB·Jenkins 부트스트랩 (실행 전 namespace 대조) |
| `scripts/openbao/` | 시크릿 관리 도구·이관 이력 스크립트 |

외부 도메인은 `onjitda.com`, 내부 서비스 코드명·네임스페이스는 `plate`, `plate-prod`,
`plate-stg`를 사용합니다. `cocdev-ingress`와 `@cocrepo/*`는 기존 리소스·패키지 이름입니다.

## 변경과 검증

1. 워크스페이스 `~/dev/AGENTS.md`와 이 저장소 [AGENTS.md](AGENTS.md)를 읽습니다.
2. 앱 코드·Dockerfile·Jenkinsfile은 `prj-core`, 차트·Application은 이 저장소에서 수정합니다.
   태그 변경은 Jenkins가 `prj-deploy main`에 기록합니다. 롤백은 같은 저장소의 범프 커밋 revert입니다.
3. GitOps 변경은 PR/리뷰 후 `main`에 반영합니다. 직접 `kubectl apply` 대신 ArgoCD가 적용하도록 합니다.
   부모 Application은 부트스트랩 객체이므로 부모 스펙 변경 시 재적용이 필요합니다.
4. 차트를 바꿨다면 해당 환경 values를 함께 렌더하고 검증합니다.

```bash
helm lint helm/applications/core-api
helm template core-api-stg helm/applications/core-api \
  -f helm/applications/core-api/values.yaml \
  -f helm/applications/core-api/values-stg.yaml \
  -f /path/to/prj-deploy/stg/core-api.yaml
git diff --check
```

배포 완료는 Git push만으로 판정하지 않습니다. 해당 ArgoCD Application의 `Synced + Healthy`,
파드 이미지·env와 앱 동작, Buzz `#cicd` 알림 도착을 확인합니다. 알림은 best-effort이며
배포 기록의 원천은 `prj-deploy` git log입니다.

```bash
kubectl -n argocd get applications \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
kubectl -n plate-prod get pods,ingress
kubectl -n plate-stg get pods,ingress
```

upstream 도구는 [Helm 관리 기준](helm/development-tools/README.md)의 pinned chart 버전과
values를 사용합니다. `deploy-libraries.sh`의 Jenkins 대상 namespace는 `jenkins`로 현재 빌드
인프라 계약인 `devops-tools`와 다릅니다. 기존 릴리스를 확인한 뒤 동일 namespace로 pinned Helm
갱신을 수행합니다. Jenkins JCasC/Job DSL 재적용 후에는 범프 잡 파라미터 재등록과
push-router GWT 트리거 등록 상태를 확인합니다. Git에 저장된 선언과 실제 잡 상태를 구분합니다.

## 관측·구성 점검

관측은 Alloy(로그·이벤트 수집), Loki(로그 저장), Prometheus(메트릭 수집),
OTel Collector·Tempo(트레이스), Grafana(조회·알림)와 postgres/redis exporter를 사용합니다.
Prometheus의 scrape 설정은 [upstream 차트 values](helm/development-tools/prometheus/values.yaml)가
소유하며 수동 Helm으로 반영합니다. 나머지 관측 구성은 각 로컬 차트와
`environments/argocd/apps/*-prod.yaml`이 소유합니다. 실제 수집·알림 상태는 런타임에서 검증합니다.

- Helm 값·시크릿 규칙 정적 점검: `./scripts/helm-sync-check.sh`.
- IDP env 키 대조: `scripts/openbao/validate-idp-env-sync.sh production`은 OpenBao 접근이 필요한 운영 점검입니다.
- 외부 도메인은 Cloudflare Tunnel → Ingress 경로입니다. VM·터널 origin/SNI·노드 Harbor LAN 경로와
  API 터널 복구 절차는 [복구 런북](docs/onjitda-recovery-runbook.md)에 보존합니다.
- 새 앱은 차트·환경 values·Application·prj-deploy 태그 파일·Jenkinsfile/DSL/라우터·범프/롤백
  allowlist·Ingress·Buzz 구독을 함께 대조해 [연결 지도](docs/deployment-map.md)를 갱신합니다.

## 시크릿·복구

- 시크릿 값은 Git에 두지 않습니다. `~/dev/onjitda-credentials.md`로 OpenBao에 진입한 뒤
  `secret/docs/overview → endpoints → credentials-map → runbooks/*` 순서로 확인합니다.
- 시크릿 원본·소비처·동기화 짝의 기준은 OpenBao `credentials-map`입니다.
  Secret 생성 예제나 과거 이관 스크립트를 현 상태에 그대로 재실행하지 않습니다.
- Harbor 대상 이미지가 없으면 `ImagePullBackOff`가 발생하며 `Synced`여도 `Healthy`가 아닐 수 있습니다.
- VM 재시작 후 OpenBao unseal, ExternalSecret 재동기화, 터널·서비스 확인은
  [클러스터 복구 런북](docs/onjitda-recovery-runbook.md)을 따릅니다.
- 외부 노출은 Ingress 경유입니다. plate-db LB의 사무실 대역 제한은 해당 values를 확인합니다.
  stg Ingress는 `ssl-redirect: false`, issuer는 `letsencrypt-prod`이며 시험 인증서를 기본 사용하지 않습니다.

## 운영 문서

| 문서 | 용도 |
|---|---|
| [배포 연결 지도](docs/deployment-map.md) | 저장소·브랜치·앱 환경·기능 한계의 현재 형상 기준 |
| [ArgoCD·webhook 운영](docs/argocd-prod-only-webhook-manual.md) | prod+stg 부모 앱, webhook·폴링·서명 검증 |
| [이미지 범프·롤백](docs/jenkins-gitops-image-bump.md) | Jenkins 권한 분리, 스크립트 지원 범위, revert |
| [STG 운영 런북](docs/stg-reactivation-runbook.md) | 수동 stg 빌드, Dolmen 경로, 재활성화 이력 |
| [Buzz 알림 연동](docs/buzz-ci-integration.md) | 알림 구독·토큰 동기화·검증 |
| [Buzz 아키텍처](docs/buzz-architecture-visual.md) | 이벤트·스레드 흐름과 과거 검증 스냅샷 |
| [빌드 속도 런북](docs/jenkins-build-speed-runbook.md) | 현 BuildKit 구성과 과거 Podman·캐시 전환 기록 |
| [AI 파이프라인](docs/ai-autonomous-pipeline.md) | 사람 결정 지점과 구축 계획·검증 이력 |
| [클러스터 복구](docs/onjitda-recovery-runbook.md) | 재부팅·OpenBao·터널 복구와 도메인 이전 기록 |

## 📝 변경 이력

### 2026-10-22

- 형상 기준 배포 연결 지도를 추가하고 prod 8앱/stg 6앱, 양 환경의 main 추적, main 자동 라우터와 수동 stg 빌드를 정리했습니다.
- design/live/Dolmen의 범프·롤백 지원 차이, Dolmen prod 배포 경로 부재, 같은 태그 범프의 no-op을 문서화했습니다.
- 과거 prod-only 지시·삭제된 plate-cache 경로를 현재 운영 설명에서 제거했습니다. 런타임 상태는 재확인하지 않았습니다.


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
