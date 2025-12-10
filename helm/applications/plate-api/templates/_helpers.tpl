{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "plate-api.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "plate-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "plate-api.labels" -}}
helm.sh/chart: {{ include "plate-api.chart" . }}
{{ include "plate-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "plate-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "plate-api.name" . }}
{{- end }}