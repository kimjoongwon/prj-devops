{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "design-web.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "design-web.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "design-web.labels" -}}
helm.sh/chart: {{ include "design-web.chart" . }}
{{ include "design-web.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "design-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "design-web.name" . }}
{{- end }}
