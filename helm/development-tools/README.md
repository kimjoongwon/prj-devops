# 개발·운영 도구 Helm 관리 기준

2026-10-22 형상 기준. 라이브 릴리스 상태는 별도 확인합니다. [배포 연결 지도](../../docs/deployment-map.md)를 참고합니다.

이 디렉터리는 두 가지 방식으로 운영합니다.

- 로컬 chart 유지: GitOps 경로에서 직접 참조하는 차트만 repo에 둡니다.
- upstream chart values only: 수동/운영 부트스트랩에 쓰는 도구는 upstream chart를 사용하고, 이 repo에는 `values.yaml`만 둡니다.

## GitOps가 참조하는 로컬 차트

- `grafana/`
- `otel-collector/`
- `tempo/`
- `loki/` — 로그 집계 백엔드 (single binary, filesystem 저장소, tsdb/v13 스키마)
- `alloy/` — 파드 로그 수집 에이전트 DaemonSet (stdout → Loki; Promtail 후속)
- `buildkitd/` — Jenkins 빌드 캐시용 rootless BuildKit 데몬 ([운영 문서](../../docs/jenkins-build-speed-runbook.md))
- `buzz-gateway/` — CI/CD 알림 게이트웨이 ([운영 문서](../../docs/buzz-ci-integration.md))
- `pr-agent/` — PR 리뷰 웹훅 서비스 ([구축·검증 이력](../../docs/ai-autonomous-pipeline.md))
- `cloudflared/` — Cloudflare Tunnel 커넥터
- `postgres-exporter/`, `redis-exporter/` — 데이터 서비스 메트릭 수집

## 반영 경계

로컬 차트는 자식 Application이 prj-devops main을 추적해 동기화합니다.
아래 upstream 도구는 values를 Git에 기록해도 Helm 릴리스가 자동 변경되지 않습니다.
기존 릴리스 namespace·pinned 버전·시크릿 보존 옵션을 확인한 뒤 해당 릴리스를 갱신합니다.
특히 `scripts/deploy-libraries.sh`의 Jenkins namespace는 `jenkins`이고 현재 빌드 인프라 계약은
`devops-tools`이므로 스크립트를 운영 복구 명령으로 그대로 재실행하지 않습니다.
Jenkins Job DSL과 push-router 변경은 [Buzz 연동 문서](../../docs/buzz-ci-integration.md)의 등록 검증을 따릅니다.

## upstream 차트 + values

| Tool | Repo | Chart | Version | Values file |
| --- | --- | --- | --- | --- |
| Argo CD | `https://argoproj.github.io/argo-helm` | `argo-cd` | `8.3.1` | `helm/development-tools/argocd/values.yaml` |
| Harbor | `https://helm.goharbor.io` | `harbor` | `1.17.2` | `helm/development-tools/harbor/values.yaml` |
| Jenkins | `https://charts.jenkins.io` | `jenkins` | `5.8.86` | `helm/development-tools/jenkins/values.yaml` |
| OpenBao | `https://openbao.github.io/openbao-helm` | `openbao` | `0.18.0` | `helm/development-tools/openbao/values.yaml` |
| OpenEBS | `https://openebs.github.io/openebs` | `openebs` | `4.3.3` | `helm/development-tools/openebs/values.yaml` |
| Prometheus | `https://prometheus-community.github.io/helm-charts` | `prometheus` | `27.37.0` | `helm/development-tools/prometheus/values.yaml` |

## 시크릿 관리

- Harbor는 `harbor-admin` secret의 `HARBOR_ADMIN_PASSWORD` 키를 사용하도록 정리했습니다.
- Harbor 신규 설치 시 `harbor-admin` 및 `harbor-database` secret/bootstrap 값을 먼저 준비해야 합니다.
- Grafana는 관리자 비밀번호를 Git에 두지 않습니다. 기존 Secret이 있으면 재사용하고, 없으면 chart가 랜덤 초기 비밀번호를 생성합니다.
- Jenkins agent는 `jenkins-agent` ServiceAccount를 따로 만들고 토큰 자동 마운트를 끕니다.
- `kubernetes-dashboard`, `fluentd`, `promtail`, `redis` vendor chart는 더 이상 repo에서 관리하지 않습니다.

다음은 과거 Harbor 관리자 비밀번호 분리 시 사용한 마이그레이션 예시입니다.
현재 `harbor-admin`은 OpenBao ClusterExternalSecret 동기화 대상이므로 재실행 전에
OpenBao `credentials-map`의 원본·소비처·소유권을 확인합니다.

```bash
kubectl get secret harbor-core -n harbor \
  -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d | \
  xargs -I{} kubectl create secret generic harbor-admin \
    -n harbor \
    --from-literal=HARBOR_ADMIN_PASSWORD="{}" \
    --dry-run=client -o yaml | kubectl apply -f -
```
