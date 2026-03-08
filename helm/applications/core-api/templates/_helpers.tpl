{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "core-api.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "core-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "core-api.labels" -}}
helm.sh/chart: {{ include "core-api.chart" . }}
{{ include "core-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "core-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "core-api.name" . }}
{{- end }}
