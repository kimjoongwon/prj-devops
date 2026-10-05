# AI 자율 개발·배포 파이프라인 — 설계·구축 문서

작성: 2026-10-05 · 갱신: 2026-10-05 (Phase 0 완료, Phase 1 구축 완료·검증 대기)
원본 논의: ZCode 세션 2026-10-04~05

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
   ├─ pr-agent (클러스터 서비스): PR opened/synchronize → /review + /improve → PR 인라인 코멘트
   └─ 결정적 CI(lint/test): Phase 2에서 stg CI와 함께 구축  ← 진짜 게이트
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

## Phase별 상태

| Phase | 내용 | 상태 |
|---|---|---|
| 0 | GitHub 브랜치 보호 | ✅ **완료 (2026-10-05)** — `stg`/`main`: PR 필수(승인 0), 관리자 포함 직접 푸시 차단, force push/삭제 차단. 승인 0인 이유: PR 작성자=사용자 계정이라 자기 승인 불가(교착 방지), 병합 버튼 자체가 결정 지점 |
| 1 | pr-agent 리뷰 게이트 | 🟡 **구축 완료·검증 대기** — 전 구간 동작 확인, 유일 블로커: z.ai 계정 잔액 |
| 2 | stg CI/CD 자동화 | ⏸ 대기 |
| 3 | AGENTS.md 표준 절차 + agent-bot 승인 요청 알림 | ⏸ 대기 |
| 4 | stg→prod 승격 자동화 | ⏸ 대기 |

## Phase 1 as-built (2026-10-05)

### 구성 (buzz-gateway 패턴)

| 구성요소 | 위치/값 |
|---|---|
| 워크로드 | `helm/development-tools/pr-agent` — Deployment+Service (ns `devops-tools`, ArgoCD App `pr-agent`) |
| 이미지 | `pragent/pr-agent:0.47.0-github_app` (pinned, Docker Hub) |
| 인증 모드 | **user(PAT)** — `.secrets.toml` `[github] deployment_type="user"` + `override_deployment_type=false` (true면 서버가 강제 app 모드로 덮어써 실패함) |
| GitHub 연결 | repo webhook `prj-core` id 692246651 — events `pull_request`, URL `https://onjitda.com/api/pr-agent/api/v1/github_webhooks` |
| 라우팅 | ingress `onjitda.com /api/pr-agent`(Prefix) → `argocd-webhook-proxy` nginx(`/api/pr-agent/` location) → `pr-agent.devops-tools:80`(→파드 3000). **포트 주의: Service 80→3000 매핑** |
| LLM | z.ai 종량제 `glm-5.2` (`api.z.ai/api/paas/v4`, openai 호환. `custom_model_max_tokens=131072`) — 작업 모델 GLM-5.3과 분리 |
| 자동 명령 | opened/reopened → `/review`,`/improve` (`pr_commands`) · synchronize → 재리뷰 (`handle_push_trigger=true` + `push_commands`) — 자동수정 루프 지원 |
| 리뷰 체크리스트 | `pr_reviewer.extra_instructions` (버그·보안·에러처리·성능·테스트 우선) |

### 시크릿 (OpenBao 일원화)

- `secret/devops/pr-agent-llm` — z.ai 키·엔드포인트·모델 (v4)
- `secret/devops/pr-agent-github` — PAT(user_token)·webhook_secret (v1)
- k8s `devops-tools/pr-agent-secrets` = 위 두 값을 조합한 `.secrets.toml` (수동 관리, buzz-gateway 패턴)
- **교체 절차**: OpenBao 값 갱신 → k8s 시크릿 재생성(스크립트는 아래) → `kubectl -n devops-tools rollout restart deploy/pr-agent`

```bash
# .secrets.toml 재생성 (OpenBao에서 값 읽어 조합)
kubectl -n devops-tools create secret generic pr-agent-secrets \
  --from-file=.secrets.toml=<(OpenBao 값으로 만든 파일) --dry-run=client -o yaml | kubectl apply -f -
kubectl -n devops-tools rollout restart deploy/pr-agent
```

### 구축 중 결정·해결 이력

| 문제 | 해결 |
|---|---|
| GH Actions vs Jenkins vs 서비스 | **클러스터 내 상시 서비스로 확정** — OpenBao 일원화(ESO 패턴) + 웹훅이 pr-agent 공식 배포 방식 |
| base 이미지(0.47.0)가 CLI라 바로 종료 | `0.47.0-github_app`(gunicorn 웹훅 서버) 타깃으로 교체 |
| app 모드 "installation ID required" | repo 웹훅 payload엔 installation 필드 없음 → user(PAT) 모드로 전환 (`override_deployment_type=false`) |
| "MAX_TOKENS 미정의" | `config.custom_model_max_tokens=131072` (GLM-5.2 128K) |
| nginx → pr-agent 타임아웃 | Service가 80→3000 매핑이라 upstream은 **80** (3000 직접 지정 금지) |
| **현재 블로커** | z.ai 응답 `Insufficient balance or no resource package. Please recharge` — 키·설정·웹훅 전체 정상, **계정 재충전 필요** |

### 부수 변경 (주의·기록)

- **coc-devops GitHub App의 웹훅 URL 교체**: 기존 `https://jenkins.cocdev.co.kr/github-webhook`(2026-09-18 도메인 만료 후 죽은 상태였음) → pr-agent URL. 구 소비자는 없었음(Jenkins 트리거는 2026-10-04 repo 웹훅 push-router로 이전 완료). 앱 이벤트 구독은 기존 `push` 그대로 유지.
- 테스트 PR: `prj-core#1` (ci/pr-agent-gate-test, worktree ~/dev/wt/pr-agent-test) — 재충전 후 reopen하면 리뷰가 게시되는 종단 재검증용으로 유지.

## 재검증 절차 (z.ai 재충전 후)

1. z.ai 콘솔에서 잔액/리소스 패키지 충전
2. `gh pr close 1 -R kimjoongwon/prj-core && gh pr reopen 1 -R kimjoongwon/prj-core`
3. ~1분 내 PR에 /review + /improve 코멘트 게시 확인 (`kubectl -n devops-tools logs deploy/pr-agent -f`)
4. 정상이면 Phase 1 완료 선언, OpenBao `pr-agent-llm` note의 ⚠ 문구 삭제

## 이후 Phase (변경 없음)

- **Phase 2**: Jenkinsfile stg 분기 → Harbor stg 이미지 → prj-deploy stg 범프 → ArgoCD + stg 앱 4종 Buzz 구독. 결정적 CI(lint/test)도 이때 PR 체크로 추가 → Phase 0 보호규칙에 required check 지정
- **Phase 3**: prj-core AGENTS.md 표준 절차 + agent-bot 승인 요청 Buzz 알림 (nostr 키 발급 = 사람 1회)
- **Phase 4**: 승격 안정 기준 → prod PR 자동 생성

## 안전장치

- 리뷰는 독립 도구 + 진짜 게이트는 결정적 CI(Phase 2) → pr-agent 장애 시 파이프라인 무영향
- AI 실수 푸시 → 브랜치 보호가 구조적 차단 (Phase 0, 관리자 포함)
- 배포 이상 → ArgoCD Degraded 즉시 Buzz + prj-deploy 태그 revert로 자동 롤백
- 알림은 best-effort (buzz-gateway 장애가 배포를 막지 않음 — 기존 설계)
