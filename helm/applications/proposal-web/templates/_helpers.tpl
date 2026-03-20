{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "proposal-web.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "proposal-web.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "proposal-web.labels" -}}
helm.sh/chart: {{ include "proposal-web.chart" . }}
{{ include "proposal-web.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "proposal-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "proposal-web.name" . }}
{{- end }}
