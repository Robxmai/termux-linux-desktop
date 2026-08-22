# GPU/Wine Benchmarking on Termux proot Desktops

Methodology validated on Xiaomi Pad 6 Pro S (SD 8+ Gen 1), Turnip 24.1.0 + DXVK 2.6.1,
Box64 0.4.5 Dynarec, Wine 11.11 amd64-wow64, custom termux-x11 @144fps.

## The three failure modes that produce silent zero-frame runs

### 1. X11 socket not bound into the container
`proot-distro login` does **not** expose the termux-x11 socket by default.
Every Wine/X11 client dies before creating a window (silently under `WINEDEBUG=-all`).

Fix - always launch benchmarks with:
```bash
proot-distro login tld-ubuntu \
  --bind /data/data/com.termux/files/usr/tmp/.X11-unix:/tmp/.X11-unix \
  -- bash your-bench.sh
```
Verify first: `xdpyinfo -display :0` must print "name of display: :0".

### 2. Wineserver lifetime vs stale sockets
A wineserver lives only briefly after its last client disconnects, but its
socket directory `/tmp/.wine-0` survives. A new client that starts after the
server died but before anyone cleans the socket fails instantly with
`wine: a wine server seems to be running, but I cannot connect to it`
- and produces zero frames with an almost-empty log.

Consequences:
* **Back-to-back runs work** (they attach to the living server).
* Runs spaced more than a few seconds apart fail unless you repair first:
  ```bash
  pkill -f wineserver          # SAFETY: wine-only pattern
  rm -rf /tmp/.wine-0
  ```
* After any repair, the next run spends its window **booting the prefix**
  (wineserver spawn + explorer.exe /desktop). It will render few or no frames.
  Discard that run; the one after it is clean.

### 3. First-run JIT/prefix cost
Even a healthy cold run pays prefix boot + Box64 dynarec warmup. Always run a
sacrificial boot pass, or chain measurements so only the first pays the cost.

## Valid measurement protocol (what bench-matrix.sh implements)

1. Launch inside container **with the X11 bind**.
2. Per configuration: chained attempts of 90 s each, **no gap** between them.
   Attempt 1 absorbs boot; attempt 2 renders on a warm server.
3. If an attempt yields 0 frames: repair (kill wineserver, purge /tmp/.wine-0,
   sleep 3) and retry - up to 3 attempts.
4. 45 s thermal cooldown between configurations (the following config's first
   attempt re-boots the prefix by design).
5. Compare configurations on **frames in equal windows** from non-boot runs;
   report max-temp alongside (thermal_zone max, millidegrees).

## Known exe behaviour
The D3D9 smoke exe (`winlator-d3d9-smoke-x86.exe`) reports cumulative
`FramesProgress=N`. Observed ceiling ~1680-1710 frames per long window
(~19 fps sustained at 90 s windows); short 60 s windows have shown ~27 fps.
When every config saturates the same frame count, switch to shorter windows
or a heavier scene to keep discrimination.

## Reproduce
```bash
# from Termux:
proot-distro login tld-ubuntu --bind /data/data/com.termux/files/usr/tmp/.X11-unix:/tmp/.X11-unix -- bash /root/bench-matrix.sh
# results: /root/bench-matrix.tsv (TSV: timestamp tag kind run secs frames fps freq_mhz maxtemp)
```
## Results: Box64 dynarec flag matrix (2026-08-22)

Workload: D3D9 smoke exe via DXVK 2.6.1 + Turnip 24.1.0, chained 90 s windows,
warm (second) measurement per config. Drift control `base2` reproduced `base`
exactly (1680 frames / 18.7 fps), so single-run deltas are trustworthy.

| config | flags over defaults | warm fps | delta |
|--------|--------------------|---------:|------:|
| base   | BIGBLOCK=1 SAFEFLAGS=2 WEAKBAR=1 CALLRET=1 | 18.7 | — |
| dc     | + BOX64_DYNACACHE=1 | 19.3 | +3.6% |
| xdg    | + XDG_RUNTIME_DIR set | 19.0 | +1.8% |
| wb2    | WEAKBARRIER=2 | 19.0 | +1.8% |
| sf0    | SAFEFLAGS=0 | 18.7 | ±0% |
| fwd1024| FORWARD=1024 | 18.7 | ±0% |
| pin    | taskset 4-7 (A7xx only) | 18.3 | −2.1% |
| bb3    | BIGBLOCK=3 | 18.0 | −3.6% |
| bb2    | BIGBLOCK=2 | 17.7 | −5.4% |
| cr2    | CALLRET=2 | 17.3 | −7.1% |
| combo  | BB3+SF0+CR2+WB2+FWD1024 | ≤13.7, 3/5 runs dead | unstable |

Conclusions:
1. **The DXVK path is GPU/presentation-bound.** Box64 flag tuning moves this
   workload by at most a few percent; the launcher defaults are already right.
2. **Do not stack aggressive dynarec flags** on wow64 Wine (combo): it both
   slows rendering and destabilises window creation.
3. CALLRET=2 and BIGBLOCK>=2 are mild regressions for D3D9/DXVK workloads.
4. Explicit `BOX64_DYNACACHE=1` is safe and slightly positive; keep it enabled.
5. wined3d (CPU-bound translation) could not be tested - the container has no
   GL driver stack (Turnip is Vulkan-only). Future work: zink-on-turnip or
   llvmpipe to build a translation-heavy benchmark.
