# Development Tools Helm Policy

이 디렉터리는 두 가지 방식으로 운영합니다.

- 로컬 chart 유지: GitOps 경로에서 직접 참조하는 차트만 repo에 둡니다.
- upstream chart values only: 수동/운영 부트스트랩에 쓰는 도구는 upstream chart를 사용하고, 이 repo에는 `values.yaml`만 둡니다.

## Repo-managed charts

- `grafana/`
- `otel-collector/`
- `tempo/`

## Upstream chart values only

| Tool | Repo | Chart | Version | Values file |
| --- | --- | --- | --- | --- |
| Argo CD | `https://argoproj.github.io/argo-helm` | `argo-cd` | `8.3.1` | `helm/development-tools/argocd/values.yaml` |
| Harbor | `https://helm.goharbor.io` | `harbor` | `1.17.2` | `helm/development-tools/harbor/values.yaml` |
| Jenkins | `https://charts.jenkins.io` | `jenkins` | `5.8.86` | `helm/development-tools/jenkins/values.yaml` |
| OpenBao | `https://openbao.github.io/openbao-helm` | `openbao` | `0.18.0` | `helm/development-tools/openbao/values.yaml` |
| OpenEBS | `https://openebs.github.io/openebs` | `openebs` | `4.3.3` | `helm/development-tools/openebs/values.yaml` |
| Prometheus | `https://prometheus-community.github.io/helm-charts` | `prometheus` | `27.37.0` | `helm/development-tools/prometheus/values.yaml` |

## Security notes

- Harbor는 `harbor-admin` secret의 `HARBOR_ADMIN_PASSWORD` 키를 사용하도록 정리했습니다.
- Harbor 신규 설치 시 `harbor-admin` 및 `harbor-database` secret/bootstrap 값을 먼저 준비해야 합니다.
- Grafana는 관리자 비밀번호를 Git에 두지 않습니다. 기존 Secret이 있으면 재사용하고, 없으면 chart가 랜덤 초기 비밀번호를 생성합니다.
- Jenkins agent는 `jenkins-agent` ServiceAccount를 따로 만들고 토큰 자동 마운트를 끕니다.
- `kubernetes-dashboard`, `fluentd`, `promtail`, `redis` vendor chart는 더 이상 repo에서 관리하지 않습니다.

기존 Harbor 릴리스에서 관리자 비밀번호를 분리할 때는 다음처럼 현재 값을 새 Secret으로 옮기면 됩니다.

```bash
kubectl get secret harbor-core -n harbor \
  -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d | \
  xargs -I{} kubectl create secret generic harbor-admin \
    -n harbor \
    --from-literal=HARBOR_ADMIN_PASSWORD="{}" \
    --dry-run=client -o yaml | kubectl apply -f -
```
