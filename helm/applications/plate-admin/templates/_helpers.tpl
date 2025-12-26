{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "plate-admin.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "plate-admin.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "plate-admin.labels" -}}
helm.sh/chart: {{ include "plate-admin.chart" . }}
{{ include "plate-admin.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "plate-admin.selectorLabels" -}}
app.kubernetes.io/name: {{ include "plate-admin.name" . }}
{{- end }}
