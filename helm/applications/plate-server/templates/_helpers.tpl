{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "plate-server.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "plate-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "plate-server.labels" -}}
helm.sh/chart: {{ include "plate-server.chart" . }}
{{ include "plate-server.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "plate-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "plate-server.name" . }}
{{- end }}
