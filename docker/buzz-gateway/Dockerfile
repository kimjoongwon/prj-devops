# syntax=docker/dockerfile:1
# buzz-gateway 이미지 — Jenkins/ArgoCD 알림을 Buzz(Nostr) 채널로 중계하는 소형 서비스.
#
# 1단계에서 block/buzz(오픈소스, Rust)의 buzz-cli를 musl 정적 빌드한다.
# 공식 릴리스에는 Linux CLI 바이너리가 없어(데스크톱 앱 빌드만 제공) 소스 빌드가 유일한 경로.
# buzz-cli는 GUI 크레이트에 의존하지 않고 TLS도 rustls(openssl 아님)를 써서
# alpine + musl 환경에서 깔끔하게 빌드된다.
#
# 빌드(클러스터 노드가 amd64이므로 Apple Silicon에서는 플랫폼 지정 필수):
#   podman build --platform linux/amd64 -t harbor.onjitda.com/devops/buzz-gateway:0.1.0 \
#     --format=docker docker/buzz-gateway/
# 푸시(Harbor robot 계정):
#   podman login harbor.onjitda.com && podman push .../buzz-gateway:0.1.0

########################
# 1단계: buzz CLI 빌드 (musl 정적)
########################
FROM rust:1-alpine AS buzz-build

# BUZZ_REF는 block/buzz의 태그로 고정한다(업데이트 시 이 값만 바꾼다).
ARG BUZZ_REF=desktop-v0.5.26

# 원격 ADD는 자동 추출이 안 되므로 수동으로 tar를 푼다.
# git: cargo가 git 의존성을 해석할 수 있게. protobuf-dev: prost 계열 build.rs 대비.
RUN apk add --no-cache tar git make perl protobuf-dev
ADD https://github.com/block/buzz/archive/refs/tags/${BUZZ_REF}.tar.gz /tmp/buzz.tar.gz
RUN mkdir -p /src && tar -xzf /tmp/buzz.tar.gz -C /src --strip-components=1

WORKDIR /src
# 워크스페이스 전체가 아니라 buzz-cli 의존 그래프만 빌드
RUN cargo build --release -p buzz-cli \
    && cp target/release/buzz /buzz

########################
# 2단계: 런타임 (node + buzz)
########################
FROM node:22-alpine

# buzz CLI가 relay와 HTTPS 통신을 하므로 CA 인증서 필요
RUN apk add --no-cache ca-certificates \
    && adduser -D -u 10001 buzz

COPY --from=buzz-build /buzz /usr/local/bin/buzz
COPY server/main.ts server/package.json /app/

ENV NODE_ENV=production \
    PORT=8080 \
    HOME=/tmp

USER buzz
EXPOSE 8080

# busybox wget으로 자체 헬스체크
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1

CMD ["node", "--experimental-strip-types", "/app/main.ts"]
