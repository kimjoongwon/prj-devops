# App Builder DevOps 에이전트

새로운 애플리케이션을 Kubernetes 클러스터에 배포할 때 필요한 Helm 차트, ArgoCD 설정, 시크릿 관리 구성을 자동으로 생성하는 에이전트입니다.

## 이미지 레포지토리 명명 규칙

**Harbor 이미지 저장소 규칙:**

```
harbor.cocdev.co.kr/{환경}/{앱이름}
```

| 환경 | 경로 예시 |
|------|----------|
| Staging | `harbor.cocdev.co.kr/stg/{앱이름}` |
| Production | `harbor.cocdev.co.kr/prod/{앱이름}` |

**예시:**
- admin 앱 Staging: `harbor.cocdev.co.kr/stg/admin`
- admin 앱 Production: `harbor.cocdev.co.kr/prod/admin`
- api 앱 Staging: `harbor.cocdev.co.kr/stg/api`
- web 앱 Production: `harbor.cocdev.co.kr/prod/web`

## 애플리케이션 배포 구성 요소

새로운 앱을 배포할 때 생성해야 하는 파일 목록:

### 1. Helm 차트 (`helm/applications/{앱이름}/`)

```
helm/applications/{앱이름}/
├── Chart.yaml           # 차트 메타데이터
├── values.yaml          # 기본 설정
├── values-stg.yaml      # Staging 환경 오버라이드
├── values-prod.yaml     # Production 환경 오버라이드
└── templates/
    ├── _helpers.tpl     # 헬퍼 템플릿
    ├── deployment.yaml  # Deployment 리소스
    └── service.yaml     # Service 리소스
```

### 2. ArgoCD Application (`environments/argocd/apps/`)

```
environments/argocd/apps/
├── {앱이름}-stg.yaml    # Staging ArgoCD Application
└── {앱이름}-prod.yaml   # Production ArgoCD Application
```

### 3. OpenBao Secrets Manager (앱 전용 시크릿이 필요한 경우)

```
helm/shared-configs/openbao-{앱이름}-secrets-manager/
├── Chart.yaml
├── values.yaml
├── values-staging.yaml
├── values-production.yaml
└── templates/
    ├── _helpers.tpl
    ├── secret-store.yaml
    └── external-secret.yaml
```

ArgoCD 앱 설정:
```
environments/argocd/apps/
├── openbao-{앱이름}-secrets-manager-stg.yaml
└── openbao-{앱이름}-secrets-manager-prod.yaml
```

## 표준 values.yaml 템플릿

### Next.js 애플리케이션

```yaml
replicaCount: 1

{앱이름}:
  image:
    repository: harbor.cocdev.co.kr/stg/{앱이름}
    tag: "latest"
    pullPolicy: IfNotPresent
  port: 3000  # Next.js 기본 포트
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 256Mi

imagePullSecrets:
  - name: harbor-docker-secret

service:
  type: ClusterIP
  port: 80
  targetPort: 3000

appSecrets:
  enabled: true
  secretName: {앱이름}-env-secrets
```

### NestJS/Node.js 애플리케이션

```yaml
replicaCount: 1

{앱이름}:
  image:
    repository: harbor.cocdev.co.kr/stg/{앱이름}
    tag: "latest"
    pullPolicy: IfNotPresent
  port: 3006  # NestJS 기본 포트
  resources:
    limits:
      cpu: 500m
      memory: 1Gi
    requests:
      cpu: 250m
      memory: 512Mi

imagePullSecrets:
  - name: harbor-docker-secret

service:
  type: LoadBalancer
  port: 80
  targetPort: 3006

appSecrets:
  enabled: true
  secretName: {앱이름}-env-secrets
```

## OpenBao KV 경로 규칙

환경변수 시크릿은 OpenBao KV 저장소에서 관리합니다:

| 앱 | Staging KV 경로 | Production KV 경로 |
|----|-----------------|-------------------|
| server | `secret/server/staging` | `secret/server/production` |
| admin | `secret/admin/staging` | `secret/admin/production` |
| {앱이름} | `secret/{앱이름}/staging` | `secret/{앱이름}/production` |

## 네임스페이스 규칙

| 환경 | 네임스페이스 |
|------|-------------|
| Staging | `plate-stg` |
| Production | `plate-prod` |

## ArgoCD Sync Wave 순서

배포 순서를 보장하기 위한 Sync Wave 설정:

| Sync Wave | 리소스 유형 |
|-----------|------------|
| 0 | Cluster Secrets (openbao-cluster-secrets-manager) |
| 1 | App Secrets (openbao-{앱이름}-secrets-manager), PVC (plate-cache) |
| (default) | Applications (plate-api, plate-web, plate-admin 등) |

## 체크리스트

새 앱 배포 시 확인사항:

- [ ] Harbor 이미지 저장소 생성 (stg/{앱이름}, prod/{앱이름})
- [ ] Helm 차트 생성 및 린트 확인
- [ ] ArgoCD Application 설정 생성
- [ ] OpenBao KV 경로 생성 (필요시)
- [ ] OpenBao Secrets Manager 설정 (필요시)
- [ ] Ingress 설정 추가 (필요시)

## 검증 명령어

```bash
# Helm 차트 린트
helm lint helm/applications/{앱이름}

# 템플릿 렌더링 확인 (Staging)
helm template helm/applications/{앱이름} -f helm/applications/{앱이름}/values-stg.yaml

# 템플릿 렌더링 확인 (Production)
helm template helm/applications/{앱이름} -f helm/applications/{앱이름}/values-prod.yaml

# ArgoCD 앱 상태 확인
kubectl get applications -n argocd | grep {앱이름}
```
