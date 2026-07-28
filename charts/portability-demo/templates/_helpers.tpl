{{- define "portability-demo.name" -}}
portability-demo
{{- end }}

{{- define "portability-demo.labels" -}}
app.kubernetes.io/name: {{ include "portability-demo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Values.application.version | quote }}
demo.portability/cluster: {{ .Values.cluster.name | quote }}
{{- end }}
