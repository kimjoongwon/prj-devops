{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "admin-web.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "admin-web.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "admin-web.labels" -}}
helm.sh/chart: {{ include "admin-web.chart" . }}
{{ include "admin-web.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "admin-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "admin-web.name" . }}
{{- end }}
