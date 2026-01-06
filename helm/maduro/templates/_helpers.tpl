{{/*
Create a default fully qualified app name.
*/}}
{{- define "maduro.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- if not .Values.nameOverride }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "maduro.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "maduro.selectorLabels" . }}
{{- if .Chart.Version }}
app.kubernetes.io/version: {{ .Chart.Version | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: maduro
{{- with .Values.labels }}
{{ toYaml . | nindent 0 }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "maduro.selectorLabels" -}}
app.kubernetes.io/name: {{ default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*Default model name*/}}
{{- define "maduro.defaultModelConfigName" -}}
default-model-config
{{- end }}

{{/*
Expand the namespace of the release.
Allows overriding it for multi-namespace deployments in combined charts.
*/}}
{{- define "maduro.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Watch namespaces - transforms list of namespaces cached by the controller into comma-separated string
Removes duplicates
*/}}
{{- define "maduro.watchNamespaces" -}}
{{- $nsSet := dict }}
{{- .Values.controller.watchNamespaces | default list | uniq | join "," }}
{{- end -}}

{{/*
UI selector labels
*/}}
{{- define "maduro.ui.selectorLabels" -}}
{{ include "maduro.selectorLabels" . }}
app.kubernetes.io/component: ui
{{- end }}

{{/*
Controller selector labels
*/}}
{{- define "maduro.controller.selectorLabels" -}}
{{ include "maduro.selectorLabels" . }}
app.kubernetes.io/component: controller
{{- end }}

{{/*
Engine selector labels
*/}}
{{- define "maduro.engine.selectorLabels" -}}
{{ include "maduro.selectorLabels" . }}
app.kubernetes.io/component: engine
{{- end }}

{{/*
Controller labels
*/}}
{{- define "maduro.controller.labels" -}}
{{ include "maduro.labels" . }}
app.kubernetes.io/component: controller
{{- end }}

{{/*
UI labels
*/}}
{{- define "maduro.ui.labels" -}}
{{ include "maduro.labels" . }}
app.kubernetes.io/component: ui
{{- end }}

{{/*
Engine labels
*/}}
{{- define "maduro.engine.labels" -}}
{{ include "maduro.labels" . }}
app.kubernetes.io/component: engine
{{- end }}

{{/*
Check if leader election should be enabled (more than 1 replica)
*/}}
{{- define "maduro.leaderElectionEnabled" -}}
{{- gt (.Values.controller.replicas | int) 1 -}}
{{- end -}}

{{/*
Validate controller configuration
*/}}
{{- define "maduro.validateController" -}}
{{- if and (gt (.Values.controller.replicas | int) 1) (eq .Values.database.type "sqlite") -}}
{{- fail "ERROR: controller.replicas cannot be greater than 1 when database.type is 'sqlite' as the SQLite database is local to the pod. Please either set controller.replicas to 1 or change database.type to 'postgres'." }}
{{- end -}}
{{- end -}}

{{/*
A2A Base URL - computes the default URL based on the controller service name if not explicitly set
*/}}
{{- define "maduro.a2aBaseUrl" -}}
{{- if .Values.controller.a2aBaseUrl -}}
{{- .Values.controller.a2aBaseUrl -}}
{{- else -}}
{{- printf "http://%s-controller.%s.svc.cluster.local:%d" (include "maduro.fullname" .) (include "maduro.namespace" .) (.Values.controller.service.ports.port | int) -}}
{{- end -}}
{{- end -}}
