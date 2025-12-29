{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "spring-server.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "spring-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "spring-server.labels" -}}
helm.sh/chart: {{ include "spring-server.chart" . }}
{{ include "spring-server.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "spring-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spring-server.name" . }}
{{- end }}
