#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")/.."

LIB=charts/observability-sidecars
APP=charts/example-app
fail=0

check() {
  local desc="$1"
  local rc="$2"
  if [ "$rc" = "0" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc"
    fail=1
  fi
}

helm dependency update "$APP" >/dev/null
out="$(helm template "$APP")"
out_min="$(helm template "$APP" -f "$APP/values-minimal.yaml")"

# 1. default values render both sidecars
echo "$out" | grep -q "name: statsd-exporter"
check "default values render the statsd-exporter sidecar" "$?"

echo "$out" | grep -q "containerPort: 9102"
check "statsd-exporter sidecar exposes port 9102" "$?"

echo "$out" | grep -q "name: fluent-bit"
check "default values render the fluent-bit sidecar" "$?"

# the app container mounts the shared log volume whenever fluent-bit is enabled
echo "$out" | grep -A20 "name: example-app" | grep -q "name: varlog"
check "app container mounts varlog" "$?"

# 2. the fluent-bit config map is rendered with the tail input configured
echo "$out" | grep -A20 "kind: ConfigMap" | grep -q "Name         tail"
check "fluent-bit config map tails the app log volume" "$?"

# 3. the app and both sidecars get the hardened security context
[ "$(echo "$out" | grep -c "readOnlyRootFilesystem: true")" = "3" ]
check "app and both sidecars get readOnlyRootFilesystem" "$?"

echo "$out" | grep -q "runAsNonRoot: true"
check "pod security context sets runAsNonRoot" "$?"

# 4. values-minimal.yaml opts out of both sidecars and the config map
echo "$out_min" | grep -q "name: statsd-exporter"
[ "$?" = "1" ]
check "minimal values drop the prometheus sidecar" "$?"

echo "$out_min" | grep -q "kind: ConfigMap"
[ "$?" = "1" ]
check "minimal values drop the fluent-bit config map" "$?"

# 5. prometheus-only: statsd-exporter present, fluent-bit and its config map absent
out_prom="$(helm template "$APP" --set observabilitySidecars.fluentbit.enabled=false)"

echo "$out_prom" | grep -q "name: statsd-exporter"
check "prometheus-only renders the statsd-exporter sidecar" "$?"

echo "$out_prom" | grep -q "name: fluent-bit"
[ "$?" = "1" ]
check "prometheus-only drops the fluent-bit sidecar" "$?"

echo "$out_prom" | grep -q "kind: ConfigMap"
[ "$?" = "1" ]
check "prometheus-only drops the fluent-bit config map" "$?"

# 6. fluentbit-only: fluent-bit present, statsd-exporter absent
out_fb="$(helm template "$APP" --set observabilitySidecars.prometheus.enabled=false)"

echo "$out_fb" | grep -q "name: fluent-bit"
check "fluentbit-only renders the fluent-bit sidecar" "$?"

echo "$out_fb" | grep -q "name: statsd-exporter"
[ "$?" = "1" ]
check "fluentbit-only drops the statsd-exporter sidecar" "$?"

exit $fail
