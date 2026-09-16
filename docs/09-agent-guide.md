# 09 Guide for AI agents

This chapter is written for a coding agent (Claude Code, Codex, Copilot agent mode, ...) that is
asked to create, modernise or maintain a CCU addon. Humans may skip it, or read it as the
condensed checklist.

## Read first

1. This handbook, chapters [01](01-platforms.md) to [08](08-testing.md); the ten facts in the
   [README](../README.md) are the minimum. For openccu-lite also [11](11-openccu-lite.md) and
   [12](12-porting-to-openccu-lite.md); a porting job can start from
   [templates/PORTING-PROMPT.md](../templates/PORTING-PROMPT.md).
2. The repository's `AGENTS.md` (or `CLAUDE.md`) and `ROADMAP.md`; completed work usually sits in
   `roadmap-archive/`.
3. A reference implementation: [ccu-addon-mosquitto](https://github.com/homematic-community/ccu-addon-mosquitto)
   (small, one daemon, complete web UI, all mechanisms) or
   [RedMatic](https://github.com/rdmtc/RedMatic) (large runtime, Node.js, monit, progress-bar self-update).

## Working rules that proved themselves

- **Work on Linux (or WSL), never through Windows tooling**: PowerShell and Windows-side
  editors introduce UTF-8 BOMs, CRLF line endings and lost execute bits, all of which break
  busybox `sh` and tclsh silently. Write files through the Linux shell, keep `.gitattributes`
  with `* text=auto eol=lf`, and scan for `\r` and BOMs before committing.
- **One commit per significant change**, with a message that explains the why. Never push, tag
  or release without the maintainer's explicit go; releases are cut by workflows the maintainer
  triggers.
- **Roadmap discipline**: numbered tasks that are never renumbered; open tasks in `ROADMAP.md`,
  finished ones moved to `roadmap-archive/task-N.md` with what was done, what was measured and
  what was found; a "follow-ups" task collects ideas. That is how the next session (human or
  agent) picks up where you stopped.
- **Verify on the real firmwares before calling anything done.** The CCU3 firmware (Tcl 8.2,
  glibc 2.27, chroot install), OpenCCU (Tcl 8.6, live install) and openccu-lite (systemd,
  confined, no ReGa) each break things the others do not. A container e2e test is mandatory but not sufficient.
- **Keep lab details out of the repo**: addresses, passwords and session ids of test systems
  belong in a private note, never in code, docs, issues or commit messages.
- **Report faithfully**: when a test fails, say so with the output; when a step was skipped, say
  that; distinguish "verified on hardware" from "passed in the container".
- When the maintainer changes a decision mid-way (feature wishes, platform choices), record it in
  the roadmap with the date, then implement.

## Order of work for a new or modernised addon

1. Survey: what is installed today, what the old package did, what the firmware offers (this handbook).
2. Roadmap with numbered tasks; commit it first.
3. Build system that produces per-architecture packages reproducibly (containers, `patchelf`).
4. Runtime scripts (`update_script`, rc.d) with the migration from the previous release.
5. Web UI: settings page, CGIs with session checks, Tcl 8.2 compatible.
6. Self-update, update check.
7. Tests: unit, container e2e, hm-simulator if the addon talks to the CCU ([08](08-testing.md) 1b),
   then all three hardware platforms; fix what they find.
8. CI, release workflows, automatic releases.
9. Documentation: README (user facing), BUILD.md, release notes, roadmap archive.
10. Hand the release decision to the maintainer.

## Trap list

Everything on this list cost real hours in 2026:

- Tcl 8.2 on the CCU3: `dict`, `{*}`, `eq`/`ne`, `2>@1`, value-returning `regsub` and `scan` all fail ([04](04-webui.md)).
- A literal `{` inside a braced `if` condition is a Tcl syntax error, shown by lighttpd as a 500.
- lighttpd's `PATH` has no `/sbin`; `ip` and `iptables` need absolute paths.
- `update_script` must not start services when `/etc/init.d/S00InstallAddon` exists, and must
  start them on updates when it does not, from `cd /`.
- Mosquitto 2.x denies anonymous clients unless `allow_anonymous true`; a migrated 1.x config
  locks everybody out.
- `mosquitto --test-config` saves its (empty) in-memory database on exit; test on a copy with
  persistence off.
- busybox: `ln -sfT` on an existing directory symlink fails, use `-n`; `install` has no
  `--strip-program`; `[[` only in newer busybox; `sed`, `awk` and `grep` are the busybox variants.
- `/media/usbN` directories exist on the CCU3 without a stick; only `/proc/mounts` tells.
- The firmware's `update_addon` helpers in older addons are i386/armv7 ELFs that only run through
  compat loaders; a tclsh script does the same job everywhere.
- Backticks in POSIX sh eat backslashes inside `sed` and `tr` arguments; use `$(...)` there.
- A dangling monit symlink after uninstall breaks monit; test with `-L`.
- Alpine's own package of a program may drag in a dependency tree twice the size of a source build with features off.
- GitHub keeps `+` in tag and asset names but URLs need `%2B`.
- The CCU3's `/usr/local` has 96k inodes; count them for `node_modules`, and clean the chroot
  installer's leftover temp dirs.
- A password or ACL file that a Mosquitto plugin points to must exist, or the broker does not
  start, and `--test-config` does not catch it: create empty files at service start.
- Non-ASCII passwords: Tcl re-encodes strings with the CGI's locale before `exec`; keep request
  bytes as bytes (`encoding system iso8859-1`, no `encoding convertfrom`) so an umlaut reaches
  `mosquitto_passwd` as the UTF-8 an MQTT client sends.
- openccu-lite: a confined addon cannot write `/var/run/<name>.pid`, `/usr/local/etc/config`,
  or a `/tmp` file another user created first (`protected_regular`); there is no
  `/var/log/messages`; the `tclrega.so` shim answers only the session check; a foreground
  `start` blocks the unit; `X-Occulite-Session` is trusted only after `/api/auth/v1/state`
  confirmed it, and never on a CCU ([11](11-openccu-lite.md)).
- In a test container pid 1 must reap (`docker run --init`), and `ldconfig` ignores libraries
  whose names do not start with `lib` (a stub `tclrega.so` belongs into `/usr/lib`).

## An AGENTS.md to start from

[templates/AGENTS.md](../templates/AGENTS.md) is the file ccu-addon-mosquitto uses; adapt names
and layout. Keep it short: layout, conventions, caveats, where the roadmap is.
