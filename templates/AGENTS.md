# Agent instructions for ADDON-NAME

ADDON-NAME packages PROGRAM as an addon for the Homematic CCU3 / OpenCCU (formerly
RaspberryMatic) / openccu-lite smart-home central. The build output is one `.tar.gz` addon package per
architecture (armv7l, aarch64, x86_64), installed on the CCU under `/usr/local/addons/ADDON`.

**Read `ROADMAP.md` before making changes.** Completed tasks live in `roadmap-archive/` (one
file per task, numbers are never reused). The general CCU addon handbook is
https://github.com/homematic-community/ccu-addon-howto.

## Layout

- `build.sh` / `build_addon.sh <arch>`: builds the binaries in a container, makes them
  self-contained with `patchelf`, copies `addon_files/`, writes `versions`, packs `dist/`.
- `addon_files/update_script`: what the CCU runs at install/update time (fresh install exits 10
  = reboot, update exits 0 and starts the service).
- `addon_files/ADDON/`: the tree that ends up on the CCU: `bin/ADDON-service` (rc.d script),
  `bin/update_addon` (WebUI button), `etc/*.default` (first-install defaults), `www/` (settings
  page: tclsh CGIs + HTML/CSS/JS, no frameworks), `lib/` (Tcl helpers).
- `test/e2e.sh`: container end-to-end test of the x86_64 package (needs docker);
  `test/*.test.js`: unit tests.
- CI: `.github/workflows/ci.yml`, `build.yml` (manual release build), `auto-release.yml`.

## Conventions and caveats

- **Always use a Linux shell (WSL on Windows), never PowerShell**: CRLF, BOMs and lost execute
  bits break busybox `sh` and tclsh silently.
- One git commit per significant change. **Never push, tag or release** without the
  maintainer's go; releases are cut by the GitHub workflows.
- The addon scripts run on busybox `ash` on the CCU: POSIX `sh` only. The CGIs run on
  **Tcl 8.2** on the original CCU3 firmware: no `dict`, `{*}`, `eq`/`ne`, `2>@1`, value-returning
  `regsub`/`scan`.
- No `LD_LIBRARY_PATH` anywhere: bundled binaries use their patched RPATH.
- Every CGI that reads or changes configuration checks the CCU session (`lib/session.tcl`).
- Keep the package small; no web frameworks in `www/`.
- openccu-lite (no ReGa, systemd, the addon confined as `addon-ADDON`): detect it with a `LITE=`
  line in `/VERSION` or an executable `/usr/bin/occulited` (never `VARIANT=lite`), write only to
  the addon's own paths, keep the pid file in
  `/run/addon-ADDON/`, do not assume `/var/log/messages`, hide the self-updater, and use no ReGa
  call except the session check (handbook chapters 11 and 12).
- Test on all firmwares before calling a change done; the container test is not enough.
- Lab test systems, their addresses and credentials stay out of the repo, the wiki and issues.
