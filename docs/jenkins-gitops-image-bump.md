# Jenkins GitOps 이미지 태그 자동 반영 가이드

## 목적
- Jenkins가 Harbor 이미지 push를 성공한 직후 `prj-devops`의 `values-prod.yaml` `image.tag`를 자동 갱신
- Git 커밋/푸시를 통해 ArgoCD가 변경을 감지하고 배포 수행

## 핵심 원칙
- Jenkins는 **클러스터 직접 배포를 하지 않고**, GitOps 저장소 변경까지만 수행
- ArgoCD가 Git 단일 진실 원천(SSOT)으로 배포를 담당
- Production 이미지는 `latest` 대신 빌드 번호 같은 **immutable tag**를 사용하고, `values-prod.yaml`도 그 태그로만 갱신

## 지원 대상 앱 (prod)
- `idp-api`
- `idp-web`
- `core-api`
- `admin-web`
- `spring-api`

## 스크립트
- 경로: `scripts/jenkins/update-gitops-image-tag.sh`
- Jenkinsfile 템플릿: `scripts/jenkins/Jenkinsfile.gitops-prod-example.groovy`

필수 인자:
- `--app <name>`
- `--tag <image_tag>`

주요 옵션:
- `--env prod` (현재 prod/production만 지원)
- `--repo-url <git_url>` (기본: `https://github.com/kimjoongwon/prj-devops.git`)
- `--branch <branch>` (기본: `main`)
- `--push-retries <n>` (기본: `3`)
- `--dry-run` (diff만 출력)
- `--skip-push` (commit만 생성)

## Jenkins Pipeline 예시

아래 파일을 기준으로 사용하세요:

- `scripts/jenkins/Jenkinsfile.gitops-prod-example.groovy`

핵심 동작:
- 프로덕션 빌드는 이미지에 `${BUILD_NUMBER}` 같은 immutable tag만 push
- 이미지 빌드/푸시 후 `prj-devops`를 토큰 인증으로 clone
- `update-gitops-image-tag.sh` 호출로 `values-prod.yaml` 갱신
- `ci(gitops): bump <app> image to <tag>` 커밋 후 `main` push

## 로컬 테스트 예시

```bash
./scripts/jenkins/update-gitops-image-tag.sh \
  --app idp-api \
  --tag test-1234abcd \
  --env prod \
  --workdir /path/to/prj-devops \
  --dry-run
```

## 실패/충돌 처리
- 스크립트는 push 시 `pull --rebase` 후 재시도(`--push-retries`) 수행
- 동시 업데이트로 충돌이 계속되면 job fail 처리 후 재실행 권장
