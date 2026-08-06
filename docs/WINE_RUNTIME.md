# Wine Runtime for ARM64 (wow64 mode)

The toolkit's GPU/Wine runtime needs an ARM64-native Wine build that can run
x86_64 Windows applications. Wine supports this on aarch64 Linux hosts via the
built-in WoW64 mode (`--enable-archs=x86_64`): the Wine host process is native
ARM64 and the Windows process is x86_64, translated by Box64.

## Build the runtime

Run `scripts/build-wine-arm64.sh` inside the PRoot guest (or any Ubuntu 24.04
ARM64 environment with ~8 GB free):

```bash
apt-get install -y build-essential flex bison gettext gawk file
bash build-wine-arm64.sh /opt/wine-src
```

The script downloads the pinned Wine 11.11 source, configures it with
`--enable-archs=x86_64`, builds, and prints the path to the runtime tree.

## Pack the runtime

```bash
tar czf wine-11.11-amd64-wow64.tar.gz \
  -C "$(dirname /opt/wine-src/build64)" \
  "$(basename /opt/wine-src/build64)"
```

## Install with the toolkit

```bash
TLD_WINE_RUNTIME_TARBALL=/path/to/wine-11.11-amd64-wow64.tar.gz desktop-install
```

The runtime lands at `/opt/wine-runtime/wine-11.11-amd64-wow64` inside the
guest and is referenced by the game launcher
(`/usr/local/bin/wow-launcher`, `WINE_BIN` default).

## Pinned versions

| Component | Pin | Reason |
|---|---|---|
| Wine | 11.11 (wow64) | validated with DXVK 2.6.1 on this stack |
| Box64 | current master, pinned commit `ba373ab` (source build) | the 0.4.x X11 presentation regression is fixed upstream in master; v0.3.7 rendered clean but dropped the WoW realm session; v0.3.5 crashed on this stack |
| Mesa Turnip | 24.1.0 | turnip 25.0.0+ Vulkan X11 WSI rewrite shows presentation corruption |
| DXVK | 2.6.1 | official release, validated with the above |

See `docs/SUPPORT.md` for the full acceptance record and diagnostics rules.
