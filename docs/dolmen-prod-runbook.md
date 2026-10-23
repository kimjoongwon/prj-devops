# Dolmen prod 최초 배포·운영

운영 진입점은 `https://onjitda.com/dolmen`, namespace는 `plate-prod`다.
이 문서는 Git에 선언한 배선과 적용 순서를 설명한다. 배포 완료 여부는 아래 런타임
검증으로 별도 판단한다. stg는 [기존 이력서 런북](dolmen-resume-stg-runbook.md)을 유지한다.

## 공급·라우팅 계약

| 대상 | 운영 설정 |
| --- | --- |
| API Application / Service | `dolmen-api-prod` / `plate-prod/dolmen-api-prod:3012` |
| Web Application / Service | `dolmen-web-prod` / `plate-prod/dolmen-web-prod:80` |
| 차트·환경 값 | `prj-devops/main`, 각 차트의 `values-prod.yaml` |
| 이미지 태그 | `prj-deploy/main`의 `prod/dolmen-api.yaml`, `prod/dolmen-web.yaml` |
| 이미지 저장소 | `harbor.onjitda.com/prod/dolmen-api`, `harbor.onjitda.com/prod/dolmen-web` |
| 외부 경로 | 기존 TLS Ingress의 `onjitda.com /dolmen` Prefix → Web |
| API 프록시 | Web의 `DOLMEN_API_URL=http://dolmen-api-prod.plate-prod.svc.cluster.local:3012` |
| OpenBao 원본 | KV v2 `secret/dolmen/production` (`remoteRef.key=dolmen/production`) |
| 기존 SecretStore | `plate-prod/openbao-env-production` (`secret` mount) |

운영은 공유 `app-env-secrets`를 사용하지 않는다(`appSecrets.enabled=false`). 전용 KV의
여섯 property를 다음 두 ExternalSecret이 분리하여 소비한다. PDF·키·개인정보는 Git,
Helm values, 이미지, PR, 터미널 출력과 빌드 로그에 기록하지 않는다. 비밀값의 원본 및
권한·소비처 짝은 OpenBao `secret/docs/credentials-map`의 Dolmen 항목이 소유한다.

| ExternalSecret → 생성 Secret | OpenBao property → Secret key | 소비 방식 |
| --- | --- | --- |
| `dolmen-api-prod-resume` → `dolmen-resume` | `resume_pdf` → `resume.pdf` | ESO `Base64` 해제, `/etc/dolmen/resume.pdf` 파일만 `0444`, 읽기 전용 디렉터리 마운트 |
| 동일 | `candidate_name` → `candidate_name` | `DOLMEN_CANDIDATE_NAME` 개별 `secretKeyRef` |
| 동일 | `resume_updated_at` → `resume_updated_at` | `DOLMEN_RESUME_UPDATED_AT` 개별 `secretKeyRef`, 원본 작성 기준일 `YYYY-MM-DD` |
| `dolmen-api-prod-llm` → `dolmen-llm` | `LLM_API_KEY` → 동일 이름 | `LLM_API_KEY` 개별 `secretKeyRef` |
| 동일 | `LLM_BASE_URL` → 동일 이름 | `LLM_BASE_URL` 개별 `secretKeyRef` |
| 동일 | `LLM_MODEL_ID` → 동일 이름 | `LLM_MODEL_ID` 개별 `secretKeyRef` |

두 Secret은 `creationPolicy: Owner`, 갱신 주기는 `30m`다. LLM 세 값과 이력서 메타데이터는
문자열 그대로 동기화한다. PDF가 포함된 `dolmen-resume`의 전체 데이터는 Kubernetes Secret
제한인 1 MiB 이내여야 한다. 운영자는 승인한 PDF와 이름·작성 기준일을 확인하여 한 KV 버전으로
공급한다. 데모·합성 PDF를 운영 Secret의 대체값으로 넣지 않는다. stg 원본의 운영 사용이
승인된 경우에도 운영 KV를 별도로 소유하며 stg SecretStore나 공유 Secret을 참조하지 않는다.

`llm.enabled`와 `resume.enabled`의 차트 기본값은 `false`이며 운영 값에서 활성화한다.
`DOLMEN_DEBUG_ENABLED=false`를 유지하므로 정제 근거·GSSC·평가용 개발 관측은 운영 응답에
노출하지 않는다. 입력 예산 `32768`과 출력 예약 `2048`은 앱 기본값이며 공급자 모델의 실제
한도를 증명하는 값은 아니다. Web의 기존 Node OTel `0.78.0`은 유지한다. Python API에 Node
자동계측을 활성화하지 않는다.

## 최초 등록과 적용 순서

1. OpenBao 운영 문서(`overview`, `endpoints`, `credentials-map`, 관련 runbook)를 읽고,
   기존 운영 SecretStore의 `Ready=True`, ESO 토큰의 `dolmen/production` 읽기 권한과
   여섯 property 존재를 값 출력 없이 확인한다. 공유 앱 시크릿을 변경하지 않는다.
2. 처음에는 `prj-deploy/prod/dolmen-*.yaml`이 없으므로 최신 소스 승격 전에 태그 파일을
   최초 등록하는 PR을 먼저 병합한다. Harbor `prod`에 이미 존재하는 이미지가 있으면 각 앱의
   SHA-12 태그·digest·빌드 커밋을 검증하여 초기값으로 사용할 수 있다. stg에만 있는 태그를
   prod에 존재한다고 추정하지 않는다. 이 단계에서는 prod Application을 활성화하지 않는다.
   prod 이미지가 전혀 없으면 먼저 main 이미지 빌드를 성공시키고 검증한 SHA-12로 최초 등록한다.
3. 사용자 승인한 `prj-core stg → main` PR을 병합하고 `dolmen-api-build`, `dolmen-web-build`를
   `BRANCH_NAME=main`으로 빌드한다. 자동 라우터가 실행했으면 중복 빌드하지 않는다.
   Harbor `prod`에 생성된 최신 두 이미지와 빌드 커밋을 대조하고, 비동기
   `gitops-prod-image-bump`가 초기 태그 파일을 최신 SHA-12로 갱신했는지 확인한다.
   이후 범프는 이 잡이 소유한다. 이 저장소에 태그를 넣지 않는다.
4. 최신 운영 태그 두 개가 `prj-deploy/main`에 반영된 다음 이 저장소의 prod 차트·Application·Ingress
   PR을 병합한다. 부모 `frontend-web-apps`가 두 Application을 생성하고 자동 동기화한다.
   앱 리소스를 `kubectl apply`로 별도 적용하지 않는다.
5. ExternalSecret 두 개가 `Ready=True / SecretSynced`이고 생성 Secret의 key 집합이 위 계약과
   같은지 값 출력 없이 확인한다. 두 Secret이 준비되기 전 API는 시작 또는 Ready 전환을 기다린다.
6. 아래 런타임 검증을 모두 통과하고 Buzz `#cicd`의 두 앱 배포 완료 알림을 확인한다.

PDF는 디렉터리 마운트이므로 ESO가 갱신한 파일이 파드에 반영된다. 메타데이터와 LLM 환경변수는
파드 시작 시 주입되므로 함께 교체할 때는 KV 갱신 → ESO 동기화 완료 → API rollout restart
순서로 적용한다. Secret 데이터·환경변수 전체를 출력하는 명령은 사용하지 않는다.

## 런타임 검증과 복구

- ArgoCD `dolmen-api-prod`, `dolmen-web-prod`, `plate-ingress-prod`가 `Synced + Healthy`인지,
  두 파드의 실제 이미지가 태그 저장소와 같은지 확인한다. 재시작 흔적과 빈 annotation 객체만
  정규화하며 값이 있는 다른 annotation은 계속 비교한다.
- `/dolmen`의 화면 렌더링과 `/dolmen/api/health`의 `llm_configured=true`를 확인한다.
  `/dolmen/api/documents`는 `resume_configured=true`, `resume_ready=true`, 승인한 작성 기준일을
  확인하되 이름·문서 내용은 로그에 복사하지 않는다. `debug` 개발 관측이 노출되지 않아야 한다.
  앱 내부 데모·합성 문서의 목록 공개 범위도 운영 정책과 대조한다. 이 차트는 앱의 시드 문서를
  제거하지 않으므로 PDF Secret 연결만으로 해당 정책의 검증을 대신하지 않는다.
- API readiness는 `/api/documents` HTTP 성공으로 PDF 추출·색인까지 판정한다(20초 지연,
  요청당 30초 제한, 실패 6회). startup/liveness는 TCP를 유지한다. health와 readiness만으로
  LLM 제공자 접속 성공을 판단하지 않고 실제 질문의 SSE 답변과 마지막 `done`을 확인한다.
- 실제 컨트롤러 `nginx/nginx-ingress`(NGINX Inc)는 `nginx.org/proxy-read-timeout`과
  `nginx.org/proxy-send-timeout`의 `120s`를 사용한다. community 형식 annotation만으로는
  기본 `60s`가 바뀌지 않는다. 생성된 `/dolmen` location의 두 timeout, SSE heartbeat 수신과
  최종 `done`을 함께 확인한다. 제한은 전체 응답 길이가 아닌 연속 무수신 간격에 적용된다.
- 기존 onjitda.com의 `/`, `/admin`, `/api`, `/proposal`, `/design`, `/live`, `/story`와
  idp.onjitda.com 라우팅 및 기존 TLS Secret이 유지되는지 확인한다.

PDF·메타데이터·색인 문제가 있으면 documents가 503을 반환하여 트래픽에서 제외한다.
일반 이미지 롤백은 해당 `prj-deploy` 범프 커밋을 확인해 revert하는 PR로 수행한다.
Dolmen은 `scripts/rollback.sh` 지원 대상이 아니다. 최초 배포에는 이전 prod 이미지 태그가
없으므로 최초 태그 파일을 삭제하는 revert만 수행하면 Application 렌더가 실패한다.
최초 배포 자체를 철회할 때는 두 prod Application과 `/dolmen` Ingress 경로를 추가한 IaC
변경을 함께 되돌리는 PR을 준비한다. OpenBao 원본은 보존하며, Application finalizer와
ExternalSecret Owner 정책에 따라 삭제되는 런타임 사본 범위를 먼저 확인한다.
