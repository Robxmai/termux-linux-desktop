#!/usr/bin/env bash
# bench-matrix.sh - Box64 dynarec A/B matrix on D3D9 smoke (XDG fixed, dynacache per config)
set -u
EXE=/root/wow-tests/d3d9-boundary-dxvk-20260812-2/winlator-d3d9-smoke-x86.exe
PREFIX=/root/wow-tests/d3d9-boundary-dxvk-20260812-2/prefix
BOX64_BIN=/usr/local/bin/box64
WINE_BIN=/opt/wine-runtime/wine-11.11-amd64-wow64/bin/wine
RESULTS=/root/bench-matrix.tsv
MEASURE=90; COOL_RUN=30; COOL_CFG=45

maxtemp() { local m=0 t z; for z in /sys/class/thermal/thermal_zone*/temp; do t=$(cat $z 2>/dev/null) || continue; [ -z "$t" ] && continue; [ "$t" -gt "$m" ] 2>/dev/null && m=$t; done; echo $m; }

kill_wineserver() {
  # SAFETY: only targets wine wineserver processes; never tailscale/x11 patterns
  local i=0
  while [ $i -lt 3 ]; do
    WINESERVER=$WINE_BIN-wineboot 2>/dev/null; true
    pids=$(pgrep -f 'wineserver' | tr '\n' ' ')
    [ -z "$pids" ] && break
    for p in $pids; do kill $p 2>/dev/null; done
    sleep 3
    i=$((i+1))
  done
}

pre_clean_unused() {
  # SAFETY: only wine processes/socket dirs; never tailscale/x11 patterns
  local pids=$(pgrep -f wineserver | tr '\n' ' ')
  if [ -n "$pids" ]; then for p in $pids; do kill $p 2>/dev/null; done; sleep 3; fi
  rm -rf /tmp/.wine-0
  sleep 1
}
run_one() { # tag runner extra seconds iswarm
  local tag="$1" runner="$2" extra="$3" secs="$4" warm="$5"
  local cache=/root/.cache/bdc/$tag; mkdir -p "$cache"
  rm -f /tmp/bench-run.log
  env DISPLAY=:0 WINEPREFIX="$PREFIX" WINEDLLOVERRIDES='d3d9=n,dxgi=n' MESA_VK_WSI_USE_HWBUF=1 MESA_VK_WSI_PRESENT_MODE=mailbox MESA_SHADER_CACHE_DISABLE=false MESA_SHADER_CACHE_DIR=/root/.cache/mesa_shader_cache TU_DEBUG=sysmem,noconform,noubwc BOX64_DYNAREC=1 BOX64_DYNAREC_BIGBLOCK=1 BOX64_DYNAREC_SAFEFLAGS=2 BOX64_DYNAREC_WEAKBARRIER=1 BOX64_DYNAREC_CALLRET=1 WINEESYNC=0 WINEFSYNC=0 WINEDEBUG=-all BOX64_LOG=1 $extra $runner timeout "${secs}s" "$BOX64_BIN" "$WINE_BIN" "$EXE" > /tmp/bench-run.log 2>&1
  local rc=$?
  local frames=$(grep -o 'FramesProgress=[0-9]*' /tmp/bench-run.log | tail -1 | cut -d= -f2)
  local fps=$(awk -v f="${frames:-0}" -v s="$secs" 'BEGIN{ if(s>0) printf "%.1f", f/s; else print 0 }')
  local freq=$(cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq 2>/dev/null || echo 0)
  local temp=$(maxtemp)
  local kind=$([ "$warm" = "1" ] && echo warm || echo meas)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%FT%T)" "$tag" "$kind" "$run_no" "$secs" "${frames:-0}" "$fps" "$((freq/1000))" "$temp" | tee -a "$RESULTS"
  return $rc
}

printf 'timestamp\ttag\tkind\trun\tsecs\tframes\tfps\tfreq_mhz\tmaxtemp\n' > "$RESULTS"

CONFIGS=(
  'base||'
  'xdg||XDG_RUNTIME_DIR=/tmp/runtime-0'
  'dc||BOX64_DYNACACHE=1'
  'bb2||BOX64_DYNAREC_BIGBLOCK=2'
  'bb3||BOX64_DYNAREC_BIGBLOCK=3'
  'wb2||BOX64_DYNAREC_WEAKBARRIER=2'
  'sf0||BOX64_DYNAREC_SAFEFLAGS=0'
  'cr2||BOX64_DYNAREC_CALLRET=2'
  'fwd1024||BOX64_DYNAREC_FORWARD=1024'
  'pin|taskset -c 4-7|'
  'combo||BOX64_DYNAREC_BIGBLOCK=3 BOX64_DYNAREC_SAFEFLAGS=0 BOX64_DYNAREC_CALLRET=2 BOX64_DYNAREC_WEAKBARRIER=2 BOX64_DYNAREC_FORWARD=1024 BOX64_DYNAREC_STRONGMEM=0'
  'base2||'
)

echo "== matrix start $(date -Is) =="

for cfg in "${CONFIGS[@]}"; do
  IFS='|' read -r tag runner extra <<< "$cfg"
  if awk -F'\t' -v t="$tag" '$2==t && $3=="meas" && $6+0>0 {found=1} END{exit !found}' "$RESULTS" 2>/dev/null; then
    echo "--- [$tag] already complete, skipping ---"
    continue
  fi
  echo "--- [$tag] starting ---"
  sleep $COOL_RUN
  for r in 1 2; do
    echo "--- [$tag] measure $r ---"
    ok=0
    for attempt in 1 2 3; do
      [ "$attempt" -gt 1 ] && {
        pids=$(pgrep -f wineserver | tr '\n' ' ')
        [ -n "$pids" ] && { for p in $pids; do kill $p 2>/dev/null; done; }
        rm -rf /tmp/.wine-0
        sleep 3
      }
      run_no=$r; run_one "$tag" "$runner" "$extra" $MEASURE 0
      last_frames=$(tail -1 "$RESULTS" | cut -f6)
      echo "    attempt $attempt frames=$last_frames"
      if [ "$last_frames" != "0" ]; then ok=1; break; fi
    done
    [ "$ok" = "1" ] || echo "    WARNING: $tag r$r incomplete"
  done
  echo "--- [$tag] done; cooling ${COOL_CFG}s ---"
  sleep $COOL_CFG
done
echo "== matrix complete $(date -Is) =="
