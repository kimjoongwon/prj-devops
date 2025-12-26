{{/*
Expand the name of the chart.
*/}}
{{- define "openbao-admin-secrets-manager.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "openbao-admin-secrets-manager.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "openbao-admin-secrets-manager.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "openbao-admin-secrets-manager.labels" -}}
helm.sh/chart: {{ include "openbao-admin-secrets-manager.chart" . }}
{{ include "openbao-admin-secrets-manager.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "openbao-admin-secrets-manager.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openbao-admin-secrets-manager.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
SecretStore name
*/}}
{{- define "openbao-admin-secrets-manager.secretStoreName" -}}
{{- .Values.externalSecrets.secretStore.name | default (printf "%s-secretstore" (include "openbao-admin-secrets-manager.fullname" .)) }}
{{- end }}

{{/*
ExternalSecret name
*/}}
{{- define "openbao-admin-secrets-manager.externalSecretName" -}}
{{- .Values.externalSecrets.externalSecret.name | default (printf "%s-externalsecret" (include "openbao-admin-secrets-manager.fullname" .)) }}
{{- end }}

{{/*
Target secret name
*/}}
{{- define "openbao-admin-secrets-manager.targetSecretName" -}}
{{- .Values.externalSecrets.externalSecret.target.name | default (printf "%s-secret" (include "openbao-admin-secrets-manager.fullname" .)) }}
{{- end }}
