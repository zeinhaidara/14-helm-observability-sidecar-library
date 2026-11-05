{{/*
Pod-level security context: non-root, fixed uid/gid, default seccomp profile.
*/}}
{{- define "observability-sidecars.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: {{ .Values.observabilitySidecars.securityContext.runAsUser | default 1000 }}
fsGroup: {{ .Values.observabilitySidecars.securityContext.fsGroup | default 1000 }}
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{/*
Container-level security context: no privilege escalation, read-only root fs,
all capabilities dropped. Applies to the app container and both sidecars.
*/}}
{{- define "observability-sidecars.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
runAsNonRoot: true
capabilities:
  drop:
    - ALL
{{- end -}}

{{/*
Prometheus metrics-exporter sidecar. Exposes a /metrics port for a
Prometheus server to scrape; does not run Prometheus itself.
*/}}
{{- define "observability-sidecars.prometheusSidecar" -}}
{{- $cfg := .Values.observabilitySidecars.prometheus }}
- name: prometheus-exporter
  image: "{{ $cfg.image.repository }}:{{ $cfg.image.tag }}"
  ports:
    - name: metrics
      containerPort: {{ $cfg.port }}
  securityContext:
    {{- include "observability-sidecars.containerSecurityContext" . | nindent 4 }}
  resources:
    {{- toYaml $cfg.resources | nindent 4 }}
{{- end -}}

{{/*
Fluent Bit sidecar. Tails the app's log volume and forwards to stdout.
*/}}
{{- define "observability-sidecars.fluentbitSidecar" -}}
{{- $cfg := .Values.observabilitySidecars.fluentbit }}
- name: fluent-bit
  image: "{{ $cfg.image.repository }}:{{ $cfg.image.tag }}"
  securityContext:
    {{- include "observability-sidecars.containerSecurityContext" . | nindent 4 }}
  resources:
    {{- toYaml $cfg.resources | nindent 4 }}
  volumeMounts:
    - name: varlog
      mountPath: /var/log/app
      readOnly: true
    - name: fluentbit-config
      mountPath: /fluent-bit/etc
      readOnly: true
{{- end -}}

{{/*
Every enabled sidecar container, ready to append under
spec.template.spec.containers in the consuming chart.
*/}}
{{- define "observability-sidecars.sidecars" -}}
{{- if .Values.observabilitySidecars.prometheus.enabled }}
{{ include "observability-sidecars.prometheusSidecar" . }}
{{- end }}
{{- if .Values.observabilitySidecars.fluentbit.enabled }}
{{ include "observability-sidecars.fluentbitSidecar" . }}
{{- end }}
{{- end -}}

{{/*
Volumes the sidecars need. Only Fluent Bit requires any (a shared log dir
and its config); the Prometheus exporter needs none.
*/}}
{{- define "observability-sidecars.volumes" -}}
{{- if .Values.observabilitySidecars.fluentbit.enabled }}
- name: varlog
  emptyDir: {}
- name: fluentbit-config
  configMap:
    name: {{ .Values.observabilitySidecars.fluentbit.configMapName }}
{{- end }}
{{- end -}}

{{/*
Minimal Fluent Bit config: tail the shared log volume, ship to stdout.
A consumer chart renders this into its own ConfigMap.
*/}}
{{- define "observability-sidecars.fluentbitConfig" -}}
[SERVICE]
    Flush        5
    Daemon       Off
    Log_Level    info

[INPUT]
    Name         tail
    Path         /var/log/app/*.log
    Tag          app.*

[OUTPUT]
    Name         stdout
    Match        *
{{- end -}}
