# Harbor + OpenBao + ESO 인증 통합

이 디렉토리는 Harbor registry에서 이미지를 안전하게 pull하기 위한 OpenBao + ESO(External Secrets Operator) 통합 설정을 포함합니다.

## 📋 아키텍처

```
Harbor Robot Accounts → OpenBao KV v2 Store → ESO → K8s Secrets → Pod ImagePullSecrets
```

## 🗂️ 파일 구조

```
helm/shared-configs/harbor-auth/
├── serviceaccount.yaml          # Harbor secret 읽기용 ServiceAccount
├── openbao-token-secret.yaml    # OpenBao 접근용 토큰 Secret  
├── secret-store.yaml            # ESO SecretStore (OpenBao 연결)
├── external-secret.yaml         # ESO ExternalSecret (Docker secret 생성)
├── kustomization.yaml           # Kustomize 설정 (ArgoCD 호환)
└── README.md                    # 이 파일

argocd/
└── harbor-auth.yaml             # ArgoCD Application 정의
```

## 🔧 사전 준비사항

### 1. Harbor Robot Account 생성
Harbor 웹 UI에서 다음 Robot Account들을 생성해야 합니다:

- **Staging**: `k8s-staging-puller` (Pull 권한)
- **Production**: `k8s-production-puller` (Pull 권한)

### 2. OpenBao에 인증정보 저장
```bash
# Staging 환경
bao write secret/data/harbor/staging \
  data.registry="harbor.cocdev.co.kr" \
  data.username="robot\$library+k8s-staging-puller" \
  data.password="Harbor에서_받은_staging_토큰"

# Production 환경  
bao write secret/data/harbor/production \
  data.registry="harbor.cocdev.co.kr" \
  data.username="robot\$library+k8s-production-puller" \
  data.password="Harbor에서_받은_production_토큰"
```

### 3. ESO 설치
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace \
  --set installCRDs=true
```

## 🚀 배포 방법 (ArgoCD GitOps)

### 1. OpenBao 토큰 설정
`openbao-token-secret.yaml` 파일에서 `REPLACE_WITH_BASE64_ENCODED_OPENBAO_TOKEN`을 실제 base64 인코딩된 토큰으로 교체:

```bash
# OpenBao 토큰 생성
bao write auth/token/create policies="default" ttl="8760h"

# base64 인코딩
echo -n "generated_token" | base64
```

### 2. Git 저장소 업데이트
변경사항을 Git 저장소에 커밋하고 푸시:

```bash
git add .
git commit -m "feat: add Harbor auth ESO configuration"
git push origin main
```

### 3. ArgoCD Application 배포
```bash
# ArgoCD Application 생성
kubectl apply -f argocd/harbor-auth.yaml

# 또는 ArgoCD CLI 사용
argocd app create harbor-auth-eso \
  --repo https://github.com/your-org/prj-devops \
  --path helm/shared-configs/harbor-auth \
  --dest-server https://kubernetes.default.svc \
  --sync-policy automated
```

### 4. 자동 배포 스크립트 사용 (ArgoCD 방식)
```bash
./scripts/deploy-harbor-auth.sh
```

### 5. ArgoCD UI에서 확인
- ArgoCD 대시보드에서 `harbor-auth-eso` 애플리케이션 상태 확인
- 자동 동기화 설정으로 Git 변경사항 자동 반영

## ✅ 검증 방법

### 1. ESO 리소스 상태 확인
```bash
# SecretStore 상태
kubectl get secretstore -A

# ExternalSecret 상태  
kubectl get externalsecret -A

# 생성된 Docker Secret 확인
kubectl get secret harbor-docker-secret -n plate-stg
kubectl get secret harbor-docker-secret -n plate-prod
```

### 2. Secret 내용 확인
```bash
kubectl get secret harbor-docker-secret -n plate-stg -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq
```

### 3. 자동 검증 스크립트 실행
```bash
./scripts/verify-harbor-auth.sh
```

## 🐳 애플리케이션 설정

### imagePullSecrets 설정
애플리케이션 Pod들이 ESO가 생성한 secret을 사용하도록 설정:

```yaml
# common-values.yaml
imagePullSecrets:
  - name: harbor-docker-secret
```

### Harbor 이미지 경로
be-server는 Harbor registry를 사용:
```yaml
# be-server values 파일
backend:
  image:
    repository: harbor.cocdev.co.kr/server-stg/server
    tag: "latest"
```

fe-web는 기존 Docker Hub 사용:
```yaml  
# fe-web values 파일
image:
  repository: nginx  # Docker Hub 그대로 사용
  tag: "latest"
```

## 🔄 자동 동기화

ESO는 1시간마다 OpenBao에서 최신 인증정보를 가져와 Kubernetes Secret을 업데이트합니다. Harbor Robot Account 토큰이 변경되면 OpenBao만 업데이트하면 자동으로 반영됩니다.

## 🚨 문제 해결

### ArgoCD 관련 문제
```bash
# ArgoCD Application 상태 확인
kubectl get application harbor-auth-eso -n argocd

# ArgoCD 동기화 상태 확인
argocd app get harbor-auth-eso

# 수동 동기화
argocd app sync harbor-auth-eso
```

### ESO 로그 확인
```bash
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets
```

### SecretStore 연결 문제
- OpenBao 토큰이 올바른지 확인
- OpenBao 서버 연결 상태 확인
- 네트워크 정책 확인
- ArgoCD Application의 동기화 상태 확인

### ExternalSecret 동기화 실패  
- Harbor Robot Account 활성화 상태 확인
- OpenBao에 저장된 인증정보 확인
- SecretStore 상태 확인
- Git 저장소의 최신 변경사항 확인

## 📚 참고 문서

- [External Secrets Operator](https://external-secrets.io/)
- [OpenBao Documentation](https://openbao.org/docs/)
- [Harbor Documentation](https://goharbor.io/docs/)
- [Kubernetes ImagePullSecrets](https://kubernetes.io/docs/concepts/containers/images/#specifying-imagepullsecrets-on-a-pod)