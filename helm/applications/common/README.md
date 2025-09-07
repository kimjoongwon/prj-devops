# CocDev Platform 아키텍처

## 현재 구조

**Namespace 기반 분리**: `plate-prod`와 `plate-stg` namespace로 환경 분리

### 파일 구조
```
helm/
├── ingress/                        # ingress 차트
│   ├── templates/ingress.yaml      # ingress 템플릿
│   ├── values.yaml                 # production 설정
│   ├── values-stg.yaml            # staging 설정
│   └── Chart.yaml                  # ingress 차트
└── applications/
    ├── fe/web/                     # frontend 차트
    ├── be/server/                  # backend 차트
    └── common/
        └── README.md               # 이 파일
```

### 배포 구조

**Production** (`plate-prod` namespace):
- `cocdev.co.kr/` → `fe-web:80`
- `cocdev.co.kr/api` → `be-server:8080`

**Staging** (`plate-stg` namespace):
- `stg.cocdev.co.kr/` → `fe-web:80`
- `stg.cocdev.co.kr/api` → `be-server:8080`

### ArgoCD 애플리케이션

각 환경별로 3개의 애플리케이션:
- `fe-web-{env}`: Frontend 애플리케이션
- `be-server-{env}`: Backend 애플리케이션  
- `ingress-{env}`: Ingress 라우팅

### 설정 변경

- **Ingress**: `helm/ingress/values*.yaml`
- **Frontend**: `environments/{env}/fe-web-values.yaml`
- **Backend**: `environments/{env}/be-server-values.yaml`