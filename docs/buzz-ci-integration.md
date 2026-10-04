# Buzz CI/CD 알림 연동 — 빌드 과정 + 배포 완료 (buzz-gateway)

> 아키텍처·이벤트 흐름을 그림으로 보려면 **[`docs/buzz-architecture-visual.md`](buzz-architecture-visual.md)**.

## 목적

- Jenkins 빌드 결과(성공/실패)와 GitOps 범프 결과를 **Buzz(Nostr) `#cicd` 채널**로 실시간 알림
- ArgoCD **배포 완료(Synced+Healthy)**와 **헬스 저하(Degraded)**도 같은 채널로 알림
- nostr 서명 키는 게이트웨이 파드 한 곳에만 존재 — Jenkins/ArgoCD는 Bearer 토큰 하나로 호출
  (Slack webhook과 동일한 사용성, 키 이관/로테이션도 한 곳에서)

Slack을 대체한다. Jenkins 쪽에는 플러그인을 추가하지 않는다(curl/wget만 사용).

## 아키텍처

```
[prj-core Jenkinsfile.* 7종]                 [ArgoCD notifications controller]
  post/finally: buzzNotify()                   trigger.on-buzz-deployed / on-buzz-degraded
        │ curl/wget POST                             │ webhook notifier
        │ Authorization: Bearer <token>              │ Bearer $buzz-gateway-token
        └─────────────► http://buzz-gateway.devops-tools.svc/send ◄──┘
                          Deployment(buzz-gateway) — buzz CLI 내장
                          Secret: buzz-gateway-env (nsec/relay/채널/토큰)
                                    │ buzz messages send
                                    ▼
                        Buzz Relay #cicd (jenkins-bot 신원)
```

알림은 모두 **best-effort**다. 게이트웨이가 죽어 있으면 빌드/배포에는 영향이 없고
알림만 유실된다(Jenkinsfile은 `\|\| true` 계열로 실패를 무시).

## 구성 요소와 형상 위치

| 요소 | 위치 |
|---|---|
| 게이트웨이 이미지 소스 | `docker/buzz-gateway/` (block/buzz buzz-cli + node:http 서버) |
| 게이트웨이 Helm 차트 | `helm/development-tools/buzz-gateway/` (로컬 관리 차트 — buildkitd와 같은 범주) |
| 게이트웨이 ArgoCD App | `environments/argocd/apps/buzz-gateway.yaml` (ns: devops-tools) |
| ArgoCD notifier/템플릿/트리거 | `helm/development-tools/argocd/values.yaml` → `notifications.*` |
| 앱 배포 알림 구독 | `environments/argocd/apps/<앱>-prod.yaml`의 `notifications.argoproj.io/subscribe.*` annotation |
| Jenkins 알림 호출 | prj-core `devops/Jenkinsfile.*`의 `buzzNotify()` (7종) |
| 게이트웨이 API 문서 | `docker/buzz-gateway/README.md` |

## 사전 준비 (1회성, 수동)

> **2026-10-03 구축 완료 상태**: #cicd 채널 UUID `2190caf3-f5fe-46fb-ab6b-3c435a175981`,
> jenkins-bot 공개키 `540f6e07e462cda6c61cecac084b6c5896592a3c69b71efdd31e99a1479f724a`
> (npub `npub12s8kuplyvtx6d3suajkqsjmvtzt9j23udxm3alwnr6v6z3ulwf9g93y85`, 채널 role=bot).
> 커뮤니티 가입은 오너 초대 코드 발급/클레임(relay `/api/invites` NIP-98)으로 수행했다.
> Harbor 프로젝트 `devops`(비공개), robot `robot$devops-buzz-gateway`(push/pull),
> 이미지 `harbor.onjitda.com/devops/buzz-gateway:0.1.0` 푸시 완료(현재 운영 태그 `0.1.2` — 스레드 매핑 보관 기능 포함, `values.yaml` 참조).
> 클러스터 시크릿(`buzz-gateway-env`, `harbor-pull-buzz`, argocd 토큰)과 Jenkins
> credential `buzz-notify-token`·잡 파라미터 `BUZZ_NOTIFY_URL`(앱 빌드 잡 7종 + gitops
> 잡 파라미터) 반영 완료. 아래 절차는 재구축/로테이션 시 참고용이다.

### 1. Buzz 측 — jenkins-bot 신원과 채널

1. Buzz Desktop에서 `jenkins-bot` 에이전트를 생성한다(오너 승인 필요):
   `buzz agents draft-create`로 프리필 폼을 열거나 Desktop UI에서 직접 생성.
2. 비공개 채널 `#cicd`를 만들고 `jenkins-bot`(그리고 알림을 볼 사람/에이전트)을 초대한다.
3. 채널 UUID를 확보한다: `buzz channels list` (member 목록에서 #cicd).
4. jenkins-bot의 **nsec/개인키**와 **NIP-OA auth tag JSON**(relay가 owner 증명을 요구하는 경우)을
   확보한다. 키는 이 문서 어디에도 적지 않고 아래 Secret에만 넣는다.

### 2. Harbor — 이미지 저장소

- 프로젝트 `devops`를 생성하고 이미지 `harbor.onjitda.com/devops/buzz-gateway:<버전>`을
  푸시한다(빌드/푸시 명령은 `docker/buzz-gateway/README.md`).
- 프로젝트가 비공개면 pull 시크릿을 만들고 `imagePullSecrets`에 지정한다
  (`helm/development-tools/buzz-gateway/values.yaml` 상단 주석).

### 3. 클러스터 Secret

```bash
kubectl -n devops-tools create secret generic buzz-gateway-env \
  --from-literal=BUZZ_RELAY_URL='https://onjitda.communities.buzz.xyz' \
  --from-literal=BUZZ_PRIVATE_KEY='<jenkins-bot nsec 또는 hex>' \
  --from-literal=BUZZ_CHANNEL='<#cicd 채널 UUID>' \
  --from-literal=BUZZ_GATEWAY_TOKEN='<임의의 긴 토큰>' \
  [--from-literal=BUZZ_AUTH_TAG='<NIP-OA auth tag JSON, 필요한 경우만>']
```

- `BUZZ_GATEWAY_TOKEN`은 Jenkins와 ArgoCD가 같이 쓴다(예: `openssl rand -hex 32`).

### 4. ArgoCD notifications 토큰

```bash
kubectl -n argocd patch secret argocd-notifications-secret \
  -p '{"stringData":{"buzz-gateway-token":"<위와 같은 토큰>"}}'
```

- values.yaml의 `notifications.secret.create`는 **false**다(필러가 지우지 않게).
- 패치 후 notifications controller 재시작: `kubectl -n argocd rollout restart deploy/argocd-notifications-controller`

### 5. Jenkins — credential과 잡 env

- Secret text credential `buzz-notify-token` = 위 `BUZZ_GATEWAY_TOKEN` 값.
- 배포 잡(보호 브랜치 job)에 env 주입: `BUZZ_NOTIFY_URL=http://buzz-gateway.devops-tools.svc.cluster.local`
  (필요 시 `BUZZ_NOTIFY_CREDENTIAL_ID`로 credential ID 재정의).
- 주입하지 않으면 해당 잡은 알림 없이 정상 동작한다(파일럿 단계 유용).

## 반영 절차

1. **게이트웨이**: 위 사전 준비 1~3 완료 후 이 저장소 커밋/푸시 →
   `buzz-gateway` Application이 자동 배포(app-of-apps). 또는 수동:
   `kubectl -n argocd argocd app sync buzz-gateway`
2. **앱 알림 구독/트리거**: 커밋/푸시만으로 앱 annotation은 반영되지만
   notifier/트리거는 argocd Helm 릴리스에 있으므로 수동 반영이 필요하다:
   `helm upgrade --install argocd jenkins/argocd ...` (기존 배포 관례 따라 values.yaml 지정)
   이후 notifications controller가 새 설정을 읽는다(config reload 또는 재시작).
3. **Jenkins**: prj-core 병합 후 각 잡의 env/credential만 Jenkins 관리자가 주입.

## 검증

```bash
# 1) 게이트웨이 직접 스모크 — #cicd에 메시지가 오는지
kubectl -n devops-tools run buzz-smoke --rm -i --restart=Never --image=curlimages/curl:8.16.0 -- \
  curl -fsS -X POST http://buzz-gateway.devops-tools.svc.cluster.local/send \
  -H "Authorization: Bearer <token>" -H 'Content-Type: application/json' \
  -d '{"content":"buzz-gateway 스모크 테스트"}'

# 2) 인증 확인(토큰 없으면 401)
kubectl -n devops-tools run buzz-auth --rm -i --restart=Never --image=curlimages/curl:8.16.0 -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://buzz-gateway.devops-tools.svc.cluster.local/send \
  -H 'Content-Type: application/json' -d '{"content":"x"}'

# 3) 파일럿 빌드: tool-storybook 잡 수동 실행 → 빌드 알림 + 범프 알림 + 🚀 배포 완료 알림 체인
#    (실패 경로 확인: 임의로 Dockerfile을 깨뜨린 커밋을 stg에서 빌드하거나,
#     게이트웨이를 일시 내려 알림이 빌드에 영향 없음을 확인)

# 4) 알림 off 확인: 앱 Application의 annotation 두 줄을 제거/주석 → 다음 배포부터 무알림
```

## 메시지 형식

| 이벤트 | 발신 | 메시지 |
|---|---|---|
| 빌드 성공/실패 | Jenkinsfile `finally` | `✅/❌ **앱** 빌드 성공/실패` + 이미지:태그, 커밋, **소요(전체 + 이미지 빌드+푸시)**, 빌드 링크 |
| GitOps 범프 성공/실패 | `Jenkinsfile.gitops-update` post | `✅/❌ **앱** GitOps 범프 성공/실패` + 태그, **소요**, 업스트림 빌드 링크 |
| 배포 완료 | ArgoCD `on-buzz-deployed` | `🚀 <앱>-prod 배포 완료 — Synced/Healthy` + 커밋, **동기화 소요**(sprig `ago`), ArgoCD 링크 |
| 헬스 저하 | ArgoCD `on-buzz-degraded` | `🔴 <앱>-prod 헬스 Degraded — 즉시 확인 필요` + ArgoCD 링크 |

소요시간 포맷: Jenkins 쪽은 `fmtDur()` 헬퍼(예: `3분 4초`). ArgoCD 쪽 동기화 소요는
템플릿이 `startedAt`/`finishedAt`을 함께 보내고 **게이트웨이가 차이를 계산**해
`동기화 소요: N분 N초` 줄을 덧붙인다(템플릿 언어로는 시차 계산이 안 되고,
`ago(startedAt)`는 "렌더링 시점 기준"이라 리비전만 갱신된 알림에서 70h 같은
비정상 값이 나온 사례가 있어 2026-10-03 이 구조로 교체). 같은 리비전의 no-op
sync는 `oncePer: revisions` 중복제거로 재발송되지 않는다.

알림 채널은 운영 소통용이다. 배포 기록의 단일 진실 원천은 여전히
**prj-deploy의 git log**(이미지 태그 히스토리)다.


## 스레드 체인과 자동 진단 (2026-10-03 고도화)

- **알림 스레드**: 빌드 ✅가 루트가 되고, 범프 ✅(SOURCE_BUZZ_EVENT_ID reply)와
  배포완료 🚀(linkKey=prj-deploy HEAD → followKey=revisions[1])가 같은 스레드에 달린다.
  게이트웨이(≥0.1.2)가 스레드 매핑을 보관한다(재시작 시 매핑 유실 — 알림은 끊기지 않고 스레드만 풀림).
- **실패 자동 진단**: 빌드/범프 실패 알림에 @ZCode가 멘션된다.
  진단 절차는 `~/.buzz/GUIDES/CICD_ALERT_DIAGNOSIS.md`(ZCode 러북).
- **빌드 잡 형상 관리**: 앱 빌드 잡 7종(빌드 5 + tool-storybook + buildkit)이 Job DSL로
  `jenkins/values.yaml`에서 관리된다(파라미터·경로 필터 포함, 수동 실행).
- **빌드 자동 트리거(폴링)는 시험 후 제거**했다 — lightweight checkout에서 includedRegions가
  무시되어 모든 커밋에 발화하고, full checkout 전환 후에도 연쇄 발화가 관찰됐다.
- **자동 트리거는 GitHub webhook + 경로 라우팅으로 재개(2026-10-04)**:
  `onjitda.com/api/jenkins-webhook`(Prefix 우회 경로) → argocd-webhook nginx →
  Jenkins GWT → **push-router 잡**이 push payload의 변경 파일을 apps regions로 매칭해
  해당 앱 빌드 잡만 `build job` 트리거한다(빌드 5종 — buildkit/storybook은 수동 예비 제외).
  - 웹훅: prj-core 저장소 1개, `push` 이벤트만, 토큰은 GWT URL 쿼리(jenkins/values.yaml
    `push-router-job`과 GitHub 웹훅 URL이 같은 토큰을 공유 — 로테이션 시 양쪽 갱신).
  - 잡 regions와 push-router의 매핑은 수동 동기화 — app-build-jobs DSL 변경 시 함께 고칠 것.
  - ping 이벤트/다른 저장소/main 외 브랜치/변경 파일 없는 push는 라우터에서 무시된다.
  - 함정 하나: JCasC/DSL 재적용(`helm upgrade jenkins`)은 gitops-prod-image-bump의
    선언적 파라미터를 한 번 지운다 — 재적용 직후 첫 범프 빌드는 파라미터 없이 돌아
    `TRUSTED_DEPLOYMENT != 'true'`로 실패한다(선언적 파라미터는 그 실행 끝에 재등록).
    helm upgrade 후 첫 범프가 이 에러로 죽으면 파라미터를 명시해 재실행하면 된다.
- **tool-storybook-buildkit 잡은 예비**: 프로비저닝이 되지 않는 현상(파드 생성 없이
  라벨 대기)이 있어 원인 조사 중. 실제 storybook 빌드는 podman 잡(tool-storybook-build) 사용.
- **Harbor 로봇 시크릿 로테이션 금지**: `PUT /api/v2.0/robots/{id}`로 시크릿을 바꾸면
  권한이 비활성화된다(actions: [] 토큰 발급). 반드시 **삭제 후 재생성**하고
  k8s pull 시크릿(`harbor-pull-buzz`)을 갱신할 것.

## 운영

### 키/토큰 로테이션

1. jenkins-bot 키 교체: Buzz Desktop에서 신원 재발급 → `buzz-gateway-env` Secret 패치 →
   `kubectl -n devops-tools rollout restart deploy/buzz-gateway`
2. 게이트웨이 토큰 교체: `buzz-gateway-env`의 `BUZZ_GATEWAY_TOKEN` +
   `argocd-notifications-secret`의 `buzz-gateway-token` + Jenkins credential `buzz-notify-token`
   세 곳을 같이 바꾼다.

### 알림 끄기

- 특정 앱만: 해당 `environments/argocd/apps/<앱>-prod.yaml`의 subscribe annotation 제거.
- 전체(배포): argocd values의 `notifications.notifiers`에서 `service.webhook.buzz-gateway` 제거.
- 빌드 알림만: Jenkins 잡에서 `BUZZ_NOTIFY_URL` env 제거.

### buzz CLI 버전 업그레이드

`docker/buzz-gateway/Dockerfile`의 `BUZZ_REF`(block/buzz 태그)를 올리고 이미지 재빌드/푸시 후
`helm/development-tools/buzz-gateway/values.yaml`의 `image.tag`를 맞춘다.
공식 릴리스에 Linux CLI 바이너리가 생기면 빌드 단계를 릴리스 다운로드로 단순화할 수 있다.

## 트러블슈팅

| 증상 | 확인 |
|---|---|
| 알림이 안 온다(빌드는 정상) | `kubectl -n devops-tools logs deploy/buzz-gateway`; Jenkins 콘솔에서 `[buzz]` 로그 |
| 게이트웨이 로그에 auth error(exit 3) | `BUZZ_PRIVATE_KEY`/`BUZZ_AUTH_TAG` 값 확인, relay가 해당 신원을 수락하는지 |
| 401 반환 | 토큰 불일치: Secret vs Jenkins credential vs argocd-notifications-secret |
| 배포 완료 알림만 안 온다 | 앱 annotation 구독 확인, `kubectl -n argocd logs deploy/argocd-notifications-controller` |
| 배포 완료 알림이 매번 오지 않는다 | multi-source 앱은 `sync.revision`이 비어 `oncePer` 중복제거에 걸릴 수 있다 → values.yaml의 `trigger.on-buzz-deployed`에서 `oncePer` 조정 |
| buzz 빌드가 이미지 빌드에서 실패 | cargo 빌드 환경 문제(openssl/protoc). rustls 기반이므로 openssl은 보통 무관, `protobuf-dev` 유지 여부 확인 |

## 보안 노트

- `jenkins-bot`은 비공개 채널에만 초대한다(키 유출 시 채널 스팸 가능 범위가 채널로 한정).
- 게이트웨이는 클러스터 내부 서비스다(ClusterIP, ingress 없음). 외부 노출 금지.
- 모든 자격증명은 Git에 커밋하지 않는다: `kubectl create/patch`로만 주입(기존 관례와 동일).
- Jenkins 파이프라인의 전송 로그는 `set +x`로 토큰 노출을 차단하고 credential masking에 의존한다.

## 향후 확장 (Phase 4, 별도 승인)

- 빌드 실패 메시지에 `@ZCode` 멘션 → ZCode가 로그를 분석해 원인 리포트를 스레드로
  (게이트웨이 `mentions` 필드 + ZCode 진단 러북 `~/.buzz/GUIDES/`)
- 게이트웨이 `fileB64`로 빌드 로그 테일 첨부
- buzz `workflows`(YAML 트리거/승인)로 채널에서의 배포 승인 게이트

> 2026-10-03: 배포 알림 노이즈 차단(리비전-only 새로고침 미발송) 검증 커밋.
