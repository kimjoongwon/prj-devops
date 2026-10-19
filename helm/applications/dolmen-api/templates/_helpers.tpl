{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "dolmen-api.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "dolmen-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "dolmen-api.labels" -}}
helm.sh/chart: {{ include "dolmen-api.chart" . }}
{{ include "dolmen-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "dolmen-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dolmen-api.name" . }}
{{- end }}
