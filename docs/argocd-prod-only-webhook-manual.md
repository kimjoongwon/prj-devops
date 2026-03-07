# ArgoCD 수동 운영 가이드 (Prod Only + GitHub Webhook 즉시 동기화)

## 목적
- ArgoCD App of Apps를 `prod only`로 운영
- Git `push` 직후 ArgoCD가 즉시 변경을 감지하도록 GitHub Webhook 구성

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

## 현재 prod-only 하위 앱(2026-03-07 기준)
- `plate-web-prod`, `plate-server-prod`, `plate-admin-prod`
- `idp-web-prod`, `idp-api-prod`
- `plate-ingress-prod`, `openbao-secrets-manager-prod`

## 현재 운영 제약(2026-03-07)
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
helm upgrade argocd ./helm/development-tools/argocd \
  -n argocd \
  --reuse-values \
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
2. `Payload URL`: `https://argocd.cocdev.co.kr/api/webhook`
3. `Content type`: `application/json`
4. `Secret`: `WEBHOOK_SECRET` 값 입력
5. 이벤트: `Just the push event`
6. `Active` 체크 후 저장

## 5. 동작 검증
1차 확인(엔드포인트 접근):

```bash
curl -I https://argocd.cocdev.co.kr/api/webhook
```

`400 Bad Request`가 나와도 엔드포인트가 살아있다면 정상입니다(서명 없는 요청이기 때문).

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
  - ArgoCD `argocd-secret`의 `webhook.github.secret` 값 재확인
  - `argocd-server` 재시작 후 재시도
- 그래도 반영 안 됨:
  - 폴링(`timeout.reconciliation`, 기본 180s)으로는 반영되는지 먼저 확인
  - Ingress/방화벽에서 `argocd.cocdev.co.kr/api/webhook` 접근 차단 여부 확인
