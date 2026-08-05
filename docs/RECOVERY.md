# Recovery

## Diagnose

```bash
desktop-status
desktop-doctor
desktop-doctor --json
```

`desktop-doctor` reports each prerequisite with PASS, WARN, or FAIL and an
actionable message. The JSON form is machine-readable and suitable for issue
reports.

## Repair a partial installation

- Re-run `desktop-install`. It is idempotent: an existing environment is not
  reinstalled and a failed stage is reported without claiming success.
- If the desktop is running but unhealthy, run `desktop-stop` and then
  `desktop-start`.

## Stop only the toolkit

```bash
desktop-stop
```

Shutdown is ownership-based. Processes not recorded by the toolkit, including
an external PulseAudio server, are left running.

## Reset

```bash
desktop-reset --yes
```

`desktop-reset --yes` stops owned processes, creates a timestamped backup
under `$PREFIX/var/lib/termux-linux-desktop/backups/`, and removes toolkit
state. The printed backup path contains the install manifest and logs.

Reset never removes the user's Termux home, unrelated packages, or other
PRoot environments.

## Rollback

The install manifest and the resolved rootfs manifest hash are recorded in
`$PREFIX/var/lib/termux-linux-desktop/instance.env`. The environment can be
recreated from the pinned image when a repair is required.
