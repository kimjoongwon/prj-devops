#!/usr/bin/env bash
set -euo pipefail

# Bootstrap mikefarah yq (v4.18+) for the GitOps image-bump tooling.
#
# - If a compatible yq is already on PATH: no-op.
# - Otherwise: download a pinned release binary (sha256-verified) into
#   <prefix>/bin and verify it runs. Callers must prepend <prefix>/bin to PATH.
#
# Designed for ephemeral Jenkins agents (kubernetes jnlp pods) where a
# pre-installed yq cannot be assumed. Pinned to YQ_VERSION below.

SCRIPT_NAME="$(basename "$0")"

YQ_VERSION="${YQ_VERSION:-v4.53.6}"
YQ_BASE_URL="${YQ_BASE_URL:-https://github.com/mikefarah/yq/releases/download}"
# sha256 of the bare release binaries, per platform
YQ_SHA256_LINUX_AMD64="c5f056448f973ae7d39b5401949648a78f2dc1947d6a8eb65be60d5c504b9385"
YQ_SHA256_LINUX_ARM64="88a1016bc1d657375a35864e4f44b6f333df8ff97b559f51bba0adcb2169df09"
YQ_SHA256_DARWIN_AMD64="caa513cb04f3804b34d4752f0e0d7904fecb9e7cf1d34081289f83259319a7f6"
YQ_SHA256_DARWIN_ARM64="cceb0b8d71ea5294334121f8429f33f92b920e7217d904a2f9f35443968ac424"
PREFIX="${PREFIX:-.tools}"

print_usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} [--prefix DIR]

Installs a pinned mikefarah yq (${YQ_VERSION}) into <prefix>/bin unless a
compatible yq (v4.18+) is already on PATH. sha256-verified download.

Options:
  --prefix DIR    Install prefix (default: ${PREFIX})

Environment variables:
  PREFIX, YQ_VERSION, YQ_BASE_URL
EOF
}

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

fail() {
  printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="${2:-}"
      shift 2
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
[[ -n "${PREFIX}" ]] || fail "--prefix must not be empty"

yq_version_ok() {
  command -v yq >/dev/null 2>&1 || return 1
  yq --version 2>/dev/null | grep -Eqi 'mikefarah|v4\.(1[8-9]|[2-9][0-9])'
}

if yq_version_ok; then
  log "Compatible yq already on PATH ($(yq --version)). Nothing to do."
  exit 0
fi

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64)
    YQ_ASSET="yq_linux_amd64"; WANT_SHA="${YQ_SHA256_LINUX_AMD64}" ;;
  Linux/aarch64|Linux/arm64)
    YQ_ASSET="yq_linux_arm64"; WANT_SHA="${YQ_SHA256_LINUX_ARM64}" ;;
  Darwin/x86_64)
    YQ_ASSET="yq_darwin_amd64"; WANT_SHA="${YQ_SHA256_DARWIN_AMD64}" ;;
  Darwin/arm64)
    YQ_ASSET="yq_darwin_arm64"; WANT_SHA="${YQ_SHA256_DARWIN_ARM64}" ;;
  *)
    fail "Unsupported platform: $(uname -s) $(uname -m)" ;;
esac

BIN_DIR="${PREFIX}/bin"
TARGET="${BIN_DIR}/yq"
URL="${YQ_BASE_URL}/${YQ_VERSION}/${YQ_ASSET}"

mkdir -p "${BIN_DIR}"

log "Downloading ${URL} -> ${TARGET}"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL -o "${TARGET}.tmp" "${URL}"
elif command -v wget >/dev/null 2>&1; then
  wget -q -O "${TARGET}.tmp" "${URL}"
else
  fail "Neither curl nor wget is available to download yq"
fi

GOT_SHA="$( (shasum -a 256 "${TARGET}.tmp" 2>/dev/null || sha256sum "${TARGET}.tmp") | awk '{print $1}' )"
if [[ "${GOT_SHA}" != "${WANT_SHA}" ]]; then
  rm -f "${TARGET}.tmp"
  fail "sha256 mismatch for ${URL}: got '${GOT_SHA}', want '${WANT_SHA}'"
fi

chmod +x "${TARGET}.tmp"
mv "${TARGET}.tmp" "${TARGET}"
"${TARGET}" --version >/dev/null
log "Installed: ${TARGET} ($("${TARGET}" --version))"
log "Prepend to PATH: export PATH=\"${BIN_DIR}:\${PATH}\""
