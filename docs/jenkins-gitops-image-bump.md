# Jenkins GitOps 이미지 범프·롤백 가이드

갱신: 2026-10-22 형상 소스 기준. 앱·환경 전체 연결은 [배포 연결 지도](deployment-map.md)를 봅니다.
이 문서의 명령은 운영 절차이며, 이번 갱신에서 Jenkins 실행·Git push·클러스터 변경을 수행한 것은 아닙니다.

## 저장소 책임

- `prj-core`: 앱 이미지 빌드 Jenkinsfile과 `devops/Jenkinsfile.gitops-update`.
- `prj-devops`: 차트·환경 values·Application, 범프/롤백 스크립트.
- `prj-deploy main`: `prod|stg/<앱>.yaml` 이미지 태그 상태와 배포 기록.
- ArgoCD multi-source: prj-devops main의 차트·환경 values 뒤에 prj-deploy main의
  `$values/<env>/<앱>.yaml`을 적용합니다. Jenkins는 클러스터 배포 대신 이 Git 상태만 갱신합니다.

태그는 **실제 빌드 체크아웃 커밋 SHA 앞 12자**를 사용합니다. `latest`나 빌드 번호 대신
소스 커밋을 추적합니다. 같은 SHA 태그로 재빌드·재범프하면 no-op이며, 파드 재시작을 보장하지 않습니다.

## 범프 지원 범위

| 환경 | 태그 파일·Application이 연결된 앱 |
|---|---|
| prod | core-api, admin-web, idp-api, idp-web, proposal-web, design-web, live-web, tool-storybook |
| stg | core-api, admin-web, idp-api, idp-web, dolmen-api, dolmen-web |

`scripts/jenkins/update-gitops-image-tag.sh`와 범프 Jenkinsfile의 앱 allowlist는 10개입니다.
실제 지원은 위 표의 기존 파일 쌍을 따릅니다. 스크립트는 파일을 새로 만들지 않습니다.
proposal/design/Storybook의 stg는 명시적으로 차단하고, live-web stg·Dolmen prod는 파일 부재로 실패합니다.
`push-router`가 Dolmen main 잡도 호출하는 불일치는 [연결 지도](deployment-map.md#앱환경-매트릭스)에 기록했습니다.

## Jenkins 실행 경로

1. `prj-core main` push는 Jenkins `push-router`가 경로를 매칭해 Storybook 제외 9개 잡을 호출합니다.
   stg와 Storybook은 해당 빌드 잡을 수동 실행합니다. stg는 `BRANCH_NAME=stg`,
   `TRUSTED_DEPLOYMENT=true`를 사용하고 실제 체크아웃 SHA를 확인합니다.
2. 빌드/Harbor push 성공 후 `/gitops-prod-image-bump`에 `APP_NAME`, `IMAGE_TAG`,
   `DEPLOY_ENV=prod|stg`를 넘깁니다. 잡 이름의 `prod`와 달리 양 환경을 지원합니다.
3. 범프 잡은 public HTTPS로 prj-devops·prj-deploy를 읽고 `prj-deploy-deploy-key`로
   prj-deploy main에만 push합니다. `github-app-credential`은 잡 정의의 prj-core 체크아웃용입니다.
4. 커밋 메시지는 prod `ci(gitops): bump <앱> image to <태그>`,
   stg `ci(gitops): bump stg/<앱> image to <태그>`입니다. 롤백이 이 접두사를 사용합니다.
5. ArgoCD가 webhook 또는 폴링으로 감지한 뒤 배포합니다. `Synced+Healthy`, 실제 이미지/env,
   앱 동작과 Buzz `#cicd` 도착까지 확인합니다.

Jenkins 잡 선언은 [JCasC·Job DSL](../helm/development-tools/jenkins/values.yaml)의
`gitops-prod-image-bump-job`이고 실행 스크립트는 prj-core `devops/Jenkinsfile.gitops-update`입니다.
Jenkins Helm/JCasC 재적용 시 선언적 파라미터가 지워지는 과거 사례가 있으므로 첫 실행 결과와
파라미터 재등록을 확인합니다. push-router는 GWT 트리거 등록을 위한 1회 수동 실행이 필요할 수 있습니다.

[`Jenkinsfile.gitops-prod-example.groovy`](../scripts/jenkins/Jenkinsfile.gitops-prod-example.groovy)는
기존 prod 6앱·PAT 방식의 참고용 골격입니다. 실제 잡의 앱 목록·권한·yq 설치 순서 기준으로 복사하지 않습니다.

## 범프 스크립트

- [update-gitops-image-tag.sh](../scripts/jenkins/update-gitops-image-tag.sh): `--app`, `--tag` 필수.
- `--env prod|stg`(기본 prod), `--repo-url`(기본 prj-deploy HTTPS), `--branch main`,
  `--push-retries 3`, `--dry-run`, `--skip-push`, `--workdir` 지원.
- mikefarah yq v4.18+ 필요. Python yq는 지원하지 않습니다.
  [install-yq.sh](../scripts/jenkins/install-yq.sh)가 핀 버전 v4.53.6·SHA 검증으로 설치하며 실제 범프 잡이 호출합니다.
- push 충돌 시 pull/rebase 후 재시도합니다. 계속 실패하면 충돌 원인을 해결한 뒤 재실행합니다.

```bash
# 깨끗한 prj-deploy clone에서 결과만 확인
./scripts/jenkins/update-gitops-image-tag.sh \
  --app idp-api --tag <빌드-SHA-12> --env stg \
  --workdir /path/to/prj-deploy --dry-run
```

## 롤백

롤백 대상은 **prj-deploy main의 범프 커밋**입니다. 앱 소스 브랜치를 되돌리는 작업과 구분합니다.
되돌릴 이미지가 Harbor에 남아 있어야 재빌드 없이 이전 태그로 배포할 수 있습니다.

### rollback.sh 지원 앱

- prod: core-api, admin-web, idp-api, idp-web, proposal-web, tool-storybook.
- stg: core-api, admin-web, idp-api, idp-web.
- design-web, live-web, dolmen-api, dolmen-web은 현재 allowlist에 없어 거부됩니다.

```bash
# 먼저 revert 결과를 확인
./scripts/rollback.sh --app core-api --env stg --dry-run

# 승인된 운영 롤백 실행: 범프 revert + prj-deploy push
./scripts/rollback.sh --app core-api --env stg

# 직전 범프 두 개를 되돌리기
./scripts/rollback.sh --app core-api --env prod --steps 2 --dry-run
```

스크립트는 최신 일치 범프부터 revert합니다. 현재 태그가 범프 태그와 다르거나 범프가 다른 파일도
변경했다면 중단합니다. `--force`로 검토를 대신하지 않습니다.

### 미지원 앱 수동 revert

깨끗한 prj-deploy 작업 브랜치에서 대상 파일과 범프 커밋을 먼저 확인합니다.
다음 예시는 stg Dolmen web이며 prod design/live도 해당 경로로 바꿔 적용합니다.

```bash
git fetch origin
git log origin/main -- stg/dolmen-web.yaml
git show --stat <범프-커밋>
git show <범프-커밋> -- stg/dolmen-web.yaml
# 해당 태그 파일만 바꾼 범프이며 후속 태그와 충돌하지 않는지 확인 후
git revert <범프-커밋>
git diff HEAD^ HEAD -- stg/dolmen-web.yaml
```

검토한 revert를 저장소의 변경 절차에 따라 main에 반영하고 ArgoCD·파드·Buzz를 검증합니다.
이전 태그나 여러 앱이 섞인 커밋을 맹목적으로 되돌리지 않습니다.
