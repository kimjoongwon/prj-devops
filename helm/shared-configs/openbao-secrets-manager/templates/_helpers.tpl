{{/*
Expand the name of the chart.
*/}}
{{- define "openbao-secrets-manager.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "openbao-secrets-manager.fullname" -}}
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
{{- define "openbao-secrets-manager.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "openbao-secrets-manager.labels" -}}
helm.sh/chart: {{ include "openbao-secrets-manager.chart" . }}
{{ include "openbao-secrets-manager.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "openbao-secrets-manager.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openbao-secrets-manager.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
SecretStore name
*/}}
{{- define "openbao-secrets-manager.secretStoreName" -}}
{{- .Values.externalSecrets.secretStore.name | default (printf "%s-secretstore" (include "openbao-secrets-manager.fullname" .)) }}
{{- end }}

{{/*
ExternalSecret name for environment variables
*/}}
{{- define "openbao-secrets-manager.externalSecretName" -}}
{{- .Values.externalSecrets.externalSecret.name | default (printf "%s-externalsecret" (include "openbao-secrets-manager.fullname" .)) }}
{{- end }}

{{/*
Target secret name for environment variables
*/}}
{{- define "openbao-secrets-manager.targetSecretName" -}}
{{- .Values.externalSecrets.externalSecret.target.name | default (printf "%s-secret" (include "openbao-secrets-manager.fullname" .)) }}
{{- end }}

{{/*
Harbor ExternalSecret name
*/}}
{{- define "openbao-secrets-manager.harborSecretName" -}}
{{- .Values.harbor.externalSecretName | default "harbor-registry-secret" }}
{{- end }}

{{/*
ServiceAccount name
*/}}
{{- define "openbao-secrets-manager.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "openbao-secrets-manager.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Environment detection helper
*/}}
{{- define "openbao-secrets-manager.environment" -}}
{{- if contains "prod" .Release.Namespace }}
{{- "production" }}
{{- else if contains "stg" .Release.Namespace }}
{{- "staging" }}
{{- else }}
{{- "development" }}
{{- end }}
{{- end }}

{{/*
Get remote ref key based on environment
*/}}
{{- define "openbao-secrets-manager.remoteRefKey" -}}
{{- $env := include "openbao-secrets-manager.environment" . }}
{{- if eq $env "production" }}
{{- .Values.environments.production.remoteRef.key | default "server/production" }}
{{- else if eq $env "staging" }}
{{- .Values.environments.staging.remoteRef.key | default "server/staging" }}
{{- else }}
{{- .Values.externalSecrets.externalSecret.data.remoteRef.key | default "server/development" }}
{{- end }}
{{- end }}