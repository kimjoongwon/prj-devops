# 배포 연결 지도 — prj-core · prj-devops · prj-deploy

갱신: 2026-10-22. 세 저장소의 형상 소스와 태그 파일을 대조한 기준입니다.
Jenkins 실잡·ArgoCD 라이브 스펙·Harbor 이미지·DNS·Buzz 알림의 현재 상태는 별도 확인이 필요합니다.

## 저장소와 브랜치 책임

| 저장소 | 관리 대상 | 배포 연결 |
|---|---|---|
| prj-core | 앱 코드, Dockerfile, Jenkinsfile | `main`은 prod, `stg`는 stg 빌드 환경 선택 |
| prj-devops | 차트, 환경 values, Application, Jenkins JCasC/DSL | 부모·자식 Application은 `main` 추적 |
| prj-deploy | `prod/<앱>.yaml`, `stg/<앱>.yaml`의 `image.tag` | 양 환경 모두 `main` 추적·범프 |

`stg` 디렉터리와 `stg` 브랜치는 다릅니다. 소스 브랜치 동기화는 이미지 재빌드나 태그 승격을
자동으로 수행하지 않습니다. `prj-devops`의 stg 브랜치에도 같은 형상을 두더라도 ArgoCD의
`targetRevision: main`은 유지됩니다.

ArgoCD는 `prj-devops`의 `values.yaml → values-<env>.yaml → $values/<env>/<앱>.yaml`
순서로 적용합니다. 마지막 파일의 이미지 태그가 배포 상태를 결정합니다. 태그는 **실제 빌드 체크아웃
커밋 SHA 앞 12자**입니다. 현재 선언된 이미지가 Harbor에 있는지는 형상만으로 증명할 수 없습니다.

## 앱·환경 매트릭스

| 앱 | prod 태그/Application | stg 태그/Application | main 자동 라우터 | rollback.sh |
|---|---|---|---|---|
| core-api | ✅ | ✅ | ✅ | prod/stg |
| admin-web | ✅ | ✅ | ✅ | prod/stg |
| idp-api | ✅ | ✅ | ✅ | prod/stg |
| idp-web | ✅ | ✅ | ✅ | prod/stg |
| proposal-web | ✅ | — | ✅ | prod |
| design-web | ✅ | — | ✅ | 미지원 |
| live-web | ✅ | — | ✅ | 미지원 |
| tool-storybook | ✅ | — | 수동 | prod |
| dolmen-api | — | ✅ | ✅, prod 범프 경로 없음 | 미지원 |
| dolmen-web | — | ✅ | ✅, prod 범프 경로 없음 | 미지원 |

- 태그 소비 앱은 prod 8개, stg 6개입니다. 태그 파일이나 values 파일 하나가 있다는 이유로
  배포 가능한 환경으로 판단하지 않습니다. 차트·Application·태그 파일 쌍을 모두 확인합니다.
- 범프 스크립트와 `Jenkinsfile.gitops-update`의 앱 목록은 10개입니다. stg에서 proposal/design/Storybook은
  명시적으로 차단하고, live-web은 `stg/live-web.yaml` 부재로 실패합니다.
- Dolmen Jenkinsfile은 main/stg 환경을 선택할 수 있고 main push-router에도 들어 있습니다.
  그러나 `prod/dolmen-*.yaml`과 prod Application이 없어 main 실행은 prod 범프까지 완결되지 않습니다.
  현재 연결된 배포 환경은 stg입니다. 이 문서 갱신에서 라우터나 배포 구성을 바꾸지 않았습니다.
- `srs-server-prod`는 live-web 미디어 백엔드입니다. upstream 이미지 고정 태그를 차트에서 관리하며
  prj-deploy 태그·Jenkins 앱 범프 대상이 아닙니다.
- `plate-llm`은 차트만 남아 있습니다. `plate-cache` 차트/Application은 현재 없습니다.
  `prj-docs-web`은 이 배포 경로의 Application·범프·라우터 참조가 없습니다.

## 자동·수동 경로

1. `push-router`는 `kimjoongwon/prj-core`, `refs/heads/main`, 변경 파일이 있는 push만 처리합니다.
   Job DSL의 10개 빌드 잡 중 Storybook을 뺀 9개를 경로로 매칭합니다. 매핑은 정적 필터이므로
   관련 Jenkinsfile 변경 등 매칭에서 빠진 경로는 수동 실행이 필요할 수 있습니다.
2. stg 빌드는 해당 잡의 `BRANCH_NAME=stg`, `TRUSTED_DEPLOYMENT=true`로 수동 실행합니다.
   공통 4서비스와 Dolmen 두 앱은 선택 브랜치를 명시적으로 체크아웃하는 Jenkinsfile을 사용합니다.
   잡 정의를 읽는 SCM 브랜치(main)와 빌드할 소스 브랜치(stg)를 구분합니다.
3. 빌드·Harbor push 성공 후 `gitops-prod-image-bump`에 `APP_NAME`, `IMAGE_TAG`,
   `DEPLOY_ENV=prod|stg`를 전달합니다. 잡 이름의 `prod`와 달리 두 환경을 지원합니다.
4. 범프 잡은 public HTTPS로 prj-devops의 스크립트와 prj-deploy 상태를 읽고,
   `prj-deploy-deploy-key`로 prj-deploy main에만 push합니다. GitHub App credential은
   잡 정의의 prj-core 체크아웃에 사용합니다.
5. ArgoCD가 변경을 감지하여 동기화합니다. `Synced+Healthy`·파드 이미지/env·앱 동작·Buzz 도착으로 완료를 판정합니다.

동일 태그를 전달하면 범프는 no-op입니다. 강제 재배포와 같은 의미가 아닙니다.
이전 이미지로 되돌리려면 [롤백 가이드](jenkins-gitops-image-bump.md#롤백)를 따릅니다.

## ArgoCD와 도메인

부모 [`frontend-web-apps`](../environments/argocd/app-of-apps.yaml)는 `*.yaml`을 재귀 포함하며
`directory.exclude`가 없어 prod/stg와 공용 앱을 모두 관리합니다. 환경 제외는 자식 Application
삭제·리소스 prune로 이어질 수 있어 일상적인 활성화 스위치로 사용하지 않습니다.
부모는 부트스트랩 객체이므로 부모 스펙 변경은 Git 반영 외 별도 재적용이 필요합니다.

- prod Ingress: `onjitda.com`의 `/`, `/admin`, `/api`, `/proposal`, `/design`, `/live`,
  `/story`, `/storybook`; `/live-stream`은 SRS; `idp.onjitda.com`은 IDP 전용입니다.
- stg Ingress: `stg.onjitda.com`의 `/`, `/admin`, `/api`, `/dolmen`; `idp-stg.onjitda.com`은 IDP 전용입니다.
- `/dolmen/api/*`는 dolmen-web의 `src/app/api/[...path]/route.ts`가 `DOLMEN_API_URL`로 전달합니다.
- webhook 우회 경로는 `onjitda.com/api/webhook`(ArgoCD), `/api/jenkins-webhook`(Jenkins GWT),
  `/api/pr-agent`(리뷰 서비스)입니다. 실제 GitHub 등록 URL·응답은 별도 확인합니다.
- ArgoCD 폴링 설정은 `timeout.reconciliation: 60s`입니다. webhook 성공과 배포 완료 시간은 라이브 검증 대상입니다.

## 근거 파일

- [부모 Application](../environments/argocd/app-of-apps.yaml), [자식 Application 디렉터리](../environments/argocd/apps/)
- [Jenkins JCasC·Job DSL](../helm/development-tools/jenkins/values.yaml)의 `app-build-jobs`, `push-router-job`, `gitops-prod-image-bump-job`
- [이미지 범프 스크립트](../scripts/jenkins/update-gitops-image-tag.sh), [롤백 스크립트](../scripts/rollback.sh)
- [prod Ingress](../helm/ingress/values.yaml), [stg Ingress](../helm/ingress/values-stg.yaml), [ArgoCD values](../helm/development-tools/argocd/values.yaml)
- prj-core `devops/Jenkinsfile.{core-api,admin-web,idp-api,idp-web,dolmen-api,dolmen-web,proposal-web,design-web,live-web,tool-storybook,gitops-update}`
- prj-deploy `prod/*.yaml`, `stg/*.yaml`
