# STG 재활성화 런북 (2026-10-04)

스테이징 환경(`plate-stg`)을 최소 리소스로 재활성화하는 절차. 기반 커밋은 이미 main에 반영되어
있고, 이 문서는 **남은 활성화 단계**(첫 이미지 빌드 → 스위치 ON → 검증)를 다룬다.

## 스코프 (운영 원칙)

| 구성 | stg | 비고 |
|---|---|---|
| core-api, admin-web, idp-api, idp-web | ✅ | 서비스 앱. replica 1, requests 합계 약 705m/1.8Gi |
| plate-db, ingress, openbao-secrets-manager | ✅ | stg 필수 인프라 (PVC 5Gi 포함) |
| proposal-web, tool-storybook | ❌ 운영만 | 서비스가 아닌 정적 에셋 — stg 매니페스트 삭제됨 |
| plate-llm | ❌ 운영만 | 무겁고(1Gi req) DNS 없음. 차트는 유지, Application만 삭제 |
| harbor, 관측 스택, 공용 인프라 | ❌ 운영만 | 기존과 동일 |

이미지 태그 전략은 prod와 동일한 **SHA-12 GitOps**: `prj-deploy stg/<앱>.yaml`의 태그를
ArgoCD multi-source로 읽는다 (`tag: latest` + 수동 재시작 방식 폐기).

## 아키텍처 변경 요약 (반영 완료)

- `environments/argocd/apps/*-stg.yaml`: 서비스 4앱 multi-source 전환, proposal-web/plate-llm 삭제
- `helm/ingress/values-stg.yaml`: `/proposal`, `llm.onjitda.com` 라우트·TLS 제거
- `scripts/jenkins/update-gitops-image-tag.sh`, `scripts/rollback.sh`: `--env stg` 지원.
  stg 범프 커밋은 `ci(gitops): bump stg/<앱> image to <태그>` (prod 롤백 매칭과 분리)
- prj-core `devops/Jenkinsfile.*`: 서비스 4앱은 stg 빌드도 범프 트리거(`DEPLOY_ENV=stg`),
  proposal-web는 main 전용으로 제한
- prj-deploy `stg/<앱>.yaml`: 초기 태그는 prod 복제(부트스트랩) — 실제 이미지는 아직 없음

## 이미 확인된 사전 조건 (2026-10-04)

- DNS/터널: `stg.onjitda.com`, `idp-stg.onjitda.com` 모두 Cloudflare 터널 → ingress-nginx 도달 확인 (404)
- OpenBao KV: `secret/{core-api,idp-api,idp-web}/staging` 경로 존재
- 클러스터 여유: node-02 (4CPU) 기준 stg 합계 requests 수용 가능

## Step 1 — 수동 사전 확인

```bash
# (a) Harbor 'stg' 프로젝트 존재 + push robot 권한 — Jenkins 'harbor' credential이
#     prod 프로젝트 외 stg 프로젝트에도 push 가능해야 한다. 없으면 프로젝트 생성 + robot 권한 부여.
#     (프로젝트 없으면 Step 2 첫 빌드에서 push 실패로 즉시 노출됨)

# (b) OpenBao secret/harbor/staging 값 — plate-stg imagePullSecret(harbor-docker-secret)의 원본.
#     stg 프로젝트 pull 권한이 있는 robot 자격증명(username/password)이 들어있어야 한다.
bao kv get secret/harbor/staging   # 값이 비어 있으면 robot 생성 후 KV 재기입

# (c) IDP stg 엔드포인트 patch (idp-api/idp-web가 idp-stg.onjitda.com을 바라보게)
./scripts/openbao/patch-idp-endpoints.sh staging dry-run
./scripts/openbao/patch-idp-endpoints.sh staging apply
```

## Step 2 — 첫 stg 이미지 빌드 (활성화 전에 수행)

Jenkins 앱 빌드 잡은 `*/main` 체크아웃 + `BRANCH_NAME` 파라미터로 환경을 결정한다.
**stg 배포 = 해당 앱 빌드 잡을 `BRANCH_NAME=stg`로 수동 실행** (main에 머지된 코드 기준).

대상 잡: `core-api-build`, `admin-web-build`, `idp-api-build`, `idp-web-build`

각 빌드는: `harbor.onjitda.com/stg/<앱>:<SHA-12>` (+`:latest`) push →
`gitops-prod-image-bump` 잡이 `prj-deploy stg/<앱>.yaml`을 자동 범프·푸시.

```bash
# 진행 확인
git -C ../prj-deploy log --oneline -- stg/        # "ci(gitops): bump stg/<앱> ..." 4건 확인
```

## Step 3 — 활성화 (스위치 ON)

`environments/argocd/app-of-apps.yaml`의 directory에서 exclude 한 줄 제거 후 커밋/푸시:

```yaml
    directory:
      recurse: true
      include: "*.yaml"
      # exclude: "*-stg.yaml"   ← 이 줄 제거 (또는 주석 처리)
```

ArgoCD가 plate-stg 네임스페이스에 7개 stg 앱을 배포한다:
`openbao-secrets-manager-stg`(wave -1) → `plate-db-stg` → `core-api/admin-web/idp-api/idp-web-stg` → `plate-ingress-stg`

끄고 싶을 때는 exclude 줄 복원 — prune로 stg 앱 전체가 제거된다 (PVC는 `plate-db-stg` finalizer
동작에 따르니 삭제 확인 필수).

## Step 4 — DB 마이그레이션 (자동)

core-api/idp-api 차트의 **PreSync 마이그레이션 Job**(`migrationJob.enabled: true`)이
`prisma migrate deploy` + 기준 데이터 시드(`data-migrate.ts`, `LOCAL_BOOTSTRAP_*` 필요)를
배포 전 자동 실행한다. 수동 실행은 불필요.

## 2026-10-04 활성화 중 해결한 사항 (재현 시 참고)

1. **esc-policy 미적용**: OpenBao에 정책이 없어 토큰이 403 → `bao policy write esc-policy scripts/openbao/policies/esc-policy.hcl`
2. **plate-stg `openbao-token` 시크릿**: `bao token create -policy=esc-policy -orphan -period=24h` 후 k8s Secret 생성 (ESO가 자동 갱신)
3. **KV 플레이스홀더**: `core-api/staging`·`idp-api/staging`의 DATABASE_URL/DIRECT_URL=CHANGE_ME → plate-db-stg 접속 URL로 기입.
   NODE_ENV는 `staging` 불가(enum) → **production**. APP_PORT=**3006** (차트 포트와 일치).
   `LOCAL_BOOTSTRAP_*` 5종은 idp-api/production에서 복사.
   AWS_*/SMTP_SECURE/OIDC_STORYBOOK_CLIENT_ID도 production에서 복사(공유 인프라).
4. **`secret/devops/staging`** 전체가 CHANGE_ME → production 값 복사 (오브젝트 스토리지 R2 공유)
5. **부모 앱 수동 apply**: app-of-apps는 부트스트랩 객체라 Git 푸시만으로 라이브 스펙이 안 바뀜 →
   `kubectl apply -f environments/argocd/app-of-apps.yaml`
6. **범프 잡 파라미터 갱신**: Jenkinsfile.gitops-update의 DEPLOY_ENV choices 변경 반영을 위해
   prod 파라미터로 1회 warm-up 실행 (b12f864 노트와 동일 함정)

## Step 5 — 검증 체크리스트

```bash
kubectl -n argocd get applications -l environment=stg \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
kubectl -n plate-stg get pods,ingress,pvc
kubectl -n plate-stg logs deploy/core-api-stg --tail=50   # DB 접속/마이그레이션 오류 확인
```

- https://stg.onjitda.com — admin-web 렌딩
- https://stg.onjitda.com/api — core-api 헬스
- https://idp-stg.onjitda.com — idp-web 로그인 페이지 → 로그인 플로우(oidc interaction) 통과

## 롤백

```bash
# 이미지 되돌리기 (stg 범프 커밋 revert)
./scripts/rollback.sh --app core-api --env stg --dry-run
./scripts/rollback.sh --app core-api --env stg

# stg 전체 비활성화: app-of-apps exclude 복원 (Step 3 역순)
```

## 운영 플로우 요약

- **prod**: main 자동 빌드(push-router 경로 라우팅) → `prod/<앱>.yaml` 범프 → 자동 배포 (기존과 동일)
- **stg**: 서비스 앱 빌드 잡 수동 실행(`BRANCH_NAME=stg`) → `stg/<앱>.yaml` 범프 → 자동 배포
- stg 이미지 빌드는 main 코드를 그대로 빌드한다 — "prod 전 검증" 용도
