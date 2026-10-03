# buzz-gateway

## 용도

Jenkins 빌드 알림과 ArgoCD 배포 완료/헬스 저하 알림을 Buzz(Nostr) 채널로
중계한다. nostr 서명 키(jenkins-bot)는 이 파드의 Secret에만 존재하고,
Jenkins 잡과 ArgoCD notifications는 Bearer 토큰 하나로 호출한다.

로컬 관리 차트(buildkitd와 같은 범주 — `environments/argocd/apps/buzz-gateway.yaml`이
GitOps로 직접 참조). Deployment/Service 두 템플릿만 둔다.

- 전체 구성/운영: `docs/buzz-ci-integration.md`
- 이미지 소스: `docker/buzz-gateway/`

## 사전 조건

1. `buzz-gateway-env` Secret (values.yaml 상단 주석의 명령 참조)
2. Harbor가 비공개 프로젝트면 pull 시크릿 (`imagePullSecrets`)
3. 이미지가 Harbor에 푸시되어 있을 것 (`docker/buzz-gateway/README.md`)

## 반영

ArgoCD Application(`environments/argocd/apps/buzz-gateway.yaml`)가 이 차트를
관리하므로 values 변경은 커밋/푸시로 반영된다. Application 신규 등록 시에는
argocd 네임스페이스의 app-of-apps(`frontend-web-apps`)가 자동으로 가져간다.

## 검증

```bash
kubectl -n devops-tools rollout status deploy/buzz-gateway
kubectl -n devops-tools run buzz-smoke --rm -i --restart=Never --image=curlimages/curl:8.16.0 -- \
  curl -fsS -X POST http://buzz-gateway.devops-tools.svc.cluster.local/send \
  -H "Authorization: Bearer <token>" \
  -H 'Content-Type: application/json' \
  -d '{"content":"buzz-gateway 스모크 테스트"}'
```
