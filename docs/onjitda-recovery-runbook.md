# onjitda.com 클러스터 복구 런북

작성일: 2026-09-18 (cocdev.co.kr → onjitda.com 전환 작업 기준)

이 문서는 두 가지를 다룬다.

1. **클러스터(VM) 재시작 후 복구 절차** — 서버/VM 재부팅 시 반드시 필요한 순서
2. **2026-09-18 도메인 전환 기록** — 무엇이 바뀌었는지, 겪은 문제와 해결

---

## 1. 클러스터 재시작 후 복구 절차

클러스터는 서버(192.168.0.97) 위 VirtualBox VM 3대로 구성된다.
VM을 내려도 클러스터 상태(etcd, 인증서, 배포 리소스)는 디스크에 보존되므로 재초기화가 아니라 **기동 + 봉인 해제**만 하면 된다.

### 1-1. VM 기동

```bash
# 서버(192.168.0.97)에서
ssh wally-server
cd ~/prj-vagrant-k8s && vagrant up
```

- VM: control-plane=192.168.0.10, node-01=.11, node-02=.12
- 부팅 후 노드 확인(kubectl은 관리 PC의 `~/.kube/config` 사용):

```bash
kubectl get nodes   # 3대 모두 Ready 여부 (2~3분 소요)
```

### 1-2. OpenBao 봉인 해제 (핵심)

OpenBao 파드가 재시작되면 **봉인(sealed) 상태**로 기동한다. 이 상태에서는 모든
ExternalSecret이 `SecretSyncedError`로 실패하고, 의존 앱 파드가 줄줄이 이상해진다.

```bash
# 봉인 상태 확인 (Sealed: true 가 나오면 해제 필요)
kubectl exec -n openbao openbao-0 -- bao status | head -6

# 봉인 해제 (Unseal Key는 안전한 보관소에서)
kubectl exec -n openbao openbao-0 -- bao operator unseal <UNSEAL_KEY>

# 파드 Ready 확인
kubectl get pod -n openbao openbao-0
```

주의: `bao operator unseal`은 stdin 파이프를 거부한다. 키를 **인자**로 넘긴다.

### 1-3. SecretStore / ExternalSecret 재동기화

봉인 중 실패했던 스토어 검증/동기화는 자동으로 즉시 재시도되지 않는다(최대 1시간 주기).
아래처럼 강제 트리거한다.

```bash
# 스토어 재검증
kubectl annotate -n plate-prod secretstore openbao-env-production force-sync="$(date +%s)" --overwrite
kubectl annotate -n plate-stg   secretstore openbao-env-staging     force-sync="$(date +%s)" --overwrite
kubectl annotate clustersecretstore openbao-cluster-store           force-sync="$(date +%s)" --overwrite

# ExternalSecret 재동기화
for ns in plate-prod plate-stg; do
  kubectl get externalsecrets -n "$ns" --no-headers | awk '{print $1}' |
  while read es; do
    kubectl annotate -n "$ns" externalsecret "$es" force-sync="$(date +%s)" --overwrite
  done
done

# 확인: 전부 SecretSynced / Ready=True 여야 함
kubectl get secretstore -A
kubectl get clustersecretstore
kubectl get externalsecrets -A
```

### 1-4. 터널 연결 및 서비스 확인

```bash
# cloudflared 파드 Running + 로그에 "Registered tunnel connection" 확인
kubectl get pods -n cloudflared
kubectl logs -n cloudflared deploy/cloudflared | grep Registered | tail -4

# 외부 응답 확인 (관리 PC에서)
for h in onjitda.com idp.onjitda.com argocd.onjitda.com harbor.onjitda.com; do
  curl -s -o /dev/null -w "$h %{http_code}\n" -m 15 "https://$h/"
done
```

### 1-5. 문제가 있을 때 첫 확인 포인트

| 증상 | 확인 |
|---|---|
| ExternalSecret 전체 실패 | OpenBao 봉인 여부 (1-2) |
| 이미지 풀 실패 (502/redirect) | 터널 라우팅 설정 (아래 2-2), `curl https://harbor.onjitda.com/v2/` → 401이어야 정상 |
| harbor-core `CreateContainerConfigError` | `harbor-admin` 시크릿 존재 여부 (아래 트러블슈팅 4) |
| 인증서 발급 실패 | `cloudflare-dns01-api-token` 시크릿(cert-manager ns)과 ClusterIssuer DNS-01 설정 |

---

## 2. 2026-09-18 도메인 전환 기록

### 2-1. 전환 개요

| 항목 | 이전 | 이후 |
|---|---|---|
| 도메인 | cocdev.co.kr (미해석 상태) | onjitda.com (Cloudflare Registrar) |
| 외부 노출 | MetalLB IP + 서버 DNAT 규칙 | Cloudflare Tunnel (remotely-managed) |
| 인증서 발급 | cert-manager HTTP-01 | cert-manager **DNS-01 (Cloudflare)** |
| 터널 커넥터 | 없음 | `helm/development-tools/cloudflared` + ArgoCD 앱 `cloudflared-prod` |

### 2-2. Cloudflare 쪽 최종 구성

- Tunnel: `homelab` (ID `5dcf2842-f2bf-4487-8048-64c00027c06a`)
- DNS: 서비스 12호스트 CNAME → `<tunnel-id>.cfargotunnel.com`, 프록시 ON
- 터널 라우팅(전 호스트 공통):

```json
{
  "service": "https://192.168.0.20:443",
  "originRequest": { "noTLSVerify": true, "originServerName": "onjitda.com" }
}
```

이 조합이 아니면 동작하지 않는다(트러블슈팅 1, 2 참조).

### 2-3. 클러스터 쪽 변경 요약

- helm 릴리스 5종(argocd, harbor, jenkins, openbao, prometheus)을 신규 values로 재적용
  (동일 차트 버전, 도메인 값만 교체)
- cert-manager ClusterIssuer 2종(prod/stg) → Cloudflare DNS-01
- OpenBao KV: `secret/harbor/{production,staging}`의 dockerconfig 레지스트리 주소 교체,
  `patch-idp-endpoints.sh production apply` 실행
- 클러스터 잔여 정리: 고아 ACME order/certificaterequest, 미사용 TLS 시크릿(default ns 3종,
  plate-stg 1종), 미사용 configmap(fe-web-prod-config) 삭제
- `spring-api-prod`는 2026-09-23 폐기 결정으로 GitOps에서 완전 제거됨
  (기존 미해결 과제였던 Harbor 이미지 누락 문제도 함께 해소)

### 2-4. 트러블슈팅 기록 (재발 방지용)

1. **터널 → ingress 리다이렉트 루프** (`stopped after 10 redirects`)
   - 원인: 터널 origin을 `http://192.168.0.20:80`로 두자 ingress의 ssl-redirect가
     https로 되돌려 무한 리다이렉트
   - 해결: origin을 `https://192.168.0.20:443`로 변경
2. **`tls: unrecognized name`** (cloudflared 로그)
   - 원인: origin이 IP면 cloudflared가 SNI를 보내지 않고, ingress-nginx가 미등록 SNI는
     핸드셰이크 거부
   - 해결: `originRequest.originServerName: "onjitda.com"` 지정
3. **Harbor 토큰 발급처가 구 도메인** (`https://harbor.cocdev.co.kr/service/token`)
   - 원인: helm values의 `externalURL` 교체 후에도 새 harbor-core 파드가 기동하지 못해
     구 core가 응답 중
   - 해결: 아래 4 해결 후 새 core 기동으로 해소
4. **harbor-core `CreateContainerConfigError`**
   - 원인: values의 `existingSecretAdminPassword: harbor-admin`이 참조하는
     `harbor-admin` 시크릿이 클러스터에 없었음(최초 설치 후 유실 추정)
   - 해결: `kubectl -n harbor create secret generic harbor-admin --from-literal=HARBOR_ADMIN_PASSWORD=...`
   - 교훈: helm 릴리스 재적용 전 values의 existingSecret 계열 참조 시크릿 존재 여부 확인
5. **OpenBao 재봉인으로 ExternalSecret 13종 전체 실패**
   - 해결: 봉인 해제 후 스토어/ES force-sync 재트리거 (위 1-2, 1-3)

### 2-5. 관리 시크릿 위치 (값은 이 문서에 기록하지 않음)

| 시크릿 | 위치 |
|---|---|
| Cloudflare API 토큰 / 터널 시크릿 / TUNNEL_TOKEN | 관리 PC `~/.cloudflare/` (600) |
| cert-manager DNS-01 토큰 | 클러스터 `cert-manager/cloudflare-dns01-api-token` |
| 터널 토큰 | 클러스터 `cloudflared/cloudflared-tunnel-token` |
| Harbor 어드민 | 클러스터 `harbor/harbor-admin` |
| OpenBao Unseal Key / Root Token | 서버 `~/openbao-init-20260318.json` (안전한 곳으로 이관 권장) |

---

## 3. 후속 조치 (2026-09-18 기준)

1. **Cloudflare Access 적용 완료 (2026-09-18)** — 관리 도구 7호스트(argocd/harbor/jenkins/grafana/prometheus/openbao/db.onjitda.com)가 이메일 OTP로 보호됨. 팀 도메인: `onjitda.cloudflareaccess.com`, 허용 이메일 정책. 도구 접속 시 이메일 인증(24시간 세션) 후 서비스 로그인 화면에 도달한다.
2. **Harbor 어드민 비밀번호 교체** — 현재 차트 기본값 사용 중
3. **유출 이력 있는 비밀번호 교체** — Jenkins/ArgoCD/pgAdmin 비밀번호가 GitHub 프로필 README에 공개된 적 있음(이력에서는 삭제 완료). Access 경비실이 있어도 교체 권장
4. OpenBao Unseal Key / Root Token을 비밀번호 관리자로 이관
5. (선택) `www.onjitda.com` → 루트 리다이렉트 ingress 규칙 추가 (현재 404)

## 4. Cloudflare Access 운영 시 주의 (2026-09-18 추가)

- 관리 도구 7호스트(argocd/harbor/jenkins/grafana/prometheus/openbao/db.onjitda.com)는
  Access 이메일 OTP 뒤에 있다. 허용 이메일: `Wallydevplan@gmail.com`, 세션 24시간.
- **ExternalSecret 스토어는 클러스터 내부 주소를 사용해야 한다**
  (`http://openbao.openbao.svc.cluster.local:8200`). 공개 주소
  `https://openbao.onjitda.com`를 스토어에 쓰면 Access 로그인 벽에 막혀
  스토어 검증이 실패한다(2026-09-18 발생 → `02f942e`로 해결).
- OpenBao 관리 스크립트(`scripts/openbao/*`) 실행 시 공개 주소 기본값이
  Access에 막히므로 `OPENBAO_ADDR=http://openbao.openbao.svc.cluster.local:8200`로
  오버라이드하거나 클러스터 내부에서 실행한다.
- 관리도구 5종(Jenkins/ArgoCD/Grafana/Harbor/pgAdmin) 비밀번호는 2026-09-18 통일 완료.

## 5. 노드의 Harbor 이미지 풀은 LAN 직결로 (2026-09-19 추가)

Cloudflare Tunnel 경유 레지스트리 풀은 레이어가 재압축되며
`failed size validation` 오류로 실패할 수 있다(실제 발생). 따라서
**전 노드의 /etc/hosts에 아래 항목이 반드시 있어야 한다** (VM 재생성 시 소실 주의):

```
192.168.0.20 harbor.onjitda.com
```

전 노드 적용 (서버 192.168.0.97에서):

```bash
cd ~/prj-vagrant-k8s
for m in control-plane node-01 node-02; do
  vagrant ssh "$m" -c 'grep -q harbor.onjitda.com /etc/hosts || \
    echo "192.168.0.20 harbor.onjitda.com" | sudo tee -a /etc/hosts'
done
```

ingress의 habor-tls 인증서(cert-manager DNS-01 발급, SAN harbor.onjitda.com)가
유효하므로 https 직결 풀이 정상 동작한다. LAN 직결 시 풀 속도도 수 배 빠르다
(실측 280MB 이미지 1.6초).

## 6. k9s/kubectl 접속 — 상시 터널 (2026-09-23 자동화)

관리 PC가 집 LAN(192.168.0.x) 밖에 있을 때는 API 서버(192.168.0.10:6443)로 직접
닿지 않는다. 기존 Cloudflare Tunnel SSH(`ssh.onjitda.com`) 위에 로컬 포워드를 얹어
우회한다. 클러스터가 살아 있는 한(= onjitda.com 응답) 이 경로로 항상 접속 가능.

처음엔 수동 기동(`ssh -f -N` + 컨텍스트 전환)이었으나, 집/밖에 따라 절차가 갈리고
컨텍스트가 어느 쪽인지 기억해야 해서 놓치면 `pnpm start`의 OpenBao port-forward까지
함께 실패했다. 2026-09-23 말기에 터널을 LaunchAgent로 상시화하고 컨텍스트를
`kubernetes-tunnel` 하나로 고정해 위치 구분을 제거했다.

- 상시 터널: `~/Library/LaunchAgents/com.onjitda.k8s-api-tunnel.plist` — 로그인 시
  `/usr/bin/ssh -N k8s-api-tunnel` 기동(RunAtLoad), 프로세스가 죽으면 launchd가
  재시작(KeepAlive). ~/.ssh/config 엔트리의 `ExitOnForwardFailure`·`ServerAliveInterval
  30 × 3`이 끊김을 감지해 exit하면 재시작으로 이어진다. 로그:
  `~/Library/Logs/k8s-api-tunnel.log`.
- 컨텍스트 `kubernetes-tunnel`(고정): `https://127.0.0.1:16443`, 인증은 기존
  `kubernetes-admin` 클라이언트 인증서 그대로 사용. API 인증서 SAN에 127.0.0.1이
  없어 이 컨텍스트만 `insecure-skip-tls-verify` — 전송 암호화는 SSH 터널이 담당.
- 절전 후 끊김은 최대 ~90초 내 자동 복구(ServerAlive 감지 + KeepAlive 재시작).
- 직결 컨텍스트 `kubernetes-admin@kubernetes`(192.168.0.10:6443)은 Cloudflare
  장애 시 집 LAN 전용 비상 fallback으로 kubeconfig에 남겨둔다.

재설치(다른 Mac) 시:

```bash
cat > ~/Library/LaunchAgents/com.onjitda.k8s-api-tunnel.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0.dtd" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.onjitda.k8s-api-tunnel</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/ssh</string>
		<string>-N</string>
		<string>k8s-api-tunnel</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>StandardOutPath</key>
	<string>/Users/wallykim/Library/Logs/k8s-api-tunnel.log</string>
	<key>StandardErrorPath</key>
	<string>/Users/wallykim/Library/Logs/k8s-api-tunnel.log</string>
</dict>
</plist>
EOF
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.onjitda.k8s-api-tunnel.plist
```

해제 시:

```bash
launchctl bootout gui/$(id -u)/com.onjitda.k8s-api-tunnel
rm ~/Library/LaunchAgents/com.onjitda.k8s-api-tunnel.plist
```

## 7. IDP 재건 및 identity DB v2 재구축 (2026-09-19)

- apps/idp 재건(prj-core): 얇은 발급자(idp-api) + 로그인 UI(idp-web).
  이미지 idp-api:23, idp-web:27 (Jenkins 잡 idp-api-build / idp-web-build).
- identity prisma v2 baseline은 "빈 DB용 전체 스키마"다. 기존 DB 위에 얹지 못하므로
  prod DB는 백업 후 스키라 초기화 -> migrate deploy(3건) -> data-migrate.ts 시드로 재구축했다.
  백업: 관리 PC ~/plate_prod_backup_20260919.sql
- 시드 부트스트랩 환경변수(LOCAL_BOOTSTRAP_ADMIN_*)는 OpenBao
  secret/idp-api/production 에 등록되어 있어 재구축 시 자동 시드된다.
- GitOps 태그 bump는 Jenkins bump 잡 대신 스크립트 직접 실행으로 대체 가능:
  bash scripts/jenkins/update-gitops-image-tag.sh --app <앱> --tag <번호> \
    --git-user-name jenkins-bot --git-user-email jenkins-bot@onjitda.com
