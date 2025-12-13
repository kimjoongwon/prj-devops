# 모니터링 스택 (Prometheus & Grafana)

<cite>
**이 문서에서 참조한 파일**  
- [prometheus/Chart.yaml](file://helm/development-tools/prometheus/Chart.yaml)
- [prometheus/values.yaml](file://helm/development-tools/prometheus/values.yaml)
- [grafana/Chart.yaml](file://helm/development-tools/grafana/Chart.yaml)
- [grafana/values.yaml](file://helm/development-tools/grafana/values.yaml)
- [promtail/Chart.yaml](file://helm/development-tools/promtail/Chart.yaml)
- [promtail/values.yaml](file://helm/development-tools/promtail/values.yaml)
</cite>

## 목차
1. [소개](#소개)
2. [프로메테우스 구성 분석](#프로메테우스-구성-분석)
3. [Grafana 설정 및 통합](#grafana-설정-및-통합)
4. [Promtail을 통한 로그 수집 파이프라인](#promtail을-통한-로그-수집-파이프라인)
5. [경고 규칙 및 Alertmanager 통합](#경고-규칙-및-alertmanager-통합)
6. [대시보드 커스터마이징 및 운영 전략](#대시보드-커스터마이징-및-운영-전략)
7. [결론](#결론)

## 소개

이 문서는 Kubernetes 기반 환경에서 Prometheus와 Grafana로 구성된 모니터링 스택의 구현을 상세히 설명합니다. 프로메테우스를 통한 메트릭 수집, Alertmanager를 활용한 경고 알림 시스템, Grafana를 통한 시각화 및 대시보드 설정, 그리고 Promtail을 통한 로그 수집 파이프라인의 통합 방식을 다룹니다. 또한 주요 메트릭 수집 대상, 경고 규칙 설정, 대시보드 커스터마이징 방법을 설명하고, 실제 운영 환경에서의 모니터링 전략을 제시합니다.

이 모니터링 스택은 Helm 차트를 기반으로 구성되며, `helm/development-tools/` 디렉터리 내에 위치한 `prometheus`, `grafana`, `promtail` 차트를 통해 배포됩니다. 각 구성 요소는 독립적으로 설정되며, 서로 간의 통합을 통해 종합적인 관측성(observability)을 제공합니다.

## 프로메테우스 구성 분석

프로메테우스는 애플리케이션 및 인프라의 메트릭을 수집하고 저장하는 핵심 구성 요소입니다. `helm/development-tools/prometheus` 디렉터리에 위치한 Helm 차트를 통해 배포되며, `Chart.yaml`과 `values.yaml` 파일을 통해 상세한 구성이 이루어집니다.

`Chart.yaml` 파일을 통해 프로메테우스의 기본 정보와 종속성(Dependencies)을 확인할 수 있습니다. 이 차트는 Alertmanager, kube-state-metrics, prometheus-node-exporter, prometheus-pushgateway 등의 핵심 컴포넌트를 종속성으로 포함하고 있습니다. 이는 프로메테우스가 단순한 메트릭 수집기 이상의 기능을 수행할 수 있도록 합니다.

`values.yaml` 파일은 프로메테우스의 세부적인 동작을 제어합니다. 주요 구성 항목은 다음과 같습니다:

- **글로벌 설정**: `scrape_interval` (1분), `scrape_timeout` (10초), `evaluation_interval` (1분) 등의 기본 주기를 정의합니다.
- **서버 구성**: `server` 섹션을 통해 프로메테우스 서버의 컨테이너 이미지, 리소스 요청 및 제한, 보안 컨텍스트 등을 설정합니다. `securityContext`를 통해 `runAsUser: 65534`로 비특권 사용자로 실행되도록 보장합니다.
- **지속성**: `persistentVolume`을 통해 데이터를 영구적으로 저장할 수 있도록 하며, `storageClass: openebs-hostpath`를 사용하여 스토리지 클래스를 지정합니다. 이는 프로메테우스 재시작 시에도 수집된 메트릭 데이터를 유지할 수 있게 합니다.
- **Ingress 구성**: `ingress.enabled: true`로 설정되어 외부에서 프로메테우스 웹 UI에 접근할 수 있도록 합니다. `hosts`에 `prometheus.cocdev.co.kr`이 정의되어 있으며, `cert-manager`를 통해 TLS 인증서를 자동으로 발급받습니다.

이러한 구성은 프로메테우스가 안정적으로 메트릭을 수집하고, 외부 접근이 가능하며, 데이터 손실 없이 장기간 운영될 수 있도록 합니다.

**Section sources**
- [prometheus/Chart.yaml](file://helm/development-tools/prometheus/Chart.yaml#L1-L59)
- [prometheus/values.yaml](file://helm/development-tools/prometheus/values.yaml#L1-L800)

## Grafana 설정 및 통합

Grafana는 수집된 메트릭 데이터를 시각화하고 대시보드를 제공하는 프론트엔드 도구입니다. `helm/development-tools/grafana` 디렉터리에 위치한 Helm 차트를 통해 배포됩니다.

`Chart.yaml` 파일은 Grafana의 기본 정보와 소스를 명시합니다. 이 차트는 Grafana 프로젝트의 공식 Helm 차트를 기반으로 합니다.

`values.yaml` 파일은 Grafana의 다양한 기능을 설정합니다. 주요 구성 항목은 다음과 같습니다:

- **기본 설정**: `adminUser`와 `adminPassword`를 통해 초기 관리자 계정을 정의합니다. 보안을 위해 `admin.existingSecret`을 사용하여 비밀번호를 외부 비밀 관리자(예: OpenBao)와 통합할 수 있습니다.
- **지속성**: `persistence.enabled: true`로 설정되어 대시보드 및 구성 정보를 영구적으로 저장합니다. `storageClassName: openebs-hostpath`를 사용하며, `volumeName: grafana-pv-volume`을 통해 기존의 PV(Persistent Volume)에 바인딩됩니다.
- **Ingress 구성**: `ingress.enabled: true`로 설정되어 외부에서 Grafana 웹 UI에 접근할 수 있습니다. `hosts`에 `grafana.cocdev.co.kr`이 정의되어 있으며, `cert-manager`를 통해 TLS 인증서를 자동으로 발급받습니다.
- **데이터 소스 통합**: `datasources` 섹션을 통해 Grafana가 프로메테우스를 데이터 소스로 사용하도록 구성할 수 있습니다. 이 설정을 통해 Grafana 대시보드에서 프로메테우스로부터 수집된 메트릭을 쿼리하고 시각화할 수 있습니다.
- **플러그인**: `plugins` 리스트를 통해 필요한 플러그인을 사전 설치할 수 있습니다.

Grafana는 프로메테우스와의 통합을 통해 수집된 메트릭을 효과적으로 시각화하며, 운영팀이 시스템 상태를 직관적으로 파악할 수 있도록 지원합니다.

**Section sources**
- [grafana/Chart.yaml](file://helm/development-tools/grafana/Chart.yaml#L1-L36)
- [grafana/values.yaml](file://helm/development-tools/grafana/values.yaml#L1-L800)

## Promtail을 통한 로그 수집 파이프라인

Promtail은 Kubernetes 클러스터 내의 노드에서 로그를 수집하여 Loki 인스턴스로 전송하는 에이전트입니다. `helm/development-tools/promtail` 디렉터리에 위치한 Helm 차트를 통해 배포됩니다.

`Chart.yaml` 파일은 Promtail의 기본 정보와 소스를 명시합니다. 이 차트는 Grafana의 Loki 프로젝트에서 제공하는 공식 Helm 차트를 기반으로 합니다.

`values.yaml` 파일은 Promtail의 동작 방식을 상세히 정의합니다. 주요 구성 항목은 다음과 같습니다:

- **배포 유형**: `daemonset.enabled: true`로 설정되어 모든 워커 노드에 Promtail 파드가 실행되도록 합니다. 이는 클러스터 내 모든 파드의 로그를 수집할 수 있도록 보장합니다.
- **보안 컨텍스트**: `podSecurityContext`를 통해 `runAsUser: 0` (루트 사용자)로 실행되도록 설정합니다. 이는 `/var/log/pods` 및 `/var/lib/docker/containers`와 같은 호스트의 로그 디렉터리에 접근하기 위해 필요합니다.
- **볼륨 마운트**: `defaultVolumes`와 `defaultVolumeMounts`를 통해 호스트의 로그 디렉터리를 파드 내부로 마운트합니다. 이를 통해 컨테이너 로그 파일을 읽을 수 있습니다.
- **Loki 엔드포인트**: `config.clients` 섹션에서 `url: http://loki-gateway/loki/api/v1/push`를 통해 로그를 전송할 Loki 게이트웨이의 엔드포인트를 지정합니다.
- **리레이블링 구성**: `config.snippets.common` 및 `config.snippets.scrapeConfigs`를 통해 Kubernetes 메타데이터(예: namespace, pod, container)를 로그 스트림의 레이블로 추출합니다. 이는 Loki에서 로그를 효율적으로 쿼리할 수 있도록 합니다.

이러한 구성은 Promtail이 클러스터 전반의 로그를 수집하고, 메타데이터와 함께 Loki로 전달하여 중앙 집중적인 로그 관리 및 분석을 가능하게 합니다.

**Section sources**
- [promtail/Chart.yaml](file://helm/development-tools/promtail/Chart.yaml#L1-L18)
- [promtail/values.yaml](file://helm/development-tools/promtail/values.yaml#L1-L648)

## 경고 규칙 및 Alertmanager 통합

프로메테우스는 단순한 메트릭 수집을 넘어, 설정된 조건에 따라 경고를 생성할 수 있는 강력한 기능을 제공합니다. 이 기능은 `prometheus` Helm 차트의 `values.yaml` 파일 내 `alertmanagers` 섹션을 통해 Alertmanager와 통합됩니다.

프로메테우스는 자체적으로 경고 규칙(alerting rules)을 평가합니다. 이 규칙은 `values.yaml` 파일 내에서 직접 정의하거나, 별도의 ConfigMap을 통해 관리할 수 있습니다. 규칙은 특정 메트릭이 임계값을 초과하는지 등을 감시하며, 조건이 충족되면 경고를 생성합니다.

생성된 경고는 Alertmanager로 전송됩니다. Alertmanager는 경고의 중복 제거, 그룹화, 라우팅 및 알림 전송을 담당합니다. 예를 들어, 동일한 문제에 대한 여러 경고를 하나의 알림으로 그룹화하거나, 특정 경고를 Slack, 이메일, PagerDuty 등의 채널로 전송할 수 있습니다.

이 문서에서 제공된 `values.yaml` 파일에는 Alertmanager의 구체적인 경고 규칙은 포함되어 있지 않지만, `prometheus` 차트가 Alertmanager 종속성을 선언하고 있으며, `server.alertmanagers` 설정을 통해 연결될 수 있도록 준비되어 있습니다. 이는 경고 시스템이 구조적으로 준비되어 있음을 의미합니다.

**Section sources**
- [prometheus/Chart.yaml](file://helm/development-tools/prometheus/Chart.yaml#L1-L59)
- [prometheus/values.yaml](file://helm/development-tools/prometheus/values.yaml#L628-L630)

## 대시보드 커스터마이징 및 운영 전략

Grafana는 강력한 대시보드 기능을 제공하며, 이를 통해 운영 전략을 수립할 수 있습니다.

- **대시보드 통합**: `values.yaml`의 `datasources` 섹션을 통해 프로메테우스를 기본 데이터 소스로 설정함으로써, 모든 대시보드가 실시간 메트릭을 기반으로 동작합니다.
- **커스터마이징**: `plugins` 설정을 통해 다양한 시각화 플러그인을 사전 설치할 수 있습니다. 또한, `extraConfigmapMounts`를 사용하여 외부에서 관리되는 대시보드 JSON 파일을 마운트할 수 있어, GitOps 방식으로 대시보드를 버전 관리하고 배포할 수 있습니다.
- **운영 전략**: 
    1. **계층적 모니터링**: 애플리케이션, 미들웨어, 인프라 등 계층별로 대시보드를 구성하여 문제를 신속하게 격리합니다.
    2. **SLO 기반 경고**: 서비스 수준 목표(SLO)를 기반으로 경고를 설정하여, 사용자 경험에 영향을 미치기 전에 문제를 탐지합니다.
    3. **로깅-메트릭 연계**: Promtail을 통해 수집된 로그와 프로메테우스의 메트릭을 Grafana에서 동시에 조회함으로써, 문제 원인을 보다 정확하게 진단할 수 있습니다.
    4. **보안 및 접근 제어**: Grafana의 RBAC 기능을 활용하여 팀별로 대시보드 접근 권한을 제어합니다.

이러한 전략은 모니터링 스택을 단순한 도구가 아닌, 시스템의 안정성과 가시성을 높이는 핵심 운영 인프라로 발전시킵니다.

**Section sources**
- [grafana/values.yaml](file://helm/development-tools/grafana/values.yaml#L676-L677)
- [grafana/values.yaml](file://helm/development-tools/grafana/values.yaml#L164-L165)

## 결론

본 문서는 Prometheus, Grafana, Promtail로 구성된 모니터링 스택의 구현을 상세히 분석하였습니다. 각 구성 요소는 Helm 차트를 통해 선언적으로 배포되며, `values.yaml` 파일을 통해 세밀한 구성이 가능합니다.

프로메테우스는 안정적인 메트릭 수집과 저장을 담당하며, Alertmanager와의 통합을 통해 강력한 경고 시스템을 구축합니다. Grafana는 이를 기반으로 직관적인 대시보드를 제공하며, Promtail은 클러스터 전반의 로그를 수집하여 Loki로 전달함으로써, 메트릭과 로그를 통합한 종합적인 관측성 환경을 완성합니다.

이 스택은 `openebs-hostpath` 스토리지 클래스를 사용하여 데이터의 지속성을 보장하며, `cert-manager`와의 통합을 통해 안전한 외부 접근을 제공합니다. 이러한 구현은 현대적인 클라우드 네이티브 환경에서 시스템의 가시성과 안정성을 확보하는 데 매우 효과적인 접근 방식입니다.