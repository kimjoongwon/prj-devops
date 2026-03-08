{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "spring-api.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "spring-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "spring-api.labels" -}}
helm.sh/chart: {{ include "spring-api.chart" . }}
{{ include "spring-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "spring-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spring-api.name" . }}
{{- end }}
