{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "tool-storybook.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "tool-storybook.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "tool-storybook.labels" -}}
helm.sh/chart: {{ include "tool-storybook.chart" . }}
{{ include "tool-storybook.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "tool-storybook.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tool-storybook.name" . }}
{{- end }}
