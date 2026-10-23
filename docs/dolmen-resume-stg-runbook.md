# Dolmen stg 비공개 이력서 연결

Dolmen API는 Git·이미지에 포함하지 않은 PDF를 읽어 정제·색인한다. 이 문서는
`plate-stg`의 전용 Secret 연결과 기능 확인을 소유한다. 비밀값과 원본 PDF는 이 문서나
Helm values, PR, 빌드 로그에 기록하지 않는다. 시크릿 운영 원본은 OpenBao
`secret/docs/credentials-map`의 Dolmen 항목이다.
운영은 별도 KV·전용 LLM Secret을 쓰며 [Dolmen prod 런북](dolmen-prod-runbook.md)을 따른다.

## 공급 계약

| 구간 | 이름·경로 |
| --- | --- |
| OpenBao KV v2 전체 경로 | `secret/dolmen/staging` |
| 기존 SecretStore | `plate-stg/openbao-env-staging` (`secret` mount, KV v2) |
| ExternalSecret | `plate-stg/dolmen-api-stg-resume` (Dolmen API 차트 소유) |
| 생성 Secret | `plate-stg/dolmen-resume`, `creationPolicy: Owner` |
| 갱신 주기 | `30m` |
| 컨테이너 PDF 경로 | `/etc/dolmen/resume.pdf` (`DOLMEN_RESUME_PATH`) |

| OpenBao property | Secret key | 소비 방식 |
| --- | --- | --- |
| `resume_pdf` | `resume.pdf` | 원본 PDF의 base64 문자열을 ESO `decodingStrategy: Base64`로 복원하여 디렉터리 볼륨에 읽기 전용 마운트 |
| `candidate_name` | `candidate_name` | `DOLMEN_CANDIDATE_NAME`의 개별 `secretKeyRef` |
| `resume_updated_at` | `resume_updated_at` | `DOLMEN_RESUME_UPDATED_AT`의 개별 `secretKeyRef`, 원본 작성 기준일 `YYYY-MM-DD` |

ESO의 `remoteRef.key`는 `dolmen/staging`이며 SecretStore가 `secret` mount와 KV v2 경로를
적용한다. PDF만 base64 해제하고 이름·날짜는 문자열 그대로 동기화한다.
[ESO의 필드별 디코딩 계약](https://external-secrets.io/v1.1.1/guides/decoding-strategy/)을 따른다.
Secret은 PDF key만 파일로 마운트하며 `0444` 권한으로 이미지의 uid 1001 프로세스가 읽는다.
디렉터리 마운트라 PDF 갱신이 반영되며, 메타데이터 환경변수 변경은 파드 재시작 후 반영된다.
PDF와 메타데이터를 함께 교체할 때는 KV 세 property를 같은 버전으로 갱신한 후 ESO 동기화와
파드 재시작을 수행한다. PDF와 메타데이터 합계는 Kubernetes Secret 크기 제한(1 MiB) 이내여야 한다.
[Kubernetes Secret 볼륨·크기 계약](https://kubernetes.io/docs/concepts/configuration/secret/)을 따른다.

LLM 접속 설정은 기존 `secret/core-api/staging` → `app-env-secrets` → `envFrom`을 유지한다.
별도 `.env`를 이미지에 복사하지 않는다. 비운영 stg는 `DOLMEN_DEBUG_ENABLED=true`로 정제 근거,
GSSC 입력 구성과 평가 개발 관측을 검증한다. 기본 차트와 앱 기본값은 `false`이며 일반 운영에서는
활성화하지 않는다. 개발 응답도 허용된 정제 자료·해당 요청 계측만 제공하며 원본 PDF·접속 키·
프롬프트·다른 세션 대화를 제공하지 않는다.
컨텍스트 입력 예산 `32768`과 출력 예약 `2048`은 앱 기본값을 사용한다.
이 수치는 공급자 모델의 실제 한도를 확인한 값이 아니며 변경이 필요하면 차트 `extraEnv`로
`DOLMEN_CONTEXT_INPUT_TOKEN_LIMIT`, `DOLMEN_CONTEXT_OUTPUT_TOKEN_RESERVE`를 주입한다.

## 적용과 검증

1. 운영 담당자가 원본 PDF와 이름·작성 기준일을 확인하고 OpenBao 전용 KV에 공급한다.
   기존 ESO 토큰의 해당 KV 읽기 권한과 `credentials-map`의 소비처 짝도 확인한다.
2. 차트의 `resume.enabled` 기본값은 `false`이며, stg는 `values-stg.yaml`에서 활성화한다.
   검토한 `prj-devops/main` 변경이 ArgoCD에 반영되면 ExternalSecret이 생성된다.
3. ExternalSecret `Ready=True`와 생성 Secret의 세 key 존재를 값 출력 없이 확인한다.
   필요하면 아래 명령으로 동기화를 요청한다. 새 Secret이 준비되기 전 파드는 Ready가 되지 않는다.

   ```bash
   kubectl -n plate-stg annotate externalsecret dolmen-api-stg-resume \
     force-sync="$(date +%s)" --overwrite
   kubectl -n plate-stg get externalsecret dolmen-api-stg-resume
   ```

4. 이미지 빌드는 `dolmen-api-build`, `dolmen-web-build` 각각 `BRANCH_NAME=stg`로 실행한다.
   빌드 성공 후 비동기 `gitops-prod-image-bump`가 두 `prj-deploy/stg/dolmen-*.yaml`을 실제
   빌드 SHA 앞 12자로 범프했는지도 확인한다.
5. ArgoCD 두 앱 `Synced + Healthy`, 파드의 해당 이미지, Buzz `#cicd` 배포 알림을 확인한다.
   `https://stg.onjitda.com/dolmen/api/health`의 `llm_configured=true`,
   `/dolmen/api/documents`의 `resume_configured=true`, `resume_ready=true`와 작성 기준일을 확인한다.
   stg에서는 documents의 정제 데이터 `debug`와 채팅의 GSSC·평가 이벤트를 확인한다.
   실제 질문의 SSE가 답변 후 `done`으로 끝나는지 확인하며 원본 PDF·키·전체 프롬프트나
   다른 세션의 대화가 개발 관측에 포함되면 배포 완료로 판단하지 않는다.

이력서 연결이 활성화되면 readiness는 `/api/documents` HTTP 성공으로 PDF 추출·색인까지
판정한다. 최초 모델 로딩을 위해 20초 지연, 요청당 30초 제한, 실패 6회를 허용한다.
startup/liveness는 TCP를 유지하여 등록 실패 때문에 파드가 재시작을 반복하지 않게 한다.
연결이 비활성화되면 기존 TCP readiness와 볼륨 없는 배포를 유지한다.

Dolmen API Application은 무시한 `restartedAt` 제거 뒤 남는 빈 pod annotation 객체도
정규화한다. 실제 ArgoCD 정규화 diff에서 빈 객체와 필드 부재만 달랐던 반복 동기화를
해소하며, 값이 있는 다른 annotation은 계속 비교한다.

stg Ingress Controller는 `nginx/nginx-ingress`(NGINX Inc)다. `helm/ingress/values-stg.yaml`의
`nginx.org/proxy-read-timeout`·`nginx.org/proxy-send-timeout`을 `120s`로 지정한다.
기존 community 형식 `nginx.ingress.kubernetes.io/*`만으로는 이 컨트롤러의 기본 `60s`를
바꾸지 못해 모델 대기 중 SSE 연결이 끊겼다. 적용 후 생성된 `/dolmen` location의 실제
`proxy_read_timeout`·`proxy_send_timeout`과 브라우저의 최종 `done` 수신을 확인한다.
이 제한은 전체 답변 시간 대신 연속 무수신 간격에 적용된다. API는 긴 모델 처리 중에도
주기적인 SSE comment를 전송하며, `X-Accel-Buffering: no`로 응답 버퍼링을 해제한다.
[NGINX Controller annotation 계약](https://docs.nginx.com/nginx-ingress-controller/configuration/ingress-resources/advanced-configuration-with-annotations/)을 따른다.

원본·작성 기준일·추출·색인에 문제가 있으면 documents가 503을 반환하여 트래픽에서 제외한다.
`/api/health`의 LLM 설정 존재 여부와 readiness는 제공자 접속·실제 답변 성공까지 증명하지 않는다.
롤백은 해당 `prj-deploy` 범프 커밋을 확인하여 revert한다. Dolmen은 `scripts/rollback.sh`
지원 대상이 아니다.
