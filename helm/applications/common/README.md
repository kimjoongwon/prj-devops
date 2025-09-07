# 공통 Helm Templates

이 디렉토리는 참조용 템플릿들을 포함합니다.

## 현재 아키텍처 (Ingress)

**중앙 관리**: 모든 ingress는 `helm/ingress/templates/ingress.yaml`에서 중앙 관리됩니다.

### 파일 구조
```
helm/
├── ingress/                        # ingress 차트
│   ├── templates/ingress.yaml      # ingress 템플릿
│   ├── values.yaml                 # ingress 설정
│   └── Chart.yaml                  # ingress 차트
└── applications/
    ├── fe/web/                     # ingress.enabled: false
    ├── be/server/                  # ingress.enabled: false  
    └── common/
        ├── README.md               # 이 파일
        └── ingress-template.yaml   # 참조용 템플릿
```

### 현재 라우팅

**Production (cocdev.co.kr)**:
- `/` → `fe-web-prod:80` (Frontend)
- `/api` → `be-server-prod:8080` (Backend API)

**Staging (stg.cocdev.co.kr)**:
- `/` → `fe-web-stg:80` (Frontend)  
- `/api` → `be-server-stg:8080` (Backend API)

### 설정 변경

ingress 설정을 변경하려면 `helm/ingress/values.yaml` 파일을 수정하세요.

### 장점

- **중앙 관리**: 모든 라우팅 규칙을 한 곳에서 관리
- **CORS 문제 해결**: 단일 도메인으로 frontend/backend 제공
- **유지보수성**: 라우팅 변경 시 한 파일만 수정
- **일관성**: 모든 환경에서 동일한 라우팅 구조