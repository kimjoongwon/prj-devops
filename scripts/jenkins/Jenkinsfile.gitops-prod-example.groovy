// GitOps 이미지 태그 범프 파이프라인 예시
//
// 태그 컨벤션: 이미지 태그는 빌드 커밋의 SHA 앞 12자(GIT_COMMIT 기반)를 사용한다.
// SHA 태그는 immutable하므로 Git 커밋과 이미지가 1:1로 추적되고,
// 롤백은 ./scripts/rollback.sh --app <앱명> 으로 bump 커밋을 revert하면 된다.
//
// 요구사항: 에이전트에 yq가 없으면 install-yq.sh가 핀된 버전을 워크스페이스에 자동 설치한다.
pipeline {
  agent any

  parameters {
    choice(
      name: 'APP_NAME',
      choices: ['idp-api', 'idp-web', 'core-api', 'admin-web', 'proposal-web', 'spring-api'],
      description: 'GitOps values-prod.yaml image.tag를 갱신할 앱 이름'
    )
    string(
      name: 'IMAGE_TAG',
      defaultValue: '',
      description: '비우면 GIT_COMMIT 앞 12자(SHA) 사용'
    )
  }

  environment {
    DEPLOY_ENV = 'prod'
    GITOPS_REPO = 'https://github.com/kimjoongwon/prj-devops.git'
    GITOPS_BRANCH = 'main'
    GITOPS_DIR = 'prj-devops-gitops'
  }

  stages {
    stage('Checkout App Repo') {
      steps {
        checkout scm
      }
    }

    stage('Build & Push Image') {
      steps {
        echo '''
          여기에 docker/podman build + harbor push 단계를 넣으세요.
          이미지 태그는 빌드 커밋 SHA 앞 12자로 push할 것 (예: ${GIT_COMMIT:0:12}).
        '''.trim()
      }
    }

    stage('Update GitOps Repo') {
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GITHUB_TOKEN')]) {
          sh '''
            set -euo pipefail
            set +x

            # yq 부트스트랩: 없으면 핀된 버전을 워크스페이스에 내려받는다 (휘발성 에이전트 대비)
            if [ -f "${GITOPS_DIR}/scripts/jenkins/install-yq.sh" ]; then
              bash "${GITOPS_DIR}/scripts/jenkins/install-yq.sh" --prefix "${PWD}/.tools"
              export PATH="${PWD}/.tools/bin:${PATH}"
            fi

            TAG="${IMAGE_TAG:-}"
            if [ -z "${TAG}" ]; then
              TAG="$(echo "${GIT_COMMIT}" | cut -c1-12)"
            fi

            rm -rf "${GITOPS_DIR}"
            git clone --branch "${GITOPS_BRANCH}" \
              "https://${GITHUB_TOKEN}@github.com/kimjoongwon/prj-devops.git" \
              "${GITOPS_DIR}"

            "${GITOPS_DIR}/scripts/jenkins/update-gitops-image-tag.sh" \
              --app "${APP_NAME}" \
              --tag "${TAG}" \
              --env "${DEPLOY_ENV}" \
              --workdir "${PWD}/${GITOPS_DIR}" \
              --branch "${GITOPS_BRANCH}" \
              --git-user-name "jenkins-bot" \
              --git-user-email "jenkins-bot@onjitda.com" \
              --push-retries 3
          '''
        }
      }
    }
  }
}
