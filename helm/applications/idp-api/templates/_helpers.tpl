{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "idp-api.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "idp-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "idp-api.labels" -}}
helm.sh/chart: {{ include "idp-api.chart" . }}
{{ include "idp-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "idp-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "idp-api.name" . }}
{{- end }}
