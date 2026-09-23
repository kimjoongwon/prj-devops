#!/usr/bin/env bash
set -euo pipefail

# Roll back an application image by reverting its latest gitops image-bump commits.
# Finds "ci(gitops): bump <app> image to <tag>" commits on the target branch,
# reverts them (newest first), and pushes so ArgoCD redeploys the previous image.
#
# Usage: ./scripts/rollback.sh --app core-api [--steps 1] [--dry-run] [--skip-push]
#
# Requires mikefarah yq v4.18+ (same as scripts/jenkins/update-gitops-image-tag.sh).

SCRIPT_NAME="$(basename "$0")"

APP_NAME="${APP_NAME:-}"
STEPS="${STEPS:-1}"
REPO_URL="${REPO_URL:-https://github.com/kimjoongwon/prj-devops.git}"
TARGET_BRANCH="${TARGET_BRANCH:-main}"
GIT_USER_NAME="${GIT_USER_NAME:-gitops-rollback}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-gitops-rollback@local}"
PUSH_RETRIES="${PUSH_RETRIES:-3}"
WORKDIR="${WORKDIR:-}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_PUSH="${SKIP_PUSH:-false}"
FORCE="${FORCE:-false}"

print_usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} --app <name> [options]

Reverts the latest image-bump commit(s) for the app and pushes, so ArgoCD
redeploys the previous image. Rollback of N steps reverts the N newest
"ci(gitops): bump <app> image to <tag>" commits.

Required:
  --app <name>                 App name (idp-api|idp-web|core-api|admin-web|proposal-web|tool-storybook)

Options:
  --steps <n>                  Number of bump commits to revert (default: 1)
  --repo-url <url>             GitOps repository URL (default: ${REPO_URL})
  --branch <name>              Branch to read/revert/push (default: ${TARGET_BRANCH})
  --git-user-name <name>       Revert commit author name (default: ${GIT_USER_NAME})
  --git-user-email <email>     Revert commit author email (default: ${GIT_USER_EMAIL})
  --push-retries <n>           Number of push retries with pull --rebase (default: ${PUSH_RETRIES})
  --workdir <path>             Use existing checkout directory instead of cloning
  --dry-run                    Show the revert diff and target tag; no commit/push
  --skip-push                  Commit only, do not push
  --force                      Skip safety checks (tag mismatch, dirty workdir, extra files in bump commit)
  -h, --help                   Show this help

Environment variable alternatives:
  APP_NAME, STEPS, REPO_URL, TARGET_BRANCH, GIT_USER_NAME, GIT_USER_EMAIL,
  PUSH_RETRIES, WORKDIR, DRY_RUN, SKIP_PUSH, FORCE

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
    --steps)
      STEPS="${2:-}"
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
    --force)
      FORCE="true"
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
[[ "${STEPS}" =~ ^[1-9][0-9]*$ ]] || fail "--steps must be a positive integer"
[[ "${PUSH_RETRIES}" =~ ^[0-9]+$ ]] || fail "--push-retries must be a non-negative integer"

DRY_RUN="$(normalize_bool "${DRY_RUN}")"
SKIP_PUSH="$(normalize_bool "${SKIP_PUSH}")"
FORCE="$(normalize_bool "${FORCE}")"
require_yq

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
  proposal-web)
    VALUES_REL_PATH="helm/applications/proposal-web/values-prod.yaml"
    APP_YAML_KEY="proposal-web"
    ;;
  tool-storybook)
    VALUES_REL_PATH="helm/applications/tool-storybook/values-prod.yaml"
    APP_YAML_KEY="tool-storybook"
    ;;
  *)
    fail "Unsupported app '${APP_NAME}'. Allowed: idp-api, idp-web, core-api, admin-web, proposal-web, tool-storybook"
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
  git clone --depth 50 --branch "${TARGET_BRANCH}" "${REPO_URL}" "${REPO_DIR}" >/dev/null
fi

VALUES_FILE="${REPO_DIR}/${VALUES_REL_PATH}"
[[ -f "${VALUES_FILE}" ]] || fail "Values file not found: ${VALUES_FILE}"

git -C "${REPO_DIR}" config user.name "${GIT_USER_NAME}"
git -C "${REPO_DIR}" config user.email "${GIT_USER_EMAIL}"

if [[ "${FORCE}" != "true" ]]; then
  if ! git -C "${REPO_DIR}" diff --quiet || ! git -C "${REPO_DIR}" diff --cached --quiet; then
    fail "Workdir has uncommitted changes: ${REPO_DIR}. Commit/stash first, or use --force."
  fi
fi

read_current_tag() {
  local tag
  # App keys contain '-', so bracket notation is required in yq expressions
  tag="$(yq eval ".[\"${APP_YAML_KEY}\"].image.tag" "${VALUES_FILE}")"
  if [[ -z "${tag}" || "${tag}" == "null" ]]; then
    return 1
  fi
  printf '%s' "${tag}"
}

CURRENT_TAG="$(read_current_tag || fail "Could not read current image tag (${APP_YAML_KEY}.image.tag) in ${VALUES_REL_PATH}")"

BUMP_SUBJECT_PREFIX="ci(gitops): bump ${APP_NAME} image to "
BUMP_LOG=()
while IFS= read -r entry; do
  BUMP_LOG+=("${entry}")
done < <(git -C "${REPO_DIR}" log --fixed-strings --grep="${BUMP_SUBJECT_PREFIX}" --format='%H|%s' -n "${STEPS}" "${TARGET_BRANCH}")

if [[ "${#BUMP_LOG[@]}" -lt "${STEPS}" ]]; then
  fail "Found only ${#BUMP_LOG[@]} bump commit(s) for '${APP_NAME}' on ${TARGET_BRANCH}, need ${STEPS}."
fi

SHAS=()
for entry in "${BUMP_LOG[@]}"; do
  sha="${entry%%|*}"
  subject="${entry#*|}"

  if [[ "${FORCE}" != "true" ]]; then
    touched="$(git -C "${REPO_DIR}" show --name-only --format= "${sha}")"
    if [[ "${touched}" != "${VALUES_REL_PATH}" ]]; then
      fail "Bump commit ${sha} touched other files besides ${VALUES_REL_PATH}. Inspect it manually or use --force."
    fi
  fi

  SHAS+=("${sha}")
  log "Will revert: ${subject}"
done

NEWEST_SUBJECT="${BUMP_LOG[0]#*|}"
NEWEST_TAG="${NEWEST_SUBJECT##* }"

if [[ "${FORCE}" != "true" && "${CURRENT_TAG}" != "${NEWEST_TAG}" ]]; then
  fail "Current tag '${CURRENT_TAG}' does not match the newest bump '${NEWEST_TAG}'. The values file was likely edited since. Inspect manually or use --force."
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  git -C "${REPO_DIR}" revert --no-commit "${SHAS[@]}"
  RESULT_TAG="$(read_current_tag || echo unknown)"
  log "Dry-run mode. ${APP_NAME}: ${CURRENT_TAG} -> ${RESULT_TAG} (reverting ${STEPS} bump(s)). Diff:"
  git -C "${REPO_DIR}" --no-pager diff HEAD -- "${VALUES_REL_PATH}" || true
  git -C "${REPO_DIR}" revert --quit >/dev/null 2>&1 || true
  git -C "${REPO_DIR}" reset --hard >/dev/null
  exit 0
fi

git -C "${REPO_DIR}" revert --no-edit "${SHAS[@]}" >/dev/null
RESULT_TAG="$(read_current_tag || fail "Could not read tag after revert")"
log "Reverted ${STEPS} bump commit(s): ${APP_NAME} ${CURRENT_TAG} -> ${RESULT_TAG}"

if [[ "${SKIP_PUSH}" == "true" ]]; then
  log "skip-push mode enabled. Revert commits created locally only."
  exit 0
fi

push_with_retry() {
  local attempt=1
  while (( attempt <= PUSH_RETRIES )); do
    log "Push attempt ${attempt}/${PUSH_RETRIES}"
    if git -C "${REPO_DIR}" pull --rebase origin "${TARGET_BRANCH}" >/dev/null 2>&1; then
      if git -C "${REPO_DIR}" push origin "HEAD:${TARGET_BRANCH}" >/dev/null 2>&1; then
        return 0
      fi
    else
      git -C "${REPO_DIR}" rebase --abort >/dev/null 2>&1 || true
    fi
    sleep $(( attempt * 2 ))
    attempt=$(( attempt + 1 ))
  done
  return 1
}

if [[ "${PUSH_RETRIES}" == "0" ]]; then
  git -C "${REPO_DIR}" push origin "HEAD:${TARGET_BRANCH}"
else
  push_with_retry || fail "Failed to push after ${PUSH_RETRIES} attempts"
fi

log "Pushed to origin/${TARGET_BRANCH}"
log "ArgoCD will pick up the revert (webhook, or within 3m polling) and redeploy ${APP_NAME}:${RESULT_TAG}"
