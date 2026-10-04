# AI Operator Policy — 운영 AI가 OpenBao만 보고 작업을 완수하기 위한 정책
#
# 용도: secret/docs/* (운영 지식)와 모든 시크릿을 읽고, 시크릿을 수정(rotation)할 수 있다.
# 시스템 영역(sys, auth, 정책 변경)은 접근 불가 — 권한 상승 불가 구조.
# 모든 접근은 감사 로그(/openbao/data/audit.log)에 기록된다.
# 토큰: period 168h — 사용 전마다 `bao token renew` 갱신 (만료 7일 내 재사용 시 연장).

# ============================================
# KV 시크릿 전체 읽기/쓰기 (시크릿 + 운영 문서)
# ============================================
path "secret/data/*" {
  capabilities = ["read", "create", "update", "delete"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata" {
  capabilities = ["list"]
}

# ============================================
# 토큰 자체 관리 (셀프 갱신/조회)
# ============================================
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# ============================================
# 시스템 헬스체크
# ============================================
path "sys/health" {
  capabilities = ["read"]
}

# ============================================
# 보안 노트
# ============================================
# 1. 이 정책은 sys/auth/identity 접근이 없어 권한 상승이 불가능하다
# 2. unseal 키·root 토큰은 이 정책으로 접근할 수 없다 (부트스트랩 카드에만 존재)
# 3. Cloudflare 대시보드/GitHub UI/서버 SSH 조작은 OpenBao 밖 영역 —
#    절차는 secret/docs/runbooks/* 를 참조
