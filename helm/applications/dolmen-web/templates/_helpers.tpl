{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "dolmen-web.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "dolmen-web.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "dolmen-web.labels" -}}
helm.sh/chart: {{ include "dolmen-web.chart" . }}
{{ include "dolmen-web.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "dolmen-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dolmen-web.name" . }}
{{- end }}
