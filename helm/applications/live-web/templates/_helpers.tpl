{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "live-web.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "live-web.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "live-web.labels" -}}
helm.sh/chart: {{ include "live-web.chart" . }}
{{ include "live-web.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "live-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "live-web.name" . }}
{{- end }}
