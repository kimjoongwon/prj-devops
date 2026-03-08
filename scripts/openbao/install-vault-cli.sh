#!/bin/bash
set -e

# Vault CLI 자동 설치 스크립트
# OpenBao 사용을 위한 Vault CLI 설치

VAULT_VERSION="${VAULT_VERSION:-1.18.3}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

echo "🔧 Vault CLI 설치 스크립트"
echo "버전: $VAULT_VERSION"
echo "설치 경로: $INSTALL_DIR"
echo ""

# OS 및 아키텍처 감지
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$OS" in
  linux*)
    OS="linux"
    ;;
  darwin*)
    OS="darwin"
    ;;
  *)
    echo "❌ 지원하지 않는 OS: $OS"
    exit 1
    ;;
esac

case "$ARCH" in
  x86_64)
    ARCH="amd64"
    ;;
  aarch64|arm64)
    ARCH="arm64"
    ;;
  *)
    echo "❌ 지원하지 않는 아키텍처: $ARCH"
    exit 1
    ;;
esac

echo "감지된 시스템: $OS $ARCH"
echo ""

# 이미 설치되어 있는지 확인
if command -v vault &> /dev/null; then
  CURRENT_VERSION=$(vault version | head -n1 | awk '{print $2}' | sed 's/v//')
  echo "⚠️  Vault CLI가 이미 설치되어 있습니다: v$CURRENT_VERSION"
  read -p "재설치하시겠습니까? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "설치를 취소합니다."
    exit 0
  fi
fi

# 임시 디렉토리 생성
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

echo "📥 Step 1: Vault CLI 다운로드 중..."
DOWNLOAD_URL="https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_${OS}_${ARCH}.zip"
echo "URL: $DOWNLOAD_URL"

if command -v curl &> /dev/null; then
  curl -LO "$DOWNLOAD_URL"
elif command -v wget &> /dev/null; then
  wget "$DOWNLOAD_URL"
else
  echo "❌ curl 또는 wget이 필요합니다."
  exit 1
fi

echo "✅ 다운로드 완료"
echo ""

echo "📦 Step 2: 압축 해제 중..."
unzip -q "vault_${VAULT_VERSION}_${OS}_${ARCH}.zip"
echo "✅ 압축 해제 완료"
echo ""

echo "🔧 Step 3: 설치 중..."
chmod +x vault

# sudo 권한 확인
if [ -w "$INSTALL_DIR" ]; then
  mv vault "$INSTALL_DIR/"
else
  echo "관리자 권한이 필요합니다..."
  sudo mv vault "$INSTALL_DIR/"
fi

echo "✅ 설치 완료"
echo ""

# 정리
cd - > /dev/null
rm -rf "$TMP_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Vault CLI 설치 성공!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
vault version
echo ""

# 자동 완성 설치 제안
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 다음 단계"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. 자동 완성 활성화 (선택사항):"
echo "   vault -autocomplete-install"
if [ -n "$BASH_VERSION" ]; then
  echo "   source ~/.bashrc"
elif [ -n "$ZSH_VERSION" ]; then
  echo "   source ~/.zshrc"
fi
echo ""
echo "2. OpenBao 서버 주소 설정:"
echo "   export VAULT_ADDR=https://openbao.cocdev.co.kr"
echo ""
echo "   영구 설정 (bash):"
echo "   echo 'export VAULT_ADDR=https://openbao.cocdev.co.kr' >> ~/.bashrc"
echo "   source ~/.bashrc"
echo ""
echo "   영구 설정 (zsh):"
echo "   echo 'export VAULT_ADDR=https://openbao.cocdev.co.kr' >> ~/.zshrc"
echo "   source ~/.zshrc"
echo ""
echo "3. 연결 테스트:"
echo "   vault status"
echo ""
echo "4. 로그인:"
echo "   vault login"
echo ""
echo "5. 시크릿 읽기:"
echo "   vault kv get secret/core-api/staging"
echo ""
