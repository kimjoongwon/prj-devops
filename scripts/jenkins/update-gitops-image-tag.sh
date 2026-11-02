#!/usr/bin/env bash
set -euo pipefail

# Update the app's image tag in prj-deploy (배포 상태 저장소), commit, and optionally push.
# Intended to be called from Jenkins after Harbor image push succeeds.
# NOTE: 이 스크립트는 prj-devops에 있지만 수정 대상은 prj-deploy다 —
# --workdir에는 prj-deploy 체크아웃을 넘겨야 한다 (Jenkins 파이프라인 참조).
# stg는 서비스 앱(idp-api|idp-web|core-api|admin-web)만 지원 —
# proposal-web/design-web/cover-letter-web/tool-storybook은 운영(prod) 전용.
#
# Requires mikefarah yq v4.18+ (python yq is NOT supported):
#   https://github.com/mikefarah/yq

SCRIPT_NAME="$(basename "$0")"

APP_NAME="${APP_NAME:-}"
IMAGE_TAG="${IMAGE_TAG:-}"
DEPLOY_ENV="${DEPLOY_ENV:-${ENV:-prod}}"
REPO_URL="${REPO_URL:-https://github.com/kimjoongwon/prj-deploy.git}"
TARGET_BRANCH="${TARGET_BRANCH:-main}"
GIT_USER_NAME="${GIT_USER_NAME:-jenkins-bot}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-jenkins-bot@local}"
PUSH_RETRIES="${PUSH_RETRIES:-3}"
WORKDIR="${WORKDIR:-}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_PUSH="${SKIP_PUSH:-false}"
# 최초 생성은 환경변수로 켜지지 않으며 명시적인 --initialize가 필요하다.
INITIALIZE_APP="false"

print_usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} --app <name> --tag <image_tag> [options]

Required:
  --app <name>                 App name (idp-api|idp-web|core-api|admin-web|proposal-web|cover-letter-web|design-web|live-web|tool-storybook|dolmen-api|dolmen-web)
  --tag <image_tag>            빌드 커밋 SHA 앞 12자 (소문자 16진수)

Options:
  --env <prod|stg>             Deploy environment (default: prod). stg는 서비스 앱만 지원
  --repo-url <url>             GitOps repository URL (default: ${REPO_URL})
  --branch <name>              Target branch to commit/push (default: ${TARGET_BRANCH})
  --git-user-name <name>       Git commit author name (default: ${GIT_USER_NAME})
  --git-user-email <email>     Git commit author email (default: ${GIT_USER_EMAIL})
  --push-retries <n>           Number of push retries with pull --rebase (default: ${PUSH_RETRIES})
  --workdir <path>             Use existing checkout directory instead of cloning
  --initialize                cover-letter-web/prod의 누락된 태그 파일만 최초 생성 허용
  --dry-run                    Show diff only; no commit/push
  --skip-push                  Commit only, do not push
  -h, --help                   Show this help

Environment variable alternatives:
  APP_NAME, IMAGE_TAG, DEPLOY_ENV, REPO_URL, TARGET_BRANCH, GIT_USER_NAME, GIT_USER_EMAIL,
  PUSH_RETRIES, WORKDIR, DRY_RUN, SKIP_PUSH

Requires:
  mikefarah yq v4.18+ on PATH (https://github.com/mikefarah/yq)
EOF
}

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

fail() {
  printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

normalize_bool() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "${value}" in
    true|1|yes|y) echo "true" ;;
    false|0|no|n|"") echo "false" ;;
    *) fail "Invalid boolean value: $1" ;;
  esac
}

require_yq() {
  if ! command -v yq >/dev/null 2>&1; then
    fail "yq is required but not installed. Install mikefarah yq v4.18+: https://github.com/mikefarah/yq"
  fi
  local version
  version="$(yq --version 2>/dev/null || true)"
  if ! printf '%s' "${version}" | grep -Eqi 'mikefarah|v4\.(1[8-9]|[2-9][0-9])'; then
    fail "Unsupported yq detected: ${version}. mikefarah yq v4.18+ is required (python yq is not supported)."
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_NAME="${2:-}"
      shift 2
      ;;
    --tag)
      IMAGE_TAG="${2:-}"
      shift 2
      ;;
    --env)
      DEPLOY_ENV="${2:-}"
      shift 2
      ;;
    --repo-url)
      REPO_URL="${2:-}"
      shift 2
      ;;
    --branch)
      TARGET_BRANCH="${2:-}"
      shift 2
      ;;
    --git-user-name)
      GIT_USER_NAME="${2:-}"
      shift 2
      ;;
    --git-user-email)
      GIT_USER_EMAIL="${2:-}"
      shift 2
      ;;
    --push-retries)
      PUSH_RETRIES="${2:-}"
      shift 2
      ;;
    --workdir)
      WORKDIR="${2:-}"
      shift 2
      ;;
    --initialize)
      INITIALIZE_APP="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --skip-push)
      SKIP_PUSH="true"
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${APP_NAME}" ]] || fail "--app is required"
[[ -n "${IMAGE_TAG}" ]] || fail "--tag is required"
[[ "${IMAGE_TAG}" =~ ^[0-9a-f]{12}$ ]] || fail "--tag must be the first 12 lowercase hexadecimal characters of the build commit SHA"
[[ "${PUSH_RETRIES}" =~ ^[0-9]+$ ]] || fail "--push-retries must be a non-negative integer"

DRY_RUN="$(normalize_bool "${DRY_RUN}")"
SKIP_PUSH="$(normalize_bool "${SKIP_PUSH}")"
require_yq

case "$(printf '%s' "${DEPLOY_ENV}" | tr '[:upper:]' '[:lower:]')" in
  prod|production)
    DEPLOY_ENV="prod"
    ;;
  stg|staging)
    DEPLOY_ENV="stg"
    ;;
  *)
    fail "Unsupported --env '${DEPLOY_ENV}'. Allowed: prod/production, stg/staging."
    ;;
esac

case "${APP_NAME}" in
  idp-api|idp-web|core-api|admin-web|proposal-web|cover-letter-web|design-web|live-web|tool-storybook|dolmen-api|dolmen-web)
    APP_YAML_KEY="${APP_NAME}"
    ;;
  *)
    fail "Unsupported app '${APP_NAME}'. Allowed: idp-api, idp-web, core-api, admin-web, proposal-web, cover-letter-web, design-web, live-web, tool-storybook, dolmen-api, dolmen-web"
    ;;
esac

# 정적 앱 중 아래 앱은 운영 전용이다.
if [[ "${DEPLOY_ENV}" == "stg" ]]; then
  case "${APP_NAME}" in
    proposal-web|cover-letter-web|design-web|tool-storybook)
      fail "App '${APP_NAME}' is prod-only (no stg environment)."
      ;;
  esac
fi

if [[ "${INITIALIZE_APP}" == "true" && "${DEPLOY_ENV}/${APP_NAME}" != "prod/cover-letter-web" ]]; then
  fail "--initialize is only allowed for cover-letter-web/prod"
fi

VALUES_REL_PATH="${DEPLOY_ENV}/${APP_NAME}.yaml"

TMP_DIR=""
cleanup() {
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT

if [[ -n "${WORKDIR}" ]]; then
  REPO_DIR="${WORKDIR}"
  [[ -d "${REPO_DIR}/.git" ]] || fail "WORKDIR does not look like a git checkout: ${REPO_DIR}"
else
  TMP_DIR="$(mktemp -d)"
  REPO_DIR="${TMP_DIR}/prj-deploy"
  log "Cloning ${REPO_URL} (${TARGET_BRANCH})"
  git clone --depth 1 --branch "${TARGET_BRANCH}" "${REPO_URL}" "${REPO_DIR}" >/dev/null
fi

VALUES_FILE="${REPO_DIR}/${VALUES_REL_PATH}"
IS_NEW_VALUES_FILE="false"
if [[ ! -f "${VALUES_FILE}" ]]; then
  [[ "${INITIALIZE_APP}" == "true" ]] || fail "Values file not found: ${VALUES_FILE}"
  [[ ! -e "${VALUES_FILE}" && ! -L "${VALUES_FILE}" ]] || fail "Values path is not a regular file: ${VALUES_FILE}"
  [[ -d "${REPO_DIR}/${DEPLOY_ENV}" ]] || fail "Deploy environment directory not found: ${DEPLOY_ENV}"
  IS_NEW_VALUES_FILE="true"
fi

git -C "${REPO_DIR}" config user.name "${GIT_USER_NAME}"
git -C "${REPO_DIR}" config user.email "${GIT_USER_EMAIL}"

extract_current_tag() {
  local file="$1"
  local app_key="$2"
  local tag
  # App keys contain '-', so bracket notation is required in yq expressions
  tag="$(yq eval ".[\"${app_key}\"].image.tag" "$file")"
  # yq prints "null" when the path does not exist
  if [[ -z "${tag}" || "${tag}" == "null" ]]; then
    return 1
  fi
  printf '%s' "${tag}"
}

update_tag() {
  local file="$1"
  local app_key="$2"
  local tag="$3"
  local path expr
  # App keys contain '-', so bracket notation is required in yq expressions.
  # Keep the double-quoted style used by the values files so diffs stay minimal
  # and all-digit tags are not re-serialized as bare (int-looking) scalars.
  path=".[\"${app_key}\"].image.tag"
  expr="(${path} = strenv(TAG)) | (${path} style=\"double\")"
  if [[ "${IS_NEW_VALUES_FILE}" == "true" ]]; then
    TAG="$tag" yq eval --null-input "$expr" > "$file"
  else
    TAG="$tag" yq eval -i "$expr" "$file"
  fi
}

if [[ "${IS_NEW_VALUES_FILE}" == "false" ]]; then
  if ! CURRENT_TAG="$(extract_current_tag "${VALUES_FILE}" "${APP_YAML_KEY}")"; then
    fail "Could not find current image tag in ${VALUES_REL_PATH} (${APP_YAML_KEY}.image.tag)"
  fi

  if [[ "${CURRENT_TAG}" == "${IMAGE_TAG}" ]]; then
    log "No change needed (${APP_NAME}: ${CURRENT_TAG})"
    exit 0
  fi
fi

BACKUP_FILE=""
if [[ "${DRY_RUN}" == "true" && "${IS_NEW_VALUES_FILE}" == "false" ]]; then
  BACKUP_FILE="$(mktemp)"
  cp "${VALUES_FILE}" "${BACKUP_FILE}"
fi

update_tag "${VALUES_FILE}" "${APP_YAML_KEY}" "${IMAGE_TAG}" || \
  fail "Failed to update ${APP_YAML_KEY}.image.tag in ${VALUES_REL_PATH}"

if [[ "${DRY_RUN}" == "true" ]]; then
  log "Dry-run mode enabled. Showing diff only."
  if [[ "${IS_NEW_VALUES_FILE}" == "true" ]]; then
    # 최초 파일은 untracked이므로 일반 git diff에는 나타나지 않는다.
    git -C "${REPO_DIR}" --no-pager diff --no-index -- /dev/null "${VALUES_FILE}" || [[ "$?" == "1" ]]
    rm "${VALUES_FILE}"
  else
    git -C "${REPO_DIR}" --no-pager diff -- "${VALUES_REL_PATH}"
    mv "${BACKUP_FILE}" "${VALUES_FILE}"
  fi
  exit 0
fi

git -C "${REPO_DIR}" add "${VALUES_REL_PATH}"

if git -C "${REPO_DIR}" diff --cached --quiet; then
  log "No staged change after update; exiting."
  exit 0
fi

# 범프 커밋 메시지는 환경을 구분한다 — rollback.sh가 커밋 메시지 접두사로
# 롤백 대상을 찾므로, stg 범프는 "bump stg/<앱>" 형태로 prod 범프와 섞이지 않게 한다.
if [[ "${DEPLOY_ENV}" == "stg" ]]; then
  BUMP_APP_LABEL="stg/${APP_NAME}"
else
  BUMP_APP_LABEL="${APP_NAME}"
fi
COMMIT_MSG="ci(gitops): bump ${BUMP_APP_LABEL} image to ${IMAGE_TAG}"
git -C "${REPO_DIR}" commit -m "${COMMIT_MSG}" >/dev/null
log "Committed: ${COMMIT_MSG}"

if [[ "${SKIP_PUSH}" == "true" ]]; then
  log "skip-push mode enabled. Commit created locally only."
  exit 0
fi

if [[ "${PUSH_RETRIES}" == "0" ]]; then
  git -C "${REPO_DIR}" push origin "HEAD:${TARGET_BRANCH}"
  log "Pushed to origin/${TARGET_BRANCH}"
  exit 0
fi

attempt=1
while (( attempt <= PUSH_RETRIES )); do
  log "Push attempt ${attempt}/${PUSH_RETRIES}"
  if git -C "${REPO_DIR}" pull --rebase origin "${TARGET_BRANCH}" >/dev/null 2>&1; then
    if git -C "${REPO_DIR}" push origin "HEAD:${TARGET_BRANCH}" >/dev/null 2>&1; then
      log "Pushed to origin/${TARGET_BRANCH}"
      exit 0
    fi
  else
    git -C "${REPO_DIR}" rebase --abort >/dev/null 2>&1 || true
  fi

  sleep $(( attempt * 2 ))
  attempt=$(( attempt + 1 ))
done

fail "Failed to push after ${PUSH_RETRIES} attempts"
