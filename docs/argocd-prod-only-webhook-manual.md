# ArgoCD 운영 가이드 — prod + stg · GitHub Webhook

> 2026-10-22 형상 기준 갱신. 파일명은 기존 링크 호환을 위해 유지합니다.
> 현재 연결 계약은 [배포 연결 지도](deployment-map.md)이며, 아래 과거 검증 결과는 현재 런타임 상태를 보증하지 않습니다.

## 목적
- ArgoCD App of Apps로 prod·stg와 공용 Application을 함께 관리
- prj-devops main·prj-deploy main 변경을 webhook과 폴링으로 감지

## 2026-09-27 적용·검증 기록 (현재 상태 별도 확인)
- 웹훅 시크릿이 실제 적용됨: `argocd-secret`의 `webhook.github.secret` + 두 저장소 훅(prj-devops, prj-deploy)이 동일 시크릿으로 서명 검증 중(핑·push 전달 200 확인)
- prj-devops 훅은 `https://argocd.onjitda.com/api/webhook` — 당시 200 전달 확인(2026-09-27; 현재 Recent Deliveries 재확인 필요). prj-deploy 훅은 우회 경로 `https://onjitda.com/api/webhook`
- **주의**: 시크릿을 공개 레포에 넣을 수 없어 라이브 패치로만 반영함 — ArgoCD helm upgrade 시 반드시 §3의 `--set-string configs.secret.githubSecret=$(kubectl -n argocd get secret argocd-secret -o go-template='{{index .data "webhook.github.secret"}}' | base64 --decode)`를 붙여야 웹훅이 깨지지 않음

## 비용 관련
- GitHub Webhook 자체는 별도 과금되지 않습니다.

## 사전 조건
- `kubectl`로 클러스터 접근 가능
- `helm` 사용 가능
- ArgoCD가 `argocd` 네임스페이스에 설치됨
- GitHub 저장소 관리자 권한(또는 Webhook 설정 권한) 보유

## 운영 기준 Parent Application
- 현재 운영 기준 App of Apps 이름: `frontend-web-apps`
- 아래 명령으로 확인:

```bash
kubectl -n argocd get application frontend-web-apps
```

## 현재 하위 앱 (2026-10-22 형상 기준)
- prj-deploy 태그 소비 prod 8앱: `core-api-prod`, `admin-web-prod`, `idp-api-prod`, `idp-web-prod`, `proposal-web-prod`, `design-web-prod`, `live-web-prod`, `tool-storybook-prod`
- prj-deploy 태그 소비 stg 6앱: `core-api-stg`, `admin-web-stg`, `idp-api-stg`, `idp-web-stg`, `dolmen-api-stg`, `dolmen-web-stg`
- 데이터·미디어: `plate-db-prod`, `plate-db-stg`, `srs-server-prod`(upstream 이미지, prj-deploy 범프 제외)
- 인그레스: `plate-ingress-prod`(ingress-prod.yaml), `pgadmin-prod`, `pgadmin-ingress-prod`
- 관측/인프라: `grafana-prod`, `loki-prod`, `tempo-prod`, `otel-collector-prod`, `alloy-prod`, `postgres-exporter-prod`, `redis-exporter-prod`, `cloudflared-prod`, `buildkitd`, `buzz-gateway`, `pr-agent`
- 시크릿·stg 인프라: `openbao-secrets-manager-prod`, `openbao-secrets-manager-stg`, `openbao-cluster-secrets-manager`, `plate-ingress-stg`
- `plate-cache` 차트/Application은 현재 없으며, `plate-llm`은 차트만 유지합니다.
- 부모는 `directory.exclude` 없이 prod+stg를 포함합니다. 라이브 배포 상태는 아래 명령으로 확인합니다. [STG 런북](stg-reactivation-runbook.md) 참고.

## 운영 확인 사항
- 형상에는 `stg` 앱이 포함됩니다. 부모·자식 모두 main을 추적하고, 환경은 prj-deploy 디렉터리로 나눕니다.
- `idp-api-prod`, `idp-web-prod`는 Harbor 이미지가 없으면 `ImagePullBackOff`로 Health가 `Progressing/Degraded`에 머뭅니다.
- 배포 전 최소 확인:

```bash
kubectl -n plate-prod get deploy idp-api-prod idp-web-prod -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image
kubectl -n plate-prod get pods | rg 'idp-(api|web)-prod'
```

## 1. 현재 App of Apps 범위 유지

파일: [environments/argocd/app-of-apps.yaml](../environments/argocd/app-of-apps.yaml)

```yaml
spec:
  source:
    targetRevision: main
    path: environments/argocd/apps
    directory:
      recurse: true
      include: "*.yaml"
```

현재 `exclude`는 없습니다. 과거 prod-only 운영은 `exclude: "*-stg.yaml"`을 사용했으나
2026-10-04 재활성화 때 제거했습니다. 이를 다시 추가하면 부모의 prune과 자식 finalizer에 의해
stg Application·리소스가 삭제될 수 있습니다. 일상적인 배포 전환 명령으로 사용하지 않습니다.
부모는 부트스트랩 객체이므로 부모 스펙을 바꿀 때만 Git 반영 후 `kubectl apply -f environments/argocd/app-of-apps.yaml` 재적용이 필요합니다.

## 2. ArgoCD에 GitHub Webhook Secret 설정
Webhook 서명 검증용 시크릿을 생성합니다.

```bash
WEBHOOK_SECRET=$(openssl rand -hex 32)
echo "$WEBHOOK_SECRET"
```

ArgoCD 시크릿에 반영:

```bash
kubectl -n argocd patch secret argocd-secret \
  --type merge \
  -p "{\"stringData\":{\"webhook.github.secret\":\"$WEBHOOK_SECRET\"}}"
```

적용 확인:

```bash
kubectl -n argocd get secret argocd-secret \
  -o go-template='{{index .data "webhook.github.secret"}}' | base64 --decode; echo
```

서버 재시작:

```bash
kubectl -n argocd rollout restart deployment argocd-server
kubectl -n argocd rollout status deployment argocd-server --timeout=180s
```

## 3. Helm 릴리스에도 Secret 유지(권장)
`kubectl patch`만 하면 다음 Helm 업그레이드 시 값이 덮일 수 있습니다. 아래 명령으로 릴리스 값에도 반영합니다.

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo

helm upgrade argocd argo/argo-cd \
  -n argocd \
  --version 8.3.1 \
  -f ./helm/development-tools/argocd/values.yaml \
  --set-string configs.secret.githubSecret="$WEBHOOK_SECRET" \
  --wait --timeout 5m
```

확인:

```bash
helm get values argocd -n argocd -o yaml | rg "githubSecret"
```

## 4. GitHub Webhook 등록
GitHub 저장소에서:

1. `Settings` -> `Webhooks` -> `Add webhook`
2. `Payload URL`: 저장소에 따라 다르다(2026-09-27 확인)
   - **prj-devops**: `https://argocd.onjitda.com/api/webhook` — 2026-09-27에 200 전달 확인. 현재 Recent Deliveries 재확인
   - **prj-deploy 등 우회 필요 시**: `https://onjitda.com/api/webhook` — Cloudflare Access가 argocd 도메인을 보호하는 경우의 우회 경로. cocdev-ingress의 `/api/webhook`(Exact) → `argocd-webhook` Service(nginx 프록시) → argocd-server 체인으로 plate-prod에 구성되어 있음(`helm/ingress/values.yaml` + `values-argocd-webhook.yaml`)
3. `Content type`: `application/json`
4. `Secret`: `WEBHOOK_SECRET` 값 입력
5. 이벤트: `Just the push event`
6. `Active` 체크 후 저장

## 5. 동작 검증
1차 확인(엔드포인트 접근):

```bash
curl -I https://argocd.onjitda.com/api/webhook
```

`400 Bad Request`가 나와도 엔드포인트가 살아있다면 정상입니다(서명 없는 요청이기 때문).
`302`로 `onjitda.cloudflareaccess.com`에 리다이렉트되면 Cloudflare Access가 웹훅을 차단 중이라는 뜻이다 → [트러블슈팅](#6-트러블슈팅)의 Access bypass 항목 참고.

2차 확인(실제 push):
- 검토된 변경을 해당 저장소의 절차에 따라 `main`에 반영 (webhook 확인만을 위한 무의미한 배포 커밋은 불필요)
- ArgoCD 로그 확인:

```bash
kubectl -n argocd logs deploy/argocd-server --since=5m | rg -i "Received push event|webhook"
```

`Received push event`가 보이면 webhook 트리거가 정상 동작 중입니다.

## 6. 트러블슈팅
- Push 후 즉시 반영 안 됨:
  - GitHub webhook Recent Deliveries에서 HTTP 상태 확인
  - ArgoCD `argocd-secret`의 `webhook.github.secret` 값 재확인 (미설정 시 서명 검증 생략 — 어느 secret이든 수락됨)
  - `argocd-server` 재시작 후 재시도
- 그래도 반영 안 됨:
  - 폴링(`timeout.reconciliation`, 2026-09-21부터 60s)으로는 반영되는지 먼저 확인
  - Ingress/방화벽에서 `argocd.onjitda.com/api/webhook` 접근 차단 여부 확인
- **Cloudflare Access가 웹훅을 차단하는 경우 (2026-09-21 실제 발생, 우회 경로로 해결 완료)**:
  - 증상: `curl -I https://argocd.onjitda.com/api/webhook`이 `302` + `location: https://onjitda.cloudflareaccess.com/...`, GitHub Recent Deliveries 실패. 도메인 전환(2026-09-18) 때 UI 보호용으로 걸은 Access가 `/api/webhook`까지 보호해 GitHub(세션 없음)가 로그인 페이지로 튕겨남
  - 당시 해결(형상 경로 유지): Access 미보호 공개 도메인 `onjitda.com`의 `/api/webhook`(Exact)을 nginx 프록시(`argocd-webhook` Service, plate-prod)로 경유시켜 argocd-server에 전달. Payload URL은 위 §4 참고. 당시 POST → 앱 refresh 실측 약 2초(현재 지연 별도 측정)
  - 대안(정석): Cloudflare Zero Trust → `Access` → `Applications` → `Add an application`(Self-hosted), Domain `argocd.onjitda.com` + Path `/api/webhook`, Policy Action **`Bypass`** + Include `Everyone`. 적용 시 원래 URL(`argocd.onjitda.com/api/webhook`)로 되돌릴 수 있음 — 그 경우 우회 프록시(`values-argocd-webhook.yaml`)와 ingress 경로는 제거 검토
