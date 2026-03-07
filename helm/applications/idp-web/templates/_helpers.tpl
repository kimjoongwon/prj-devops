{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "idp-web.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "idp-web.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "idp-web.labels" -}}
helm.sh/chart: {{ include "idp-web.chart" . }}
{{ include "idp-web.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "idp-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "idp-web.name" . }}
{{- end }}
