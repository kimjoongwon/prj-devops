# Namespace 통합 마이그레이션 가이드

기존 `fe-web-prod`, `fe-web-stg`, `be-server-prod`, `be-server-stg` namespace를 
`plate-prod`, `plate-stg`로 통합하는 마이그레이션 가이드입니다.

## 현재 상황

```bash
# 기존 namespace들 (제거 예정)
kubectl get namespaces | grep -E "(fe-web|be-server)"
fe-web-prod            Active   5d5h
fe-web-stg             Active   5d5h
be-server-prod         Active   5d5h (추정)
be-server-stg          Active   5d5h (추정)
```

## 마이그레이션 순서

### 1. 기존 ArgoCD 애플리케이션 제거

```bash
# ArgoCD CLI 사용
argocd app delete fe-web-prod --cascade
argocd app delete fe-web-stg --cascade
argocd app delete be-server-prod --cascade
argocd app delete be-server-stg --cascade
```

또는 ArgoCD UI에서 각 애플리케이션을 삭제 (Cascade 옵션 체크)

### 2. 기존 namespace 정리

```bash
# 기존 namespace들 삭제
kubectl delete namespace fe-web-prod
kubectl delete namespace fe-web-stg
kubectl delete namespace be-server-prod
kubectl delete namespace be-server-stg
```

### 3. 새로운 namespace 생성

```bash
# 통합 namespace 생성
kubectl create namespace plate-prod
kubectl create namespace plate-stg
```

### 4. 새로운 ArgoCD 애플리케이션 배포

#### App-of-Apps 배포
```bash
kubectl apply -f environments/argocd/app-of-apps.yaml
```

#### 개별 애플리케이션 배포 (선택사항)
```bash
kubectl apply -f environments/argocd/apps/plate-fe-web-prod.yaml
kubectl apply -f environments/argocd/apps/plate-fe-web-stg.yaml
kubectl apply -f environments/argocd/apps/plate-be-server-prod.yaml
kubectl apply -f environments/argocd/apps/plate-be-server-stg.yaml
kubectl apply -f environments/argocd/apps/plate-ingress-prod.yaml
kubectl apply -f environments/argocd/apps/plate-ingress-stg.yaml
```

## 마이그레이션 후 구조

### Namespace 구조
```
plate-prod:
├── fe-web (deployment, service)
├── be-server (deployment, service)
└── ingress (cocdev.co.kr)

plate-stg:
├── fe-web (deployment, service)
├── be-server (deployment, service)
└── ingress (stg.cocdev.co.kr)
```

### ArgoCD 애플리케이션
```
argocd namespace:
└── cocdev-platform-apps (App-of-Apps)
    ├── plate-fe-web-prod      → plate-prod
    ├── plate-fe-web-stg       → plate-stg
    ├── plate-be-server-prod   → plate-prod
    ├── plate-be-server-stg    → plate-stg
    ├── plate-ingress-prod     → plate-prod
    └── plate-ingress-stg      → plate-stg
```

## 확인 방법

### 1. Namespace 확인
```bash
kubectl get namespaces | grep plate
# 예상 출력:
# plate-prod     Active   1m
# plate-stg      Active   1m
```

### 2. ArgoCD 애플리케이션 확인
```bash
argocd app list | grep plate
# 또는 ArgoCD UI에서 확인
```

### 3. 서비스 확인
```bash
# Production 서비스
kubectl get svc -n plate-prod
# 예상: fe-web, be-server, ingress 관련 서비스들

# Staging 서비스  
kubectl get svc -n plate-stg
# 예상: fe-web, be-server, ingress 관련 서비스들
```

### 4. 도메인 접근 확인
```bash
curl -I https://cocdev.co.kr        # Production
curl -I https://stg.cocdev.co.kr    # Staging
curl -I https://cocdev.co.kr/api    # Production API
curl -I https://stg.cocdev.co.kr/api # Staging API
```

## 문제 해결

### Finalizers 문제
만약 namespace가 삭제되지 않는다면:
```bash
kubectl patch namespace [NAMESPACE_NAME] -p '{"metadata":{"finalizers":null}}'
```

### ArgoCD 동기화 문제
```bash
argocd app sync [APP_NAME] --force
```

### 상태 확인
```bash
kubectl get all -n plate-prod
kubectl get all -n plate-stg
```