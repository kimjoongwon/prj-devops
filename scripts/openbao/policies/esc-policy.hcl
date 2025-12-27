# ESC (External Secrets Controller) Policy
# External Secrets Operator가 OpenBao의 시크릿을 읽을 수 있는 정책
# secret/data/* 하위 모든 경로에 읽기 권한 부여

# ============================================
# 모든 시크릿 읽기 권한 (KV v2)
# ============================================

# 모든 시크릿 데이터 읽기
# 예: secret/data/server/staging, secret/data/plate-admin/staging 등
path "secret/data/*" {
  capabilities = ["read"]
}

# 모든 시크릿 메타데이터 읽기
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}

# 루트 메타데이터 리스트 조회
path "secret/metadata" {
  capabilities = ["list"]
}

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
