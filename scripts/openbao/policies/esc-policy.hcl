# ESC (External Secrets Controller) Policy
# External Secrets Operator가 OpenBao의 시크릿을 읽을 수 있는 최소 권한 정책
# 현재 Helm 차트 구성에 맞춰 작성됨

# ============================================
# 서버 환경 변수 시크릿 (KV v2)
# ============================================

# Staging 서버 시크릿 읽기
path "secret/data/server/staging" {
  capabilities = ["read"]
}

path "secret/metadata/server/staging" {
  capabilities = ["read"]
}

# Production 서버 시크릿 읽기
path "secret/data/server/production" {
  capabilities = ["read"]
}

path "secret/metadata/server/production" {
  capabilities = ["read"]
}

# Default 서버 시크릿 읽기 (필요시)
path "secret/data/server/default" {
  capabilities = ["read"]
}

path "secret/metadata/server/default" {
  capabilities = ["read"]
}

# Cluster 레벨 시크릿 읽기 (GITHUB 인증 등 전역 시크릿)
path "secret/data/server/cluster" {
  capabilities = ["read"]
}

path "secret/metadata/server/cluster" {
  capabilities = ["read"]
}

# 서버 시크릿 리스트 조회 (트러블슈팅용)
path "secret/metadata/server" {
  capabilities = ["list"]
}

# ============================================
# Harbor Registry 인증 시크릿 (KV v2)
# ============================================

# Staging Harbor 시크릿 읽기
path "secret/data/harbor/staging" {
  capabilities = ["read"]
}

path "secret/metadata/harbor/staging" {
  capabilities = ["read"]
}

# Production Harbor 시크릿 읽기
path "secret/data/harbor/production" {
  capabilities = ["read"]
}

path "secret/metadata/harbor/production" {
  capabilities = ["read"]
}

# Development Harbor 시크릿 읽기 (필요시)
path "secret/data/harbor/development" {
  capabilities = ["read"]
}

path "secret/metadata/harbor/development" {
  capabilities = ["read"]
}

# Harbor 시크릿 리스트 조회
path "secret/metadata/harbor" {
  capabilities = ["list"]
}

# ============================================
# 향후 확장 가능 경로 (주석 처리)
# ============================================

# 애플리케이션별 시크릿이 필요한 경우 아래 주석 해제
# path "secret/data/plate-api/*" {
#   capabilities = ["read", "list"]
# }
#
# path "secret/metadata/plate-api/*" {
#   capabilities = ["read", "list"]
# }
#
# path "secret/data/plate-web/*" {
#   capabilities = ["read", "list"]
# }
#
# path "secret/metadata/plate-web/*" {
#   capabilities = ["read", "list"]
# }
#
# path "secret/data/plate-cache/*" {
#   capabilities = ["read", "list"]
# }
#
# path "secret/metadata/plate-cache/*" {
#   capabilities = ["read", "list"]
# }
#
# path "secret/data/plate-llm/*" {
#   capabilities = ["read", "list"]
# }
#
# path "secret/metadata/plate-llm/*" {
#   capabilities = ["read", "list"]
# }

# ============================================
# 토큰 자체 관리 권한
# ============================================

# 토큰 자체 정보 조회 (헬스체크, 디버깅용)
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# 토큰 갱신 권한 (TTL 연장, 자동 갱신용)
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# ============================================
# 시스템 헬스체크 (선택사항)
# ============================================

# OpenBao 헬스 상태 확인
path "sys/health" {
  capabilities = ["read"]
}

# ============================================
# 보안 노트
# ============================================
# 1. 이 정책은 읽기 전용(read-only) 권한만 부여합니다
# 2. 시크릿 생성, 수정, 삭제 권한은 없습니다
# 3. 특정 경로만 접근 가능하도록 제한되어 있습니다
# 4. 토큰은 자동 갱신 가능하도록 설정되어야 합니다
