# prj-devops — AI 작업 규칙

인프라 IaC 저장소. **main 반영 = GitOps 자동 동기화 대상**. Jenkins·ArgoCD 등 upstream 도구는 수동 Helm 반영.
현재 연결 계약: [docs/deployment-map.md](docs/deployment-map.md) (2026-10-22 형상 기준, 런타임 상태 별도 검증).

## 인프라 접근 (전체 진입점)

- 워크스페이스 전체 지도·파이프라인: `~/dev/AGENTS.md` (최초 1회 읽을 것)
- OpenBao 접근 열쇠: `~/dev/onjitda-credentials.md`(부트스트랩 카드, git 밖) → 이후 `secret/docs/*`

## 구조

- `helm/` — 3계층: cluster-services(인프라) / development-tools(도구: jenkins·buzz-gateway·pr-agent·buildkitd·관측) / applications(앱)
- `environments/argocd/apps/` — ArgoCD Application 매니페스트 (부모 app-of-apps가 이 디렉터리 감시)
- `docs/` — 운영 문서. 특히 `ai-autonomous-pipeline.md`(배포 파이프라인), `buzz-ci-integration.md`(알림)

## 규칙

1. **직접 `kubectl apply` 금지** — GitOps 변경은 이 저장소 커밋·푸시로. 예외: 부트스트랩 부모 앱 스펙 변경 시에만 재적용.
2. **시크릿은 git에 두지 않는다** — 원본은 OpenBao(`secret/docs/credentials-map`의 짝 목록 참조).
   k8s 수동 시크릿(buzz-gateway-env, pr-agent-secrets, buildkit-*-config)은 "문서화된 런타임 사본" —
   로테이션 시 OpenBao와 k8s 양쪽 갱신 후 해당 파드 rollout restart.
3. **Jenkins는 기존 릴리스 namespace를 확인한 뒤 수동 helm** (`deploy-libraries.sh`는 `jenkins`를 사용해 현재 `devops-tools` 계약과 다름): `helm -n devops-tools upgrade jenkins jenkins/jenkins --version <pinned> -f helm/development-tools/jenkins/values.yaml`
   - 재시작 후: 범프 잡 파라미터 말소 → 실패 1회 후 자동 재등록, push-router는 1회 수동 실행 필요
   - GWT 토큰은 values에 없음(OpenBao→마운트→시드 주입). 로테이션 절차는 credentials-map
4. 이미지 태그는 `prj-deploy main`의 `prod|stg/<앱>.yaml`이 소유 — 여기서 태그 직접 수정 금지.
   부모·자식 Application은 prj-devops/prj-deploy 양쪽 `main`을 추적하며, 부모는 환경 exclude 없이 prod 8앱/stg 6앱을 포함한다.
   stg 빌드는 수동(`BRANCH_NAME=stg`), main push-router는 Storybook 제외 9개 잡 대상이다. Dolmen prod 태그/Application은 없다.
   범프 allowlist 10앱과 rollback.sh 지원(prod 기존 6앱/stg 기존 4앱)은 다르다. 미지원 롤백은 prj-deploy 범프 커밋을 직접 검토·revert한다.
5. 알림: 앱별 배포완료/Degraded 구독은 Application의 `notifications.argoproj.io/subscribe.*` annotation.
6. 변경 후 확인: ArgoCD 앱 Synced+Healthy + (서비스면) Buzz #cicd 알림.

## 도메인·노출 정책 (2026-10-05)

- 외부 공개는 ingress 경유 원칙. LB 직접 노출은 ingress(정문)와 plate-db LB(사무실 대역
  `192.168.0.0/24` 제한, DataGrip용)뿐.
