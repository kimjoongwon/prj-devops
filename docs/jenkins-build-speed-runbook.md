# Jenkins 빌드 속도 개선 운영 런북

## 목적

- Jenkins 빌드 파이프라인의 1차 플래그 개선, podman v5 전환, public-ci pnpm 캐시,
  BuildKit 영속 캐시 도입을 단계별로 검증하고 안전하게 롤백할 수 있게 한다.
- 각 단계는 독립적으로 진행/중단할 수 있으며, 뒤 단계는 앞 단계 완료를 전제로 하지 않는다.

## 대상 및 관련 파일

| 항목 | 위치 |
| --- | --- |
| 1차 플래그 개선 대상 Jenkinsfile/Dockerfile | prj-core `devops/Jenkinsfile.*`, `devops/Dockerfile.*` |
| GitOps 얕은 clone(depth 5) | prj-core `devops/Jenkinsfile.gitops-update` |
| container-builder-pvc 정리 스크립트 | prj-devops `scripts/jenkins/cleanup-container-builder.sh` |
| pnpm 스토어 공유 캐시 PVC | prj-devops `helm/applications/plate-cache/` (`pnpm-store-pvc`) |
| BuildKit 데몬 차트/앱 | prj-devops `helm/development-tools/buildkitd/`, `environments/argocd/apps/buildkitd.yaml` |
| 외부 PR CI | prj-core `devops/Jenkinsfile.public-ci`, `devops/README.public-ci.md` |

공통 전제:

- Jenkins 컨트롤러와 agent pod는 `devops-tools` 네임스페이스에서 실행된다
  (`helm/development-tools/jenkins/values.yaml`의 `agent.namespace` 미설정 → 컨트롤러 네임스페이스 상속).
- `container-builder-pvc`(RWO, openebs-hostpath), `pnpm-store-pvc`(RWX, nfs-client),
  `buildkitd` 모두 `devops-tools` 네임스페이스에 둔다.
- 실제 자격증명·시크릿 값은 어느 저장소에도 커밋하지 않는다. 시크릿은 런북의
  `kubectl create secret` 명령으로만 생성한다.

---

## 1. 1차 플래그 개선 검증 (stg)

대상 개선 (prj-core devops 기존 변경):

- podman push `--compression-format=gzip --compression-level=6` (압축 단계 완화)
- agent `alwaysPullImage: false` (podman 이미지 매 빌드 재풀 제거)
- podman build에서 `--pull=always` 제거 (로컬 레이어 캐시 활용)
- `Jenkinsfile.gitops-update`의 `git clone --depth 5` (GitOps 저장소 얕은 clone)
- `Dockerfile.*` 캐시 정합성 정리 (의존성 설치 계층이 소스 변경에 무관하게 재사용되도록 순서 고정)

### 절차

1. 위 변경을 stg 브랜치 잡(idp-web 등)에 반영한 커밋을 빌드한다.
2. 동일 커밋으로 2회째 빌드를 실행한다. (젠킨스 재실행/Rebuild, 커밋·체크아웃 변경 없음)
3. Jenkins 콘솔 출력의 타임스탬프로 stage별 소요 시간을 비교한다.
   콘솔에 시각이 없으면 "Pipeline Steps"와 각 `sh` 단계의 시작-종료 시각으로 비교한다.
4. `pnpm install` 단계 캐시 히트 확인: 2회째 빌드의 podman build 로그에서
   pnpm install 관련 계층이 재실행되지 않고 캐시로 넘어가는지 확인한다.
5. gitops-update 잡 로그에서 depth 5 clone이 적용됐는지 확인한다.

### 완료 판정 기준

- 2회째 빌드의 이미지 빌드 stage가 1회째보다 유의미하게 짧고, 의존성 설치 계층이 재실행되지 않는다.
- push 소요 시간이 gzip 6 적용 후 악화되지 않았다.
- podman 컨테이너 시작 직후 이미지 pull 대기(콜 다운로드 로그)가 발생하지 않는다.

### 롤백 방법

- 클러스터 변경이 없으므로 prj-core의 Jenkinsfile/Dockerfile 변경을 revert 커밋한다.

---

## 2. podman v4.8.2 → v5.8.4 전환

배경: podman 이미지를
`quay.io/podman/stable:v5.8.4@sha256:3c99be9108dacd2b25d2f343c91386abd14a5ceaca68aa3e8d7f6ee2ebd50a16`
(digest 고정)로 올리고 build에 `--pull=newer`를 적용한다.

### 실행 순서

(a) container-builder-pvc 스토어 초기화 — 클린 스토어로 시작해 포맷 마이그레이션 회피:

1. 빌드 잡이 돌지 않는 시간대에 `scripts/jenkins/cleanup-container-builder.sh`를 실행한다.
2. PVC 사용 Pod 확인 단계에서 사용 중 Pod가 없는지 확인한다.
3. 정리 옵션에서 "1) 전체 삭제 (모든 이미지, 캐시, 볼륨 삭제)"를 선택해 스토어를 초기화한다.

(b) prj-core의 6개 Jenkinsfile 변경 반영 — 대상: `Jenkinsfile.admin-web`, `Jenkinsfile.core-api`,
`Jenkinsfile.idp-api`, `Jenkinsfile.idp-web`, `Jenkinsfile.proposal-web`, `Jenkinsfile.tool-storybook`:

1. podman 이미지를 v5.8.4 digest로 교체한다.
2. `podman build`에 `--pull=newer`를 적용한다.
3. main/stg 보호 브랜치에 반영한다.

(c) stg 잡부터 빌드 검증:

1. stg 잡(idp-web 등)을 실행해 login/build/push/rmi 전 단계가 v5에서 정상 동작하는지 확인한다.
2. 동일 커밋 재빌드로 `--layers` 캐시가 그대로 적중되는지 확인한 뒤 prod 잡으로 확산한다.

### 주의사항

- 6개 잡은 동시 전환을 권장한다. v5가 스토어를 마이그레이션한 뒤 v4.8.2 이미지를 쓰는 잡이
  남아 있으면 같은 PVC를 읽지 못할 수 있다.
- 전환 후 4.x 이미지로 되돌리면 마이그레이션된 스토어를 못 읽을 수 있다.
  롤백 시에는 cleanup 스크립트(옵션 1, 전체 삭제)로 스토어를 초기화한 뒤 되돌린다.
  레이어 캐시 손실은 감수하고, 베이스/런타임 이미지는 재풀로 자연 회복된다.

### 완료 판정 기준

- 6개 잡 모두 v5.8.4 digest로 실행 중이고 빌드-푸시-GitOps 트리거까지 성공한다.
- 동일 커밋 재빌드에서 레이어 캐시가 적중해 2회째 빌드가 짧아진다.
- 초기화 직후 첫 빌드의 전체 시간을 기록해 둔다(이후 캐시 워밍 기준선).

### 롤백 방법

1. prj-core의 Jenkinsfile 변경을 revert 커밋한다.
2. `scripts/jenkins/cleanup-container-builder.sh` 옵션 1으로 스토어를 초기화한다.
3. 다음 몇 회 빌드는 이미지 재풀로 느려졌다가 자연 회복된다.

---

## 3. public-ci pnpm 캐시 (pnpm-store-pvc)

배경: 외부 PR CI(`Jenkinsfile.public-ci`)는 매 PR 임의 노드에서 pod가 떠서 pnpm install이
매번 콜드로 실행된다. `pnpm-store-pvc`(RWX, NFS `nfs-client`)로 pnpm 스토어를 공유해 이를 제거한다.

### 절차

1. pnpm-store-pvc 배포 확인:
   - prj-devops에 `helm/applications/plate-cache` 변경을 merge하면 ArgoCD `plate-cache` 앱이
     자동 동기화한다(기본 폴링 3분). 즉시 반영은 `argocd app sync plate-cache`.
   - 확인 명령:

     ```bash
     kubectl -n devops-tools get pvc pnpm-store-pvc
     # 기대: Bound / ReadWriteMany / nfs-client / 20Gi
     ```

2. prj-core `Jenkinsfile.public-ci` 변경 반영: agent pod 정의에 `pnpm-store-pvc`를 마운트하고
   pnpm store 위치를 해당 볼륨 경로로 지정한다.
3. 검증: 외부 PR 1건으로 install 시간을 비교한다. 변경 전 콘솔 로그(또는 직전 PR 빌드)와
   `pnpm install --frozen-lockfile` 단계 시간을 대비하고, 패키지 다운로드 대신
   스토어 복원(하드링크) 로그가 나오는지 확인한다.
4. 문제 시(NFS 손상·권한 오류·store 무결성 오류): 스토어 디렉터리를 클리어하고 재검증한다.

### 완료 판정 기준

- 서로 다른 PR 연속 실행에서 두 번째 PR부터 pnpm install이 눈에 띄게 짧아진다.
- public-ci의 나머지 단계(public-packages:check, type-check, lint, test) 결과에 변화가 없다.

### 롤백 방법

- prj-core `Jenkinsfile.public-ci`에서 마운트/store 지정 변경을 revert한다.
- PVC를 비활성화하려면 plate-cache values의 `pnpmStore.enabled`를 false로 바꾸고 ArgoCD 동기화한다.
  (기존 데이터 삭제는 별도 판단 후 수동 실시)

---

## 4. BuildKit 파일럿 (tool-storybook)

배경: 젠킨스 빌드 전용 BuildKit 데몬(`buildkitd`, rootless)을 `devops-tools`에 두고
`RUN --mount=type=cache` 캐시를 PVC에 영속화한다. 파일럿 대상은 tool-storybook이며,
파일럿 잡은 `devops/Jenkinsfile.tool-storybook.buildkit`(prj-core)을 사용한다.
배포 파일: `helm/development-tools/buildkitd/` + `environments/argocd/apps/buildkitd.yaml`.

### (a) buildkitd 배포

1. ArgoCD: prj-devops merge 후 `buildkitd` 앱 자동 동기화(3분) 또는 `argocd app sync buildkitd`.
   수동 대안:

   ```bash
   helm upgrade --install buildkitd helm/development-tools/buildkitd -n devops-tools
   ```

2. 확인 명령:

   ```bash
   kubectl -n devops-tools get pvc buildkit-cache-pvc   # Bound / RWO / openebs-hostpath / 50Gi
   kubectl -n devops-tools get pods -l app.kubernetes.io/name=buildkitd
   kubectl -n devops-tools get svc buildkitd            # TCP 1234
   ```

완료 판정: pod Running 1/1(readiness `buildctl debug workers` 통과), PVC Bound.
시크릿이 없으면 pod가 CreateContainerConfigError로 대기하므로 (b)를 먼저 진행해도 된다.

### (b) buildkit-registry-config 시크릿 생성

Harbor 로봇 계정을 사용한다. 값은 Git에 커밋하지 않고 아래 명령으로만 생성한다.
Deployment는 이 시크릿(`.dockerconfigjson` 키)을 `config.json`으로 매핑해
`/home/user/.docker/config.json`에 마운트하므로, 아래 형식이 곧 마운트와 짝이 된다.

```bash
kubectl -n devops-tools create secret docker-registry buildkit-registry-config \
  --docker-server=harbor.onjitda.com \
  --docker-username='<harbor robot 계정명>' \
  --docker-password='<harbor robot secret>'
```

갱신 시에는 `--dry-run=client -o yaml | kubectl apply -f -`로 교체하고 buildkitd를 재시작한다.

### (c) Jenkins 신규 pipeline job 수동 생성

파일럿은 Job DSL에 넣지 않고 Jenkins UI에서 수동 생성한다.
기존 잡 생성 관례(보호 브랜치, 주입 값, 권한 제한)는 prj-core `devops/README.public-ci.md`를 따른다.

- Pipeline from SCM: prj-core 저장소, 보호 브랜치(main) 고정,
  Script Path `devops/Jenkinsfile.tool-storybook.buildkit`
- 주입 환경값:
  - `TRUSTED_DEPLOYMENT=true` (내부 배포 잡 보호값)
  - `HARBOR_REGISTRY=harbor.onjitda.com`
  - `HARBOR_CREDENTIAL_ID` (Harbor push credential ID)
  - `GITOPS_UPDATE_JOB` (기존 gitops 이미지 태그 갱신 잡)
- 승인된 사용자만 수동 실행·설정 변경 가능하도록 잡 권한을 제한한다.

### (d) 파일럿 검증

1. 동일 커밋으로 2회 연속 빌드한다.
2. buildctl `--progress=plain` 로그에서 2회째 빌드에 `CACHED` 라인(RUN --mount=type=cache 대상 단계)이
   찍히는지, 단계별 소요 시간이 짧아지는지 비교한다.
3. Harbor push 성공을 확인한다(프로젝트 `prod/tool-storybook`, 태그 = BUILD_NUMBER).
4. GitOps 갱신 → ArgoCD 동기화 후 tool-storybook 앱이 정상 기동하는지 확인한다.

완료 판정: 2회째 빌드의 캐시 적중, Harbor push, 앱 기동이 모두 확인되면 파일럿 통과.

### (e) 통과 시 확산

1. 본 `Jenkinsfile.tool-storybook`을 buildctl 방식으로 전환한다.
2. 파일럿 파일 `devops/Jenkinsfile.tool-storybook.buildkit`과 파일럿 잡을 제거한다.
3. 이후 다른 앱으로 확산한다(프론트 계열부터). 확산 속도는 watch-item 관찰 결과에 따라 조절한다.

### (f) 롤백 방법

1. 파일럿 Jenkins 잡을 UI에서 삭제한다(본 잡은 그대로 podman 방식으로 운영된다).
2. buildkitd 배포를 중단한다: `argocd app delete buildkitd` 또는
   `helm -n devops-tools uninstall buildkitd`.
3. `buildkit-cache-pvc`는 유지한다(삭제하지 않는다). 재배포 시 캐시를 재사용할 수 있다.

---

## 5. watch-item 목록

- **buildkit 데몬 ulimit 기본값과 storybook 빌드의 nofile 요구**: podman 시절
  `--ulimit nofile=65536:65536`을 줬던 것과 동일 관점이다. Kubernetes는 컨테이너 ulimit를
  직접 지정할 수 없으므로 buildkitd 컨테이너의 nofile 기본값이 storybook 번들링의 파일 수를
  감당하는지를 파일 디스크립터 오류(too many open files) 발생 여부로 관찰한다.
  부족하면 노드/컨테이너 런타임 수준의 nofile 조정이나 빌드 분할을 검토한다.
- **buildkitd 단일 인스턴스 병렬 빌드 처리량**: `replicaCount: 1`이고 캐시 PVC가 RWO라
  replica 확장은 불가하다. 여러 잡이 동시에 붙을 때 대기·처리량 저하가 있는지 관찰하고,
  한계가 오면 앱 그룹별 buildkitd 인스턴스 분리 또는 아키텍처 재검토를 논의한다.
- **캐시 PVC 용량 증가 추이**: buildkit GC 상한(`gckeepstorage` 40GB, gcpolicy keepBytes 40GB,
  keepDuration 168h)과 PVC(50Gi) 사이 여유를 관찰한다. 점검 명령:

  ```bash
  kubectl -n devops-tools exec deploy/buildkitd -- buildctl du
  ```

  또한 `pnpm-store-pvc`(20Gi, NFS) 사용량도 함께 관찰해 증설 시점을 판단한다.
