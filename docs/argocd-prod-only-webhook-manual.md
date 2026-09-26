# ArgoCD 수동 운영 가이드 (Prod Only + GitHub Webhook 즉시 동기화)

## 목적
- ArgoCD App of Apps를 `prod only`로 운영
- Git `push` 직후 ArgoCD가 즉시 변경을 감지하도록 GitHub Webhook 구성

## 2026-09-27 현황 (시크릿 적용 완료)
- 웹훅 시크릿이 실제 적용됨: `argocd-secret`의 `webhook.github.secret` + 두 저장소 훅(prj-devops, prj-deploy)이 동일 시크릿으로 서명 검증 중(핑·push 전달 200 확인)
- prj-devops 훅은 `https://argocd.onjitda.com/api/webhook` — 현재 200 전달됨(2026-09-27 확인, §6의 302 이슈는 재발하지 않는 상태). prj-deploy 훅은 우회 경로 `https://onjitda.com/api/webhook`
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

## 현재 prod-only 하위 앱(2026-03-08 기준)
- `proposal-web-prod`
- `admin-web-prod`, `core-api-prod`
- `idp-web-prod`, `idp-api-prod`
- `plate-ingress-prod`, `openbao-secrets-manager-prod`, `openbao-cluster-secrets-manager`

## 현재 운영 제약(2026-03-08)
- `stg` 하위 앱은 의도적으로 제외(`exclude: "*-stg.yaml"`)되어 있습니다.
- `idp-api-prod`, `idp-web-prod`는 Harbor 이미지가 없으면 `ImagePullBackOff`로 Health가 `Progressing/Degraded`에 머뭅니다.
- 배포 전 최소 확인:

```bash
kubectl -n plate-prod get deploy idp-api-prod idp-web-prod -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image
kubectl -n plate-prod get pods | rg 'idp-(api|web)-prod'
```

## 1. App of Apps를 `prod only`로 변경
파일: `environments/argocd/app-of-apps.yaml`

아래처럼 `directory.exclude`를 설정합니다.

```yaml
spec:
  source:
    path: environments/argocd/apps
    directory:
      recurse: true
      include: "*.yaml"
      exclude: "*-stg.yaml"
```

모드 전환 규칙:
- `prod only`: `exclude: "*-stg.yaml"`
- `stg only`: `exclude: "*-prod.yaml"`
- `all`: `exclude` 라인 제거

주의:
- Child Application에 `prune: true`가 켜져 있으면, 제외된 환경 리소스(`stg`)가 정리될 수 있습니다.

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
2. `Payload URL`: `https://onjitda.com/api/webhook`
   - **주의**: `https://argocd.onjitda.com/api/webhook`는 Cloudflare Access가 보호 중이라 302 로그인으로 거부됨(2026-09-21 확인). 우회 경로는 cocdev-ingress의 `/api/webhook`(Exact) → `argocd-webhook` Service(nginx 프록시) → argocd-server 체인으로 plate-prod에 구성되어 있음(`helm/ingress/values.yaml` + `values-argocd-webhook.yaml`)
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
- `main` 브랜치에 커밋/푸시
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
  - 현재 해결(구성됨): Access 미보호 공개 도메인 `onjitda.com`의 `/api/webhook`(Exact)을 nginx 프록시(`argocd-webhook` Service, plate-prod)로 경유시켜 argocd-server에 전달. Payload URL은 위 §4 참고. POST → 앱 refresh 실측 ~2초
  - 대안(정석): Cloudflare Zero Trust → `Access` → `Applications` → `Add an application`(Self-hosted), Domain `argocd.onjitda.com` + Path `/api/webhook`, Policy Action **`Bypass`** + Include `Everyone`. 적용 시 원래 URL(`argocd.onjitda.com/api/webhook`)로 되돌릴 수 있음 — 그 경우 우회 프록시(`values-argocd-webhook.yaml`)와 ingress 경로는 제거 검토
