# STG 운영·재활성화 런북

갱신: 2026-10-22 형상 소스 기준. 2026-10-04 재활성화 절차와 이후 추가된 Dolmen을 함께 정리합니다.
현재 부모 형상에는 stg가 포함되어 있습니다. 이번 갱신에서 클러스터·Jenkins·DNS·시크릿 상태를 조회하지 않았습니다.
전체 계약은 [배포 연결 지도](deployment-map.md)를 봅니다.

## 현재 범위

| 구성 | stg 연결 | 비고 |
|---|---|---|
| core-api, admin-web, idp-api, idp-web | ✅ | 공통 서비스 4앱 |
| dolmen-api, dolmen-web | ✅ | `/dolmen` 데모, prod Application·태그 파일 없음 |
| plate-db, ingress, openbao-secrets-manager | ✅ | stg 기반 구성 |
| proposal-web, design-web, live-web, tool-storybook | — | prod만 연결 |
| plate-llm | — | 차트만 남음, 어느 환경에도 Application 없음 |
| 관측·개발 도구·SRS | 공용/prod | 앱별 Application 대상 namespace 확인 |

부모 `frontend-web-apps`는 환경 exclude가 없고 stg Application **9개**(태그 소비 6앱+기반 3개)를
포함합니다. prj-devops·prj-deploy 소스는 모두 main이며 태그는 `prj-deploy main`의
`stg/<앱>.yaml`에서 읽습니다. stg 소스 브랜치와 태그 디렉터리를 구분합니다.

## 빌드와 배포

1. Harbor stg push/pull 권한, OpenBao staging 시크릿·ESO 상태를 확인합니다.
   시크릿·토큰 생성/교체는 OpenBao `secret/docs/credentials-map`의 소비처·동기화 짝을 따릅니다.
2. 대상 앱 빌드 잡을 수동 실행합니다: `BRANCH_NAME=stg`, `TRUSTED_DEPLOYMENT=true`.
   공통 4서비스와 Dolmen 두 앱 Jenkinsfile은 선택한 stg 브랜치를 명시적으로 체크아웃합니다.
   잡 정의 SCM이 main이어도 이미지가 main 코드라는 뜻은 아니며 콘솔의 체크아웃 SHA를 확인합니다.
3. 이미지 `harbor.onjitda.com/stg/<앱>:<SHA-12>` push 성공 후
   `gitops-prod-image-bump`가 `DEPLOY_ENV=stg`로 `stg/<앱>.yaml`을 범프합니다.
   커밋은 `ci(gitops): bump stg/<앱> image to <태그>`입니다.
4. ArgoCD 자동 동기화 후 상태·실제 이미지/env·앱 동작·Buzz 도착을 확인합니다.

`push-router`는 main push만 받으므로 stg 머지만으로 빌드를 시작하지 않습니다.
Dolmen이 main 라우터에도 포함되지만 prod 태그/Application이 없는 불일치는
[연결 지도](deployment-map.md#앱환경-매트릭스)에 기록했습니다.

## 인그레스·DB

- `stg.onjitda.com/`, `/admin` → admin-web; `/api` → core-api 및 IDP 인증 경로.
- `idp-stg.onjitda.com/` → idp-web; `/api`, `/oidc` → idp-api.
- `stg.onjitda.com/dolmen` → dolmen-web.
  `/dolmen/api/*`는 Next API Route Handler(`src/app/api/[...path]/route.ts`)가 요청마다
  `DOLMEN_API_URL`을 읽어 dolmen-api에 전달합니다.
- stg Ingress는 `ssl-redirect: false`, 기본 issuer는 `letsencrypt-prod`입니다.
- core-api/idp-api의 PreSync 마이그레이션 Job 설정과 DB 연결·시드 요구사항은 해당 차트와
  prj-core 런북에서 확인합니다. Dolmen을 같은 Prisma 마이그레이션 대상으로 가정하지 않습니다.

## 상태 확인

```bash
kubectl -n argocd get applications -l environment=staging \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
kubectl -n plate-stg get pods,ingress,pvc
kubectl -n plate-stg logs deploy/core-api-stg --tail=50
```

`https://stg.onjitda.com`, `https://idp-stg.onjitda.com`에서 로그인 흐름을 확인하고
`https://stg.onjitda.com/dolmen`의 화면·API 동작을 확인합니다. 태그 변경 이력은 prj-deploy에서 봅니다.

## 재활성화·비활성화 시 주의

현재는 스위치를 켤 필요가 없습니다. 과거 prod-only에서 복구할 때는 부모의
`exclude: "*-stg.yaml"`을 제거하고 부트스트랩 부모를 별도로 apply했습니다.
부모 스펙 변경은 Git push만으로 라이브 부모가 바뀌지 않습니다.

반대로 exclude를 추가하면 prune·자식 finalizer로 Application과 리소스가 삭제될 수 있습니다.
DB/PVC 보존·복구 영향을 검토한 운영 변경으로 다루며, 일반 이미지 롤백 용도로 사용하지 않습니다.

## 롤백

```bash
# 기존 4서비스 지원: 먼저 dry-run
./scripts/rollback.sh --app core-api --env stg --dry-run
./scripts/rollback.sh --app core-api --env stg
```

Dolmen 두 앱은 `rollback.sh` 미지원입니다. prj-deploy에서 해당 `stg/dolmen-*.yaml`만
바꾼 범프를 확인하고 직접 revert합니다. [구체적 절차](jenkins-gitops-image-bump.md#미지원-앱-수동-revert)를 따릅니다.

## 2026-10-04 활성화 중 해결한 사항 (역사 기록)

아래는 당시 조치입니다. 현재 시크릿 값을 덮어쓰거나 토큰을 재발급하는 지시가 아닙니다.
재발 시 OpenBao 문서와 실제 소비처를 먼저 확인합니다.


1. **esc-policy 미적용**: OpenBao에 정책이 없어 토큰이 403 → `bao policy write esc-policy scripts/openbao/policies/esc-policy.hcl`
2. **plate-stg `openbao-token` 시크릿**: `bao token create -policy=esc-policy -orphan -period=168h` 후 k8s Secret 생성 (ESO가 자동 갱신 — 24h는 만료 사고 재발 위험, 2026-10-05 인시던트 이후 168h 권장)
3. **KV 플레이스홀더**: `core-api/staging`·`idp-api/staging`의 DATABASE_URL/DIRECT_URL=CHANGE_ME → plate-db-stg 접속 URL로 기입.
   NODE_ENV는 `staging` 불가(enum) → **production**. APP_PORT=**3006** (차트 포트와 일치).
   `LOCAL_BOOTSTRAP_*`·SMTP_SECURE·OIDC_STORYBOOK_CLIENT_ID는 idp-api/production에서 복사했었다(최초 부트스트랩 시점 기록).
   이후 관리자 비밀번호는 prod와 분리(2026-10-05), AWS_* 4종은 미사용 제거(2026-10-05).
4. **`secret/devops/staging`** 전체가 CHANGE_ME → production 값 복사 (오브젝트 스토리지 R2 공유)
5. **부모 앱 수동 apply**: app-of-apps는 부트스트랩 객체라 Git 푸시만으로 라이브 스펙이 안 바뀜 →
   `kubectl apply -f environments/argocd/app-of-apps.yaml`
6. **범프 잡 파라미터 갱신**: Jenkinsfile.gitops-update의 DEPLOY_ENV choices 변경 반영을 위해
   prod 파라미터로 1회 warm-up 실행 (b12f864 노트와 동일 함정)
