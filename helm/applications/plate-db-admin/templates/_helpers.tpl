{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "plate-db-admin.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "plate-db-admin.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "plate-db-admin.labels" -}}
helm.sh/chart: {{ include "plate-db-admin.chart" . }}
{{ include "plate-db-admin.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: database-admin
{{- end }}

{{/*
Selector labels
*/}}
{{- define "plate-db-admin.selectorLabels" -}}
app.kubernetes.io/name: {{ include "plate-db-admin.name" . }}
{{- end }}
