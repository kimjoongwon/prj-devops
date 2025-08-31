# ArgoCD Application 설정

Frontend Web 애플리케이션을 위한 ArgoCD GitOps 설정입니다.

## 📁 구조

```
environments/argocd/
├── README.md                          # 이 파일
├── app-of-apps.yaml                  # App of Apps 패턴 메인 Application
└── apps/
    ├── frontend-web-production.yaml  # Production 환경 Application
    └── frontend-web-staging.yaml     # Staging 환경 Application
```

## 🚀 ArgoCD 연결 방법

### 1. Git Repository URL 수정
각 Application 파일에서 `repoURL`을 실제 Git Repository로 변경:

```yaml
source:
  repoURL: https://github.com/your-username/prj-devops.git  # 실제 URL로 변경
```

### 2. App of Apps 배포
```bash
# ArgoCD CLI 또는 UI를 통해 메인 Application 생성
kubectl apply -f environments/argocd/app-of-apps.yaml
```

### 3. 자동 배포 확인
- ArgoCD가 `app-of-apps.yaml`을 감지
- `apps/` 폴더의 모든 Application들이 자동 생성
- 각 환경별 자동 배포 시작

## 🎯 배포 환경

### Production 환경
- **Namespace**: `frontend-web-prod`
- **Domain**: `cocdev.co.kr`, `www.cocdev.co.kr`
- **Admin**: `k8s.cocdev.co.kr`
- **Image**: `nginx:1.25` (안정 버전)
- **Replicas**: 2

### Staging 환경
- **Namespace**: `frontend-web-staging`
- **Domain**: `stg.cocdev.co.kr`
- **Admin**: `k8s.cocdev.co.kr` (staging)
- **Image**: `nginx:latest` (최신 버전)
- **Replicas**: 1

## 🔄 GitOps 워크플로우

1. **코드 변경**: `helm/applications/frontend/web/` 또는 `environments/*/` 수정
2. **Git Push**: main 브랜치에 푸시
3. **ArgoCD 감지**: 3분 이내 자동 감지
4. **자동 배포**: 변경사항 자동 적용
5. **상태 동기화**: Kubernetes와 Git 상태 일치

## ⚙️ 설정 변경

### 이미지 버전 변경
```yaml
# frontend-web-production.yaml
helm:
  parameters:
    - name: image.tag
      value: "1.26"  # 원하는 버전으로 변경
```

### Values 파일 수정
- Production: `environments/production/frontend-web-values.yaml`
- Staging: `environments/staging/frontend-web-values.yaml`

### 동기화 정책 조정
```yaml
syncPolicy:
  automated:
    prune: true      # 삭제된 리소스 자동 정리
    selfHeal: true   # 수동 변경사항 되돌리기
```

## 🛡️ 보안 고려사항

- **Git Repository**: Private repository 사용 권장
- **ArgoCD Access**: RBAC으로 접근 제한
- **Secret Management**: External Secrets 또는 Sealed Secrets 사용
- **Image Security**: 컨테이너 이미지 스캔 적용