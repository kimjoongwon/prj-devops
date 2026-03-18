#!/usr/bin/env bash
set -euo pipefail

# Update prj-devops Helm values image tag for a specific app, commit, and optionally push.
# Intended to be called from Jenkins after Harbor image push succeeds.

SCRIPT_NAME="$(basename "$0")"

APP_NAME="${APP_NAME:-}"
IMAGE_TAG="${IMAGE_TAG:-}"
DEPLOY_ENV="${DEPLOY_ENV:-${ENV:-prod}}"
REPO_URL="${REPO_URL:-https://github.com/kimjoongwon/prj-devops.git}"
TARGET_BRANCH="${TARGET_BRANCH:-main}"
GIT_USER_NAME="${GIT_USER_NAME:-jenkins-bot}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-jenkins-bot@local}"
PUSH_RETRIES="${PUSH_RETRIES:-3}"
WORKDIR="${WORKDIR:-}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_PUSH="${SKIP_PUSH:-false}"

print_usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} --app <name> --tag <image_tag> [options]

Required:
  --app <name>                 App name (idp-api|idp-web|core-api|admin-web|spring-api|tool-storybook)
  --tag <image_tag>            New image tag to set

Options:
  --env <prod|production>      Deploy environment (default: prod)
  --repo-url <url>             GitOps repository URL (default: ${REPO_URL})
  --branch <name>              Target branch to commit/push (default: ${TARGET_BRANCH})
  --git-user-name <name>       Git commit author name (default: ${GIT_USER_NAME})
  --git-user-email <email>     Git commit author email (default: ${GIT_USER_EMAIL})
  --push-retries <n>           Number of push retries with pull --rebase (default: ${PUSH_RETRIES})
  --workdir <path>             Use existing checkout directory instead of cloning
  --dry-run                    Show diff only; no commit/push
  --skip-push                  Commit only, do not push
  -h, --help                   Show this help

Environment variable alternatives:
  APP_NAME, IMAGE_TAG, DEPLOY_ENV, REPO_URL, TARGET_BRANCH, GIT_USER_NAME, GIT_USER_EMAIL,
  PUSH_RETRIES, WORKDIR, DRY_RUN, SKIP_PUSH
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
[[ "${PUSH_RETRIES}" =~ ^[0-9]+$ ]] || fail "--push-retries must be a non-negative integer"

DRY_RUN="$(normalize_bool "${DRY_RUN}")"
SKIP_PUSH="$(normalize_bool "${SKIP_PUSH}")"

case "$(printf '%s' "${DEPLOY_ENV}" | tr '[:upper:]' '[:lower:]')" in
  prod|production)
    DEPLOY_ENV="prod"
    ;;
  *)
    fail "Unsupported --env '${DEPLOY_ENV}'. Currently only prod/production is supported."
    ;;
esac

case "${APP_NAME}" in
  idp-api)
    VALUES_REL_PATH="helm/applications/idp-api/values-prod.yaml"
    APP_YAML_KEY="idp-api"
    ;;
  idp-web)
    VALUES_REL_PATH="helm/applications/idp-web/values-prod.yaml"
    APP_YAML_KEY="idp-web"
    ;;
  core-api)
    VALUES_REL_PATH="helm/applications/core-api/values-prod.yaml"
    APP_YAML_KEY="core-api"
    ;;
  admin-web)
    VALUES_REL_PATH="helm/applications/admin-web/values-prod.yaml"
    APP_YAML_KEY="admin-web"
    ;;
  spring-api)
    VALUES_REL_PATH="helm/applications/spring-api/values-prod.yaml"
    APP_YAML_KEY="spring-api"
    ;;
  tool-storybook)
    VALUES_REL_PATH="helm/applications/tool-storybook/values-prod.yaml"
    APP_YAML_KEY="tool-storybook"
    ;;
  *)
    fail "Unsupported app '${APP_NAME}'. Allowed: idp-api, idp-web, core-api, admin-web, spring-api, tool-storybook"
    ;;
esac

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
  REPO_DIR="${TMP_DIR}/prj-devops"
  log "Cloning ${REPO_URL} (${TARGET_BRANCH})"
  git clone --depth 1 --branch "${TARGET_BRANCH}" "${REPO_URL}" "${REPO_DIR}" >/dev/null
fi

VALUES_FILE="${REPO_DIR}/${VALUES_REL_PATH}"
[[ -f "${VALUES_FILE}" ]] || fail "Values file not found: ${VALUES_FILE}"

git -C "${REPO_DIR}" config user.name "${GIT_USER_NAME}"
git -C "${REPO_DIR}" config user.email "${GIT_USER_EMAIL}"

extract_current_tag() {
  local file="$1"
  local app_key="$2"
  awk -v app_key="$app_key" '
    BEGIN { in_app = 0 }
    $0 ~ "^" app_key ":[[:space:]]*$" { in_app = 1; next }
    in_app && $0 ~ "^[^[:space:]#].*:[[:space:]]*$" { in_app = 0 }
    in_app && $0 ~ "^[[:space:]]+tag:[[:space:]]*" {
      line = $0
      sub(/^[[:space:]]+tag:[[:space:]]*/, "", line)
      sub(/[[:space:]]*(#.*)?$/, "", line)
      gsub(/^"/, "", line)
      gsub(/"$/, "", line)
      print line
      exit
    }
  ' "$file"
}

update_tag() {
  local file="$1"
  local app_key="$2"
  local tag="$3"
  local tmp_file
  tmp_file="$(mktemp)"

  if ! awk -v app_key="$app_key" -v new_tag="$tag" '
    BEGIN { in_app = 0; replaced = 0 }
    {
      line = $0
      if (line ~ "^" app_key ":[[:space:]]*$") {
        in_app = 1
        print line
        next
      }
      if (in_app && line ~ "^[^[:space:]#].*:[[:space:]]*$") {
        in_app = 0
      }
      if (in_app && replaced == 0 && line ~ "^[[:space:]]+tag:[[:space:]]*\"?[^\"[:space:]]+\"?") {
        sub(/tag:[[:space:]]*\"?[^\"[:space:]]+\"?/, "tag: \"" new_tag "\"", line)
        replaced = 1
      }
      print line
    }
    END {
      if (replaced == 0) {
        exit 42
      }
    }
  ' "$file" >"$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi

  mv "$tmp_file" "$file"
  return 0
}

CURRENT_TAG="$(extract_current_tag "${VALUES_FILE}" "${APP_YAML_KEY}")"
if [[ -z "${CURRENT_TAG}" ]]; then
  fail "Could not find current image tag in ${VALUES_REL_PATH} (${APP_YAML_KEY}.image.tag)"
fi

if [[ "${CURRENT_TAG}" == "${IMAGE_TAG}" ]]; then
  log "No change needed (${APP_NAME}: ${CURRENT_TAG})"
  exit 0
fi

BACKUP_FILE=""
if [[ "${DRY_RUN}" == "true" ]]; then
  BACKUP_FILE="$(mktemp)"
  cp "${VALUES_FILE}" "${BACKUP_FILE}"
fi

update_tag "${VALUES_FILE}" "${APP_YAML_KEY}" "${IMAGE_TAG}" || \
  fail "Failed to update ${APP_YAML_KEY}.image.tag in ${VALUES_REL_PATH}"

if [[ "${DRY_RUN}" == "true" ]]; then
  log "Dry-run mode enabled. Showing diff only."
  git -C "${REPO_DIR}" --no-pager diff -- "${VALUES_REL_PATH}"
  mv "${BACKUP_FILE}" "${VALUES_FILE}"
  exit 0
fi

git -C "${REPO_DIR}" add "${VALUES_REL_PATH}"

if git -C "${REPO_DIR}" diff --cached --quiet; then
  log "No staged change after update; exiting."
  exit 0
fi

COMMIT_MSG="ci(gitops): bump ${APP_NAME} image to ${IMAGE_TAG}"
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
