{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "plate-web.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "plate-web.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "plate-web.labels" -}}
helm.sh/chart: {{ include "plate-web.chart" . }}
{{ include "plate-web.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "plate-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "plate-web.name" . }}
{{- end }}
