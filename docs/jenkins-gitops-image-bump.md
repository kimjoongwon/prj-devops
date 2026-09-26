# Jenkins GitOps 이미지 태그 자동 반영 가이드

## 목적
- Jenkins가 Harbor 이미지 push를 성공한 직후 **`prj-deploy`**의 `prod/<앱>.yaml`(이미지 태그 전용 저장소)을 자동 갱신
- Git 커밋/푸시를 통해 ArgoCD가 변경을 감지하고 배포 수행

## 저장소 분리 구조 (2026-09-27~)
- `prj-deploy` — 배포 상태(이미지 태그) 전용. Jenkins 범프 잡이 여기에만 커밋하며 git log가 곧 배포 기록
- `prj-devops` — 차트·values(리소스/env 등)·Application 정의. 사람이 관리
- ArgoCD Application은 multi-source로 차트는 prj-devops, 태그는 prj-deploy의 `$values/prod/<앱>.yaml`에서 읽는다
- 범프 스크립트(`update-gitops-image-tag.sh`)와 `rollback.sh`는 prj-devops에 있지만 수정 대상은 prj-deploy다

## 핵심 원칙
- Jenkins는 **클러스터 직접 배포를 하지 않고**, GitOps 저장소 변경까지만 수행
- ArgoCD가 Git 단일 진실 원천(SSOT)으로 배포를 담당
- Production 이미지 태그는 빌드 커밋 **SHA 앞 12자**를 사용한다 (`latest`, 빌드 번호 X)
  - SHA 태그는 immutable하므로 Git 커밋 ↔ 이미지가 1:1 추적된다
  - `prj-deploy`의 `prod/<앱>.yaml`도 그 태그로만 갱신

## 지원 대상 앱 (prod)
- `idp-api`
- `idp-web`
- `core-api`
- `admin-web`
- `proposal-web`
- `tool-storybook`

## 스크립트
- 경로: `scripts/jenkins/update-gitops-image-tag.sh`
- Jenkinsfile 템플릿: `scripts/jenkins/Jenkinsfile.gitops-prod-example.groovy`
- yq 요구사항(mikefarah yq v4.18+, python yq 불가): 에이전트에 yq가 없으면
  `scripts/jenkins/install-yq.sh`가 핀된 버전(v4.53.6, sha256 검증)을 워크스페이스 `.tools/bin`에
  자동 설치한다. `Jenkinsfile.gitops-update`(prj-core)가 이를 자동으로 호출하므로 별도 사전 설치 불필요.

참고: SHA 태그는 커밋별로 불변이므로 **같은 커밋을 다시 빌드하면 태그가 같아 범프가 no-op** 처리된다.
재배포가 필요하면 `gitops-prod-image-bump` 잡을 IMAGE_TAG 파라미터로 수동 실행하거나
롤백 후 재빌드한다.

필수 인자:
- `--app <name>`
- `--tag <image_tag>`

주요 옵션:
- `--env prod` (현재 prod/production만 지원)
- `--repo-url <git_url>` (기본: `https://github.com/kimjoongwon/prj-deploy.git`)
- `--branch <branch>` (기본: `main`)
- `--push-retries <n>` (기본: `3`)
- `--dry-run` (diff만 출력)
- `--skip-push` (commit만 생성)

## Jenkins Pipeline 예시

아래 파일을 기준으로 사용하세요:

- `scripts/jenkins/Jenkinsfile.gitops-prod-example.groovy`
- Jenkins job 선언: `helm/development-tools/jenkins/values.yaml` 의 `controller.JCasC.configScripts.gitops-prod-image-bump-job`

핵심 동작:
- 프로덕션 빌드는 이미지에 빌드 커밋 **SHA 앞 12자** immutable tag만 push
- 이미지 빌드/푸시 후 `github-app-credential`으로 스크립트는 `prj-devops`를 clone,
  범프 커밋/푸시는 `prj-deploy`를 clone해서 수행 (`Jenkinsfile.gitops-update`가 양쪽을 관리)
- `update-gitops-image-tag.sh` 호출로 `prj-deploy/prod/<앱>.yaml` 갱신 (yq 기반)
- `ci(gitops): bump <app> image to <tag>` 커밋 후 `prj-deploy` `main`에 push

운영 반영:
- Jenkins는 `JCasC + Job DSL`로 `gitops-prod-image-bump` 잡을 선언합니다. 잡 정의 자체가 `prj-devops`에 포함되므로 Jenkins 재배포 시 동일 상태로 수렴합니다.
- 반영은 Jenkins Helm 릴리스 재적용(`helm upgrade --install`)이 필요합니다. `configAutoReload`가 켜져 있어도 Job DSL 플러그인 추가는 컨트롤러 재시작이 선행돼야 합니다.

## 로컬 테스트 예시

```bash
./scripts/jenkins/update-gitops-image-tag.sh \
  --app idp-api \
  --tag test-1234abcd \
  --env prod \
  --workdir /path/to/prj-deploy \
  --dry-run
```

## 실패/충돌 처리
- 스크립트는 push 시 `pull --rebase` 후 재시도(`--push-retries`) 수행
- 동시 업데이트로 충돌이 계속되면 job fail 처리 후 재실행 권장

## 롤백
롤백은 bump 커밋을 revert하는 방식으로 수행한다 (Git 되돌리기 = 롤백, ArgoCD가 자동 복구):

```bash
# 직전 버전으로 롤백 (dry-run으로 결과 미리보기)
./scripts/rollback.sh --app core-api --dry-run

# 실제 롤백: 최신 bump 커밋 revert + push
./scripts/rollback.sh --app core-api

# 2단계 롤백 (최신 bump 2개 revert)
./scripts/rollback.sh --app core-api --steps 2
```

동작:
- `ci(gitops): bump <app> image to <tag>` 커밋을 찾아 최신 것부터 revert 후 push
- 안전장치: prj-deploy `prod/<앱>.yaml` 현재 태그가 최신 bump 태그와 불일치하거나, bump 커밋이 다른 파일을 건드렸으면 중단 (강제는 `--force`)
- SHA 태그 이미지는 Harbor에 그대로 남있으므로 리빌드 없이 즉시 재배포됨
