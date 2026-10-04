# buzz-gateway 이미지 소스

Jenkins 빌드 알림과 ArgoCD 배포 완료 알림을 Buzz(Nostr) `#cicd` 채널로 중계하는
소형 HTTP 서비스의 컨테이너 이미지 소스다. 전체 구성과 운영 절차는
`docs/buzz-ci-integration.md`를 참조한다.

## 구성

- `Dockerfile` — multi-stage. 1단계에서 [block/buzz](https://github.com/block/buzz)의
  `buzz-cli`를 musl 정적 빌드(rustls 사용, openssl 의존 없음), 2단계 `node:22-alpine`에
  buzz 바이너리와 서버를 얹는다. `BUZZ_REF` build-arg로 buzz 소스 리비전을 고정한다.
- `server/main.ts` — 의존성 없는 node:http 서버. `POST /send`을 buzz CLI 서브프로세스로
  변환한다. 인증은 `Authorization: Bearer <BUZZ_GATEWAY_TOKEN>`.

## API

```
POST /send
Authorization: Bearer <token>
{
  "content":  "메시지 본문 (마크다운/멘션 지원)",
  "channel":  "선택. 미지정 시 BUZZ_CHANNEL 환경변수 기본 채널",
  "fileB64":  "선택. base64 첨부 (최대 4MB 디코딩 기준)",
  "filename": "선택. 첨부 파일명 (기본 attachment.log)",
  "mentions": ["npub/hex 공개키", ...],
  "replyTo":  "선택. 이벤트 ID (스레드 답장)",
  "startedAt": "선택. RFC3339 — finishedAt와 함께 오면",
  "finishedAt": "선택. RFC3339 — '동기화 소요: N분 N초' 줄을 content 끝에 추가"
}
```

- `message`/`text` 필드는 `content`의 별칭이다(ArgoCD notifications 템플릿 호환).
- 본문 상한 8MB, content 16K chars. buzz CLI 30초 타임아웃 후 504.

## 빌드/푸시 (로컬 podman, 1회성 — 소스 리비전을 바꿀 때만)

클러스터 노드가 amd64다. Apple Silicon Mac에서는 `--platform linux/amd64`로 빌드한다
(qemu 에뮬레이션으로 Rust 빌드가 오래 걸릴 수 있음 — 1회성이므로 감수).

```bash
cd prj-devops
podman build --platform linux/amd64 --format=docker \
  -t harbor.onjitda.com/devops/buzz-gateway:0.1.2 \
  docker/buzz-gateway/
podman login harbor.onjitda.com        # Harbor robot 계정
podman push harbor.onjitda.com/devops/buzz-gateway:0.1.2
```

이미지 버전을 올릴 때는 `helm/development-tools/buzz-gateway/values.yaml`의
`image.tag`와 `docker/buzz-gateway/Dockerfile`의 `BUZZ_REF`를 함께 갱신한다.
