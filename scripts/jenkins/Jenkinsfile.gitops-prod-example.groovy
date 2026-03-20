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
      description: '비우면 GIT_COMMIT 앞 12자 사용'
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
        echo '여기에 docker/podman build + harbor push 단계를 넣으세요.'
      }
    }

    stage('Update GitOps Repo') {
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GITHUB_TOKEN')]) {
          sh '''
            set -euo pipefail
            set +x

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
              --git-user-email "jenkins-bot@cocdev.co.kr" \
              --push-retries 3
          '''
        }
      }
    }
  }
}
