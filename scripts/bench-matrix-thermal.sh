#!/usr/bin/env bash
# bench-matrix-thermal.sh v2 — adds thermal gating + covariate logging to the
# chained benchmark methodology. Wait for SoC cooldown before each trial and
# record frequency/thermal covariates beside every row so A/B deltas are
# attributable (single-run deltas under ~6 s are thermal noise otherwise).
set -Eeuo pipefail

MEASURE=${MEASURE:-90}
COOL_TRIAL=${COOL_TRIAL:-120}      # seconds of idle before each trial
TEMP_ZONE=${TEMP_ZONE:-/sys/class/thermal/thermal_zone0}
TEMP_MAX=${TEMP_MAX:-40000}        # gate: wait while zone temp (milli-C) above this
TSV=${TSV:-/root/bench-thermal.tsv}

configs=("$@")
((${#configs[@]})) || configs=(base)

echo "timestamp	tag	kind	secs	frames	freq_max	temp_start	temp_end" > "$TSV"

read_temp() { cat "$TEMP_ZONE/temp" 2>/dev/null || echo 0; }
read_freq_max() {
  local m=0 f c
  for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
    f=$(cat "$c" 2>/dev/null || echo 0); (( f > m )) && m=$f
  done
  echo $m
}

for tag in "${configs[@]}"; do
  # thermal gate
  while :; do
    t=$(read_temp)
    (( t <= TEMP_MAX )) && break
    echo "[thermal] waiting: ${t}mC > ${TEMP_MAX}mC" >&2
    sleep 20
  done
  t_start=$(read_temp)

  : > /tmp/bench-run.log
  local_rc=0
  timeout "$((MEASURE + 5))" bash -c "$RUNNER" > /tmp/bench-run.log 2>&1 || local_rc=$?
  frames=$(grep -oE 'FramesPresented=[0-9]+' /tmp/bench-run.log | tail -1 | cut -d= -f2 || echo 0)
  printf '%s	%s	meas	%s	%s	%s	%s	%s
' \
    "$(date +%FT%T)" "$tag" "$MEASURE" "${frames:-0}" \
    "$(read_freq_max)" "$t_start" "$(read_temp)" >> "$TSV"
done
echo "[thermal] results in $TSV"
