{{/*
리소스 이름 (Release Name 사용)
*/}}
{{- define "plate-db.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
차트 이름과 버전
*/}}
{{- define "plate-db.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
공통 라벨
*/}}
{{- define "plate-db.labels" -}}
helm.sh/chart: {{ include "plate-db.chart" . }}
{{ include "plate-db.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: database
{{- end }}

{{/*
Selector 라벨
*/}}
{{- define "plate-db.selectorLabels" -}}
app.kubernetes.io/name: {{ include "plate-db.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Headless Service 이름
*/}}
{{- define "plate-db.headlessServiceName" -}}
{{- printf "%s-headless" (include "plate-db.name" .) }}
{{- end }}
