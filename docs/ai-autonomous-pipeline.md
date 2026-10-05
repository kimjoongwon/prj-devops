# AI 자율 개발·배포 파이프라인 — 설계 문서 (계획)

작성: 2026-10-05 · 상태: **Phase 0~4 전 단계 미구축** (설계 확정, 구축 대기)
작업 기록: ZCode 세션 2026-10-04~05 (계획 수립 + 키 등록까지 완료)

## 목적

- AI 에이전트(ZCode)가 작업·리뷰 루프·배포 추적까지 전 과정 수행
- 사람은 **결정 3곳만**: ① stg 병합 승인 ② prod 병합 승인 ③ 리뷰 루프 3회 초과 시 판단
- 구조: `stg → main(prod)` · 작업은 git worktree 격리 · 배포는 기존 Jenkins+ArgoCD+Buzz 자산 재사용

## 전체 흐름

```
사용자: 작업 지시
   ▼
① ZCode: worktree 작업 → feature 브랜치 → PR (feature → stg)
   ▼
② 리뷰 게이트 (병행)
   ├─ PR-Agent (Jenkins 리뷰 잡, 도커): /review + /improve → PR 인라인 코멘트
   └─ Jenkins 결정적 CI: lint / typecheck / test / build  ← 진짜 게이트
   ▼
③ ZCode: 리뷰 코멘트 자동 수정 → 재푸시 → 재리뷰 (상한 3회)
   ├─ 초과/판단 필요 → 【결정 ③】사용자 질의
   └─ 신규 critical 없음 + CI 그린 → 【결정 ①】stg 병합 승인 요청 (Buzz 알림)
   ▼
④ 사용자: GitHub PR 승인·머지
   ▼
⑤ stg 자동 배포: Jenkins 빌드 → Harbor stg/<앱> (태그=SHA 12자)
   → prj-deploy stg/<앱>.yaml 태그 범프 → ArgoCD 자동 배포
   → Buzz #cicd: 빌드/배포/Degraded 알림 (buzz-gateway 재사용)
   ▼
⑥ ZCode: 배포 추적 (ArgoCD Synced+Healthy, Grafana 지표) — 이상 시 즉시 Buzz+분석
   ▼
⑦ stg 안정 판정 → ZCode가 prod PR (stg → main) 생성
   ▼
⑧ 【결정 ②】prod 승인 → ⑤와 동일 자동 배포·모니터링
```

## 결정 로그 (2026-10-04~05)

| 주제 | 결정 | 이유 |
|---|---|---|
| 코드 리뷰 도구 | **PR-Agent** ([The-PR-Agent/pr-agent](https://github.com/The-PR-Agent/pr-agent), MIT, ~13.3k★) | 오픈소스 self-host 무료·무제한 + GitHub PR 연동 조건을 만족하는 사실상 유일 후보. 2026년 Qodo→커뮤니티 기증 이관(활동 유지) |
| 리뷰어 = ZCode 자체 | **기각** | zcode CLI 무헤드 실행 시 인증 전파 실패(코딩플랜 OAuth가 프로세스 간 전파 안 됨) + 작업자=리뷰어 편향 |
| 리뷰 실행 위치 | **Jenkins** (당초 GH Actions안에서 변경) | **OpenBao 시크릿 일원화**를 위해 — GH Actions는 외부라 OpenBao 접근 불가, GitHub Secrets 이중 보관 발생 |
| 리뷰 LLM | z.ai 종량제 API (코딩플랜 불가) | 코딩플랜은 OAuth 구독·코딩도구 전용 약관이라 서드파티 CI 불가. 종량제 키로 리뷰 모델을 작업 모델과 분리 가능(편향 감소) |
| 시크릿 저장 | `secret/devops/pr-agent-llm` | buzz-gateway 선례 따름. 소비처: Jenkins credential 'pr-agent-llm-zai' (Phase 1 등록 예정) |

## Phase별 구축 계획

| Phase | 내용 | 완료 기준 | 상태 |
|---|---|---|---|
| 0 | GitHub 브랜치 보호 — `stg`/`main` 직접 푸시 차단, PR 필수 | 직접 push 거부 확인 | ⏸ 대기 (gh auth 필요) |
| 1 | Jenkins PR 리뷰 잡: PR-Agent 도커 실행(버전 고정), OpenBao 키 주입, `extra_instructions` 체크리스트(AGENTS.md와 동기), CI를 required check로 | 테스트 PR에 리뷰 자동 부착, CI 그린 경우만 병합 | ⏸ 대기 (키 검증 완료) |
| 2 | stg CI/CD: Jenkinsfile stg 분기 → Harbor stg 푸시 → `update-gitops-image-tag.sh` prj-deploy stg 범프 → ArgoCD + stg 앱 4종 Buzz 구독 | stg 머지 → #cicd 배포 완료 알림까지 무개입 | ⏸ 대기 |
| 3 | prj-core AGENTS.md 표준 절차 커밋 + agent-bot 승인 요청 Buzz 알림 (nostr 키·초대 = 사람 1회) | 문서만 읽고 ZCode가 전 절차 수행 | ⏸ 대기 |
| 4 | stg→prod 승격 자동화 (안정 판정 기준 문서화 → prod PR 자동 생성) | 사람은 승인 버튼만 | ⏸ 대기 |

## 시크릿 관리 (OpenBao 일원화)

- **`secret/devops/pr-agent-llm`** (2026-10-05 등록·같은 날 재발급 키로 교체): `zai-api-key` · `zai-api-base`(https://api.z.ai/api/paas/v4) · `model`(glm-5.2) · `note`
- **인증검증 완료 (2026-10-05)**: models API로 키 동작 확인 (glm-4.5~glm-5.3 계열 11종 노출)
- **리뷰 모델 = glm-5.2** — 작업 모델(GLM-5.3)과 분리해 편향 감소. 대안: glm-5.3(최상급)/glm-5.3-flash(저비용) — Phase 1 튜닝 시 note의 값만 교체
- 소비처는 Phase 1에서 Jenkins credential 사본 등록 시 `docs/credentials-map`(OpenBao `secret/docs/credentials-map`)의 [AI 리뷰 LLM 키] 항목과 짝 관리

## 안전장치

- 리뷰는 독립 도구 + 진짜 게이트는 결정적 CI → PR-Agent 장애 시 파이프라인 무영향
- AI 실수 푸시 → 브랜치 보호가 구조적 차단 (Phase 0)
- 배포 이상 → ArgoCD Degraded 즉시 Buzz + prj-deploy 태그 revert로 자동 롤백
- 알림은 best-effort (buzz-gateway 장애가 배포를 막지 않음 — 기존 설계)

## 차단 목록 (다음 세션 착수 조건)

1. `gh auth login` (Phase 0 착수 전제)
2. Phase 3 시점: agent-bot nostr 키 발급 + #cicd 초대 (사람 작업)
3. Phase 4 시점: 승격 안정 기준 수치 확정 (기본값 제안 후 선택)
