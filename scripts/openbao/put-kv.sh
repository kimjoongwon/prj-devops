#!/bin/bash
set -e

# OpenBao KV2 Key-Value 등록 스크립트
# 폴더 선택 후 key-value를 저장합니다

OPENBAO_ADDR="${OPENBAO_ADDR:-http://localhost:8200}"
KV_MOUNT="${KV_MOUNT:-secret}"  # KV2 마운트 경로

echo "🔐 OpenBao KV2 Key-Value 등록"
echo "OpenBao 주소: $OPENBAO_ADDR"
echo "KV 마운트: $KV_MOUNT"
echo ""

# 현재 인증 확인
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Step 1: 인증 상태 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
vault token lookup > /dev/null 2>&1 || {
  echo "❌ OpenBao에 로그인되어 있지 않습니다."
  echo "다음 명령으로 로그인하세요:"
  echo "  export VAULT_ADDR=$OPENBAO_ADDR"
  echo "  vault login"
  exit 1
}
echo "✅ 인증 확인 완료"
echo ""

# 기존 폴더(경로) 목록 조회
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📂 Step 2: 기존 경로 목록"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 재귀적으로 모든 경로 탐색
list_paths() {
  local path="$1"
  local indent="$2"
  
  # 현재 경로의 하위 키 조회
  local keys=$(vault kv list -format=json "$KV_MOUNT/$path" 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
  
  for key in $keys; do
    if [[ "$key" == */ ]]; then
      # 폴더인 경우
      local folder_name="${key%/}"
      echo "${indent}📁 ${path}${folder_name}/"
      list_paths "${path}${folder_name}/" "  $indent"
    else
      # 키인 경우
      echo "${indent}📄 ${path}${key}"
    fi
  done
}

echo "현재 저장된 경로 목록:"
echo ""

# 루트 레벨 폴더 조회
ROOT_FOLDERS=$(vault kv list -format=json "$KV_MOUNT/" 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")

if [ -z "$ROOT_FOLDERS" ]; then
  echo "  (저장된 경로가 없습니다)"
else
  for folder in $ROOT_FOLDERS; do
    if [[ "$folder" == */ ]]; then
      folder_name="${folder%/}"
      echo "📁 $folder_name/"
      list_paths "$folder_name/" "  "
    else
      echo "📄 $folder"
    fi
  done
fi

echo ""

# 경로 선택
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 Step 3: 저장 경로 선택"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "저장할 경로를 입력하세요."
echo "  - 기존 경로 사용: server/staging"
echo "  - 새 경로 생성:   myapp/config (자동 생성됨)"
echo ""
read -p "경로 입력: " SECRET_PATH

if [ -z "$SECRET_PATH" ]; then
  echo "❌ 경로를 입력해주세요."
  exit 1
fi

# 경로 앞뒤 슬래시 정리
SECRET_PATH="${SECRET_PATH#/}"
SECRET_PATH="${SECRET_PATH%/}"

echo ""
echo "선택된 경로: $KV_MOUNT/$SECRET_PATH"
echo ""

# 기존 데이터 확인
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Step 4: 기존 데이터 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

EXISTING_DATA=$(vault kv get -format=json "$KV_MOUNT/$SECRET_PATH" 2>/dev/null || echo "")

if [ -n "$EXISTING_DATA" ] && [ "$EXISTING_DATA" != "" ]; then
  echo ""
  echo "⚠️  해당 경로에 기존 데이터가 있습니다:"
  echo ""
  echo "$EXISTING_DATA" | jq -r '.data.data | to_entries[] | "  \(.key) = \(.value)"' 2>/dev/null || echo "  (데이터 파싱 실패)"
  echo ""
  echo "새 키를 추가하면 기존 데이터와 병합됩니다."
  read -p "계속하시겠습니까? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "취소되었습니다."
    exit 0
  fi
else
  echo "새 경로입니다. 데이터가 새로 생성됩니다."
fi

echo ""

# Key-Value 입력
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔑 Step 5: Key-Value 입력"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "저장할 Key-Value를 입력하세요."
echo "여러 개 입력 시 한 줄에 하나씩 입력하고, 빈 줄을 입력하면 완료됩니다."
echo "형식: KEY=VALUE"
echo ""

declare -a KV_PAIRS=()

while true; do
  read -p "> " KV_INPUT
  
  if [ -z "$KV_INPUT" ]; then
    break
  fi
  
  # = 포함 여부 확인
  if [[ "$KV_INPUT" != *"="* ]]; then
    echo "  ⚠️  형식 오류. KEY=VALUE 형식으로 입력하세요."
    continue
  fi
  
  KV_PAIRS+=("$KV_INPUT")
  echo "  ✅ 추가됨"
done

if [ ${#KV_PAIRS[@]} -eq 0 ]; then
  echo ""
  echo "❌ 입력된 Key-Value가 없습니다."
  exit 1
fi

echo ""
echo "입력된 Key-Value 목록:"
for kv in "${KV_PAIRS[@]}"; do
  KEY="${kv%%=*}"
  VALUE="${kv#*=}"
  echo "  $KEY = $VALUE"
done

echo ""
read -p "저장하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "취소되었습니다."
  exit 0
fi

# 저장 실행
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💾 Step 6: 데이터 저장"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# vault kv patch 또는 put 명령 구성
if [ -n "$EXISTING_DATA" ] && [ "$EXISTING_DATA" != "" ]; then
  # 기존 데이터가 있으면 patch (병합)
  CMD="vault kv patch $KV_MOUNT/$SECRET_PATH"
else
  # 새 경로면 put
  CMD="vault kv put $KV_MOUNT/$SECRET_PATH"
fi

for kv in "${KV_PAIRS[@]}"; do
  CMD="$CMD \"$kv\""
done

echo "실행 명령: $CMD"
echo ""

# 실행
eval $CMD

echo ""
echo "✅ 저장 완료!"

# 최종 결과 출력
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Step 7: 최종 저장 정보"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📍 저장 경로: $KV_MOUNT/$SECRET_PATH"
echo ""
echo "📋 저장된 데이터:"
vault kv get "$KV_MOUNT/$SECRET_PATH"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔗 데이터 조회 명령어"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# 전체 데이터 조회"
echo "vault kv get $KV_MOUNT/$SECRET_PATH"
echo ""
echo "# 특정 필드만 조회"
for kv in "${KV_PAIRS[@]}"; do
  KEY="${kv%%=*}"
  echo "vault kv get -field=$KEY $KV_MOUNT/$SECRET_PATH"
done
echo ""
echo "# JSON 형식 조회"
echo "vault kv get -format=json $KV_MOUNT/$SECRET_PATH"
echo ""
