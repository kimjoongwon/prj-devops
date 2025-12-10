{{/*
Create app name (use Release Name for consistency)
*/}}
{{- define "plate-llm.name" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "plate-llm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "plate-llm.labels" -}}
helm.sh/chart: {{ include "plate-llm.chart" . }}
{{ include "plate-llm.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "plate-llm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "plate-llm.name" . }}
{{- end }}
