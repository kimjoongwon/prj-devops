{{/* 기존 앱과 동일하게 ArgoCD Release 이름을 리소스 이름으로 사용한다. */}}
{{- define "cover-letter-web.name" -}}
{{- .Release.Name }}
{{- end }}

{{- define "cover-letter-web.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "cover-letter-web.labels" -}}
helm.sh/chart: {{ include "cover-letter-web.chart" . }}
{{ include "cover-letter-web.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "cover-letter-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cover-letter-web.name" . }}
{{- end }}
