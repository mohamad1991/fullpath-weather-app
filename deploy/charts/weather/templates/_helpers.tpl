{{- define "weather.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Common labels. Usage: include "weather.labels" (dict "ctx" $ "component" "api") */}}
{{- define "weather.labels" -}}
app.kubernetes.io/name: {{ .ctx.Chart.Name }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/version: {{ include "weather.tag" .ctx | quote }}
app.kubernetes.io/part-of: weather
app.kubernetes.io/managed-by: {{ .ctx.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .ctx.Chart.Name .ctx.Chart.Version }}
{{- end -}}

{{/* Selector labels - immutable on Deployments, so keep them minimal and stable. */}}
{{- define "weather.selectorLabels" -}}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "weather.tag" -}}
{{- required "image.tag is required (immutable git SHA, set by CI)" .Values.image.tag -}}
{{- end -}}

{{- define "weather.image" -}}
{{- printf "%s/%s:%s" .ctx.Values.image.registry .component (include "weather.tag" .ctx) -}}
{{- end -}}

{{/* Restricted Pod Security Standard - pod level. */}}
{{- define "weather.podSecurityContext" -}}
runAsNonRoot: true
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{/* Restricted Pod Security Standard - container level. */}}
{{- define "weather.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end -}}

{{/* DB connection env from the shared secret contract. */}}
{{- define "weather.dbEnv" -}}
- name: DB_HOST
  valueFrom: { secretKeyRef: { name: {{ .Values.database.secretName }}, key: host } }
- name: DB_PORT
  valueFrom: { secretKeyRef: { name: {{ .Values.database.secretName }}, key: port } }
- name: DB_NAME
  valueFrom: { secretKeyRef: { name: {{ .Values.database.secretName }}, key: dbname } }
- name: DB_USER
  valueFrom: { secretKeyRef: { name: {{ .Values.database.secretName }}, key: username } }
- name: DB_PASSWORD
  valueFrom: { secretKeyRef: { name: {{ .Values.database.secretName }}, key: password } }
- name: DB_SSLMODE
  value: {{ .Values.database.sslmode | quote }}
{{- end -}}

{{/* Zone + node spread. Usage: include "weather.topologySpread" (dict "ctx" $ "component" "api") */}}
{{- define "weather.topologySpread" -}}
{{- if .ctx.Values.topologySpread.enabled }}
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: {{ .ctx.Values.topologySpread.zoneWhenUnsatisfiable }}
    labelSelector:
      matchLabels: {{- include "weather.selectorLabels" . | nindent 8 }}
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels: {{- include "weather.selectorLabels" . | nindent 8 }}
{{- end }}
{{- end -}}

{{/* NetworkPolicy egress peers for Postgres: CIDRs (RDS) or in-cluster pods (CNPG). */}}
{{- define "weather.dbEgressPeers" -}}
{{- if .Values.networkPolicy.databaseCIDRs }}
{{- range .Values.networkPolicy.databaseCIDRs }}
- ipBlock: { cidr: {{ . }} }
{{- end }}
{{- else }}
- namespaceSelector: {{- toYaml .Values.networkPolicy.databasePodSelector.namespaceSelector | nindent 4 }}
  podSelector:
    matchLabels: {{- toYaml .Values.networkPolicy.databasePodSelector.podSelector | nindent 6 }}
{{- end }}
{{- end }}
