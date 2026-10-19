{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "srs-server.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "srs-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "srs-server.labels" -}}
helm.sh/chart: {{ include "srs-server.chart" . }}
{{ include "srs-server.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels (SRS 서버)
*/}}
{{- define "srs-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "srs-server.name" . }}
{{- end }}

{{/*
Selector labels (데모 소스 푸셔)
*/}}
{{- define "srs-server.pusherSelectorLabels" -}}
app.kubernetes.io/name: {{ include "srs-server.name" . }}-pusher
{{- end }}
