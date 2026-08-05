# Contributing

Contributions should keep this toolkit focused, reproducible, and usable on
no-root ARM64 Android devices.

## Focused Changes

- Keep each change limited to one clear purpose.
- Explain the user-visible effect and the devices or environments affected.
- Do not add proprietary software, personal data, generated artifacts, or
  unrelated refactors.
- Keep scripts and documentation portable across supported Termux and PRoot
  environments.
- Keep the standard Termux core utilities, including `flock`, available; the
  process ownership lock requires `flock`.

## Checks Before Submission

- Run ShellCheck against every changed shell script.
- Run the applicable Bats suite, including all relevant regression cases.
- Run the repository's static checks and `git diff --check`.
- Confirm that no generated logs, rootfs archives, game data, CI artifacts, or
  dependency caches are included.
- Remove account sign-in material and internal network details from diagnostic
  output.

Run these checks before submission:

```sh
git ls-files 'bin/*' 'lib/*' | grep -E '\.sh$' | xargs -r shellcheck
git ls-files 'tests/*.bats' | xargs -r bats
test ! -f tests/test_scripts.sh || bash tests/test_scripts.sh
git ls-files 'bin/*' 'lib/*' 'tests/*' | xargs -r shfmt -d
git diff --check
```

## Runtime Changes

Runtime changes require evidence from a clean device or a fresh environment.
Record the exact setup and result without including sensitive diagnostic data.
At minimum, report:

- Device manufacturer, model, chipset, and available memory.
- Android release, ARM64 ABI, and Termux source and version.
- PRoot distribution and package versions.
- Termux:X11, XFCE, and any optional compatibility components used.
- The clean-device starting state, exact commands, expected result, actual
  result, and any reproducible failure output.

## Supported-Hardware Details

Every runtime report must identify the hardware and software combination that
was tested. Do not describe a device as supported based only on a different
chipset, Android release, display configuration, or input method. Clearly
separate confirmed results from untested combinations.

## Pull Requests

Describe the change, checks run, runtime evidence when applicable, and known
limitations. Link related issue tracker discussions without embedding private
repository details. Review [SECURITY.md](SECURITY.md) before attaching logs or
other diagnostic material.
