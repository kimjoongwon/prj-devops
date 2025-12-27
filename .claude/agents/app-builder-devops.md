# App Builder DevOps 에이전트

새로운 애플리케이션을 Kubernetes 클러스터에 배포할 때 필요한 Helm 차트, ArgoCD 설정, 시크릿 관리 구성을 자동으로 생성하는 에이전트입니다.

## 앱 이름 결정 규칙

**앱 이름 구조:**

```
{프로젝트명}-{하위분류} = 앱이름
```

| 프로젝트명 | 하위분류 | 앱이름 |
|-----------|---------|--------|
| plate | admin | `plate-admin` |
| plate | server | `plate-server` |
| plate | web | `plate-web` |
| plate | llm | `plate-llm` |

**핵심 원칙: 앱이름이 모든 리소스 명명의 기준**

`plate-admin`을 예시로 한 전체 명명 규칙:

| 구성 요소 | 명명 규칙 | plate-admin 예시 |
|----------|----------|-----------------|
| Helm 차트 폴더 | `helm/applications/{앱이름}/` | `helm/applications/plate-admin/` |
| Chart.yaml name | `{앱이름}` | `plate-admin` |
| ArgoCD Application 파일 | `{앱이름}-{환경}.yaml` | `plate-admin-stg.yaml` |
| ArgoCD Application name | `{앱이름}-{환경}` | `plate-admin-stg` |
| 이미지 레포지토리 | `harbor.cocdev.co.kr/{환경}/{앱이름}` | `harbor.cocdev.co.kr/stg/plate-admin` |
| K8s Secret 이름 | `app-env-secrets-{환경}` | `app-env-secrets-staging` |
| OpenBao KV 경로 | `server/{환경}` | `server/staging` |

## 이미지 레포지토리 규칙

**Harbor 이미지 저장소:**

```
harbor.cocdev.co.kr/{환경}/{앱이름}
```

| 환경 | 앱이름 | 전체 경로 |
|------|--------|----------|
| Staging | plate-admin | `harbor.cocdev.co.kr/stg/plate-admin` |
| Production | plate-admin | `harbor.cocdev.co.kr/prod/plate-admin` |
| Staging | plate-server | `harbor.cocdev.co.kr/stg/plate-server` |
| Production | plate-web | `harbor.cocdev.co.kr/prod/plate-web` |

## OpenBao KV 경로 규칙

**KV 경로 구조 (환경별 공유):**

```
secret/server/{환경}
```

| 환경 | KV 경로 | Secret 이름 |
|------|---------|-------------|
| Staging | `secret/server/staging` | `app-env-secrets-staging` |
| Production | `secret/server/production` | `app-env-secrets-production` |

**참고:** 모든 앱이 환경별로 동일한 시크릿을 공유합니다. 앱별 시크릿이 아닌 환경별 시크릿 구조입니다.

## 애플리케이션 배포 구성 요소

새로운 앱 `{앱이름}`을 배포할 때 생성해야 하는 파일:

### 1. Helm 차트

```
helm/applications/{앱이름}/
├── Chart.yaml              # name: {앱이름}
├── values.yaml             # 기본 설정
├── values-stg.yaml         # Staging (이미지: harbor.cocdev.co.kr/stg/{앱이름})
├── values-prod.yaml        # Production (이미지: harbor.cocdev.co.kr/prod/{앱이름})
└── templates/
    ├── _helpers.tpl        # define "{앱이름}.name" 등
    ├── deployment.yaml
    └── service.yaml
```

### 2. ArgoCD Application

```
environments/argocd/apps/
├── {앱이름}-stg.yaml       # name: {앱이름}-stg
└── {앱이름}-prod.yaml      # name: {앱이름}-prod
```

### 3. OpenBao Secrets Manager (앱 전용 시크릿 필요시)

```
helm/shared-configs/openbao-{앱이름}-secrets-manager/
├── Chart.yaml              # name: openbao-{앱이름}-secrets-manager
├── values.yaml
├── values-staging.yaml     # KV: {앱이름}/staging
├── values-production.yaml  # KV: {앱이름}/production
└── templates/
    ├── _helpers.tpl
    ├── secret-store.yaml
    └── external-secret.yaml   # target: app-env-secrets-{환경}
```

ArgoCD 앱:
```
environments/argocd/apps/
├── openbao-{앱이름}-secrets-manager-stg.yaml
└── openbao-{앱이름}-secrets-manager-prod.yaml
```

## 표준 values.yaml 템플릿

### Next.js 애플리케이션 (plate-admin 예시)

```yaml
replicaCount: 1

plate-admin:  # 앱이름을 키로 사용
  image:
    repository: harbor.cocdev.co.kr/stg/plate-admin
    tag: "latest"
    pullPolicy: IfNotPresent
  port: 3000
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
  secretName: app-env-secrets-staging  # app-env-secrets-{환경}
```

### NestJS 애플리케이션 (plate-server 예시)

```yaml
replicaCount: 1

plate-server:  # 앱이름을 키로 사용
  image:
    repository: harbor.cocdev.co.kr/stg/plate-server
    tag: "latest"
    pullPolicy: IfNotPresent
  port: 3006
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
  secretName: app-env-secrets-staging  # app-env-secrets-{환경}
```

## 네임스페이스 규칙

| 환경 | 네임스페이스 |
|------|-------------|
| Staging | `plate-stg` |
| Production | `plate-prod` |

## ArgoCD Sync Wave 순서

| Sync Wave | 리소스 유형 |
|-----------|------------|
| 0 | Cluster Secrets (openbao-cluster-secrets-manager) |
| 1 | App Secrets (openbao-{앱이름}-secrets-manager), PVC |
| (default) | Applications ({앱이름}) |

## 체크리스트

새 앱 `{앱이름}` 배포 시:

- [ ] Harbor 프로젝트 생성: `stg/{앱이름}`, `prod/{앱이름}`
- [ ] Helm 차트 생성: `helm/applications/{앱이름}/`
- [ ] ArgoCD Application: `{앱이름}-stg.yaml`, `{앱이름}-prod.yaml`
- [ ] OpenBao KV 경로: `{앱이름}/staging`, `{앱이름}/production`
- [ ] Secrets Manager: `openbao-{앱이름}-secrets-manager/`
- [ ] Helm 린트 확인

## 검증 명령어

```bash
# Helm 차트 린트
helm lint helm/applications/{앱이름}

# 템플릿 렌더링 (Staging)
helm template helm/applications/{앱이름} -f helm/applications/{앱이름}/values-stg.yaml

# 템플릿 렌더링 (Production)
helm template helm/applications/{앱이름} -f helm/applications/{앱이름}/values-prod.yaml

# ArgoCD 앱 상태
kubectl get applications -n argocd | grep {앱이름}
```
