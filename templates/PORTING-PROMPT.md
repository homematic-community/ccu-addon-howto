# Porting prompt: make a CCU addon fully openccu-lite compatible

*For addon maintainers. Open your coding agent (Claude Code, Codex, Copilot agent mode, …) in
your addon's repository and paste everything below the line. Replace `<ADDON>` and `<ID>`
(the name of the rc.d script). Written for openccu-lite `1.0.0-dev.28` (September 2026); check
[chapter 11](../docs/11-openccu-lite.md) for changes before you use it.*

---

You are porting the Homematic CCU addon **<ADDON>** (rc.d id `<ID>`, this repository) so that it
runs fully on **openccu-lite**, while it keeps working unchanged on the original CCU3 firmware
and on OpenCCU.

openccu-lite is a CCU firmware built from OpenCCU without ReGaHSS. It uses systemd, and addons
are managed by a service called `occulited`. Addons run confined as their own user by default.

## Read first

Read these in full before changing anything:

1. The CCU addon handbook, https://github.com/homematic-community/ccu-addon-howto: the README
   and chapters 01–08. They describe how CCU addons work. (Clone it, or fetch the raw files.)
2. [docs/11-openccu-lite.md](https://github.com/homematic-community/ccu-addon-howto/blob/master/docs/11-openccu-lite.md): openccu-lite as an addon platform.
3. [docs/12-porting-to-openccu-lite.md](https://github.com/homematic-community/ccu-addon-howto/blob/master/docs/12-porting-to-openccu-lite.md): the porting checklist. **Follow it step by step.**
4. [templates/lib/session.tcl](https://github.com/homematic-community/ccu-addon-howto/blob/master/templates/lib/session.tcl): the session check with the openccu-lite header path.

The openccu-lite project itself is https://github.com/hobbyquaker/openccu-lite; its system
service is https://github.com/hobbyquaker/occulited. The normative references, read the ones
that apply:

- the manifest: https://github.com/hobbyquaker/occulited/blob/master/docs/manifest-format.md and
  its schema `docs/manifest.schema.json` beside it;
- the catalogue: https://github.com/hobbyquaker/occulited/blob/master/docs/catalog-format.md;
- the metadata API: https://github.com/hobbyquaker/occulited/blob/master/docs/meta-api.md;
- the system and auth APIs: https://github.com/hobbyquaker/occulited/blob/master/docs/system-api.md;
- the ReGa mapping, and what has no replacement:
  https://github.com/hobbyquaker/openccu-lite/blob/main/docs/porting-from-rega.md.

Then read this repository: its `AGENTS.md`/`CLAUDE.md` if any, the build scripts,
`update_script`, the rc.d script, the CGIs and the daemon's start code.

## Invariants: do not break these

1. **One package for all firmwares.** Every CCU3 and OpenCCU code path stays. Behaviour on a
   CCU is identical before and after your change.
2. **Detect at runtime, never at build time.**
   - Firmware, one rule in every language: **a `LITE=` line in `/VERSION`, or an executable
     `/usr/bin/occulited`** — `grep -q '^LITE=' /VERSION 2>/dev/null || [ -x /usr/bin/occulited ]`
     in shell, `regexp -line {^LITE=}` or `file exists` in Tcl, `/^LITE=/m` or `fs.existsSync` in
     JS. `VARIANT=lite` is also in `/VERSION` but is not the marker to test.
   - Metadata API: `GET http://127.0.0.1/api/meta/v1/version` answers `{"api":"meta",…}`.
   - No new mandatory configuration.
3. **No user configuration may break.** ReGa-only options stay accepted. On openccu-lite they
   log one line and do nothing.
4. **Only the session check may use ReGa.** The system's `tclrega.so` shim answers
   `system.GetSessionVarStr` and nothing else. Do not add other ReGa calls.
5. **Never trust `X-Occulite-Session` without asking the system.** Use it only when the detection
   rule says openccu-lite, and accept it only after `GET http://127.0.0.1/api/auth/v1/state` with
   `Authorization: Bearer <value>` answers `authenticated: true` with the same `sid`.
6. **No systemd unit files, no `iptables`, no writes to the read-only root, no `mount`, no new
   root requirements.** What the daemon needs is declared in the `runtime` block of the
   addon's manifest `openccu-lite.json`. Device descriptions go to `/firmware/rftypes`, which is
   writable on openccu-lite without a remount.
7. **Tcl stays 8.2-compatible** and shell stays POSIX `sh` (busybox ash), because the CCU3 still
   runs this code.

## What to do

Work through chapter 12 in order. Make one commit per step, and explain why in each message.

1. **Triage.** Run the grep from chapter 12, step 0, and classify the addon:
   - **ABI-only**;
   - **metadata reader/writer**;
   - **ReGa-bound**. If ReGa-bound, stop and report: it cannot be ported, only documented.
2. **Packaging.**
   - Build one asset per `uname -m` (`aarch64`, `x86_64`, plus `armv7l` for the stock CCU3),
     with the architecture in the file name and a `.sha256` sibling.
   - The package version must equal the release tag.
   - Put `openccu-lite.json` at the root of the tarball, beside `update_script` (step 12). It
     replaces the `openccu-lite.ok` marker.
   - Refuse a wrong architecture with exit 13.
3. **`update_script`.**
   - Create every directory the daemon writes to.
   - Keep the CCU start logic.
   - On openccu-lite, optionally start through `systemctl start addon-<ID>.service`.
   - Write the right `Config-Url` (or name the settings page in `ui.settings_url`).
   - Don't touch the firewall.
   - Ship a lighttpd fragment as `etc/lighttpd.conf` in the addon's tree; on openccu-lite do not
     link or copy it into `/usr/local/etc/config/lighttpd/`, the system writes a validated copy.
4. **rc.d script.**
   - `start` backgrounds the daemon and returns.
   - The pid file goes to `/run/addon-<ID>/` (or the addon directory) when not root.
   - Skip boot-time network waits and `/proc/*/oom_score_adj` writes on openccu-lite.
   - `uninstall` removes only what the addon created, and tolerates a failed removal: on
     openccu-lite it runs as the addon user when the addon is confined, and the system removes
     the rc.d entry, the www link and the emptied directories afterwards.
   - `info` and `init` of a confined addon run as the addon user too (`init` inside the unit,
     right before `start`): neither may need root. Answer `init` with nothing if unused.
5. **Confinement.**
   - List every path the daemon, the CGIs and the helper scripts write or read outside the
     addon directory, every port, every device and every root-only operation.
   - Fix each one in code, or put it in the manifest's `runtime` block (`data_dirs`, `paths`,
     `groups`, `capabilities`, `ports` + `port_info`, `needs`, `note`; `daemon: true` when
     `start` leaves a process running; `start: "early"` only when the addon retries within
     seconds and logs no errors while it waits).
   - Aim for no `root`.
   - Use no shared `/tmp` files; use `/run/addon-<ID>/`.
6. **Web UI.**
   - Switch the CGIs to `request_session_ok` from the template, and add a `role` check for
     admin-only pages.
   - If the addon has its own HTTP server, give it the same header check.
   - Pages must work without `?sid=` when the header is there, and still with `?sid=` on a CCU.
   - No streaming CGIs.
   - CGIs and the addon's server change state only on a POST (or PUT/DELETE), never on a GET
     with a query; the POST reads its fields from the body. openccu-lite refuses cross-site
     requests that carry its cookie, and a page on the addon's own port counts as another site.
     Browser calls to the system's `/api/` that change state send `X-Occulite-Request: 1`.
   - Keep the frontend proxy under `/addons/`, proxying to this system only; no `include`,
     `cgi.*` or `$SERVER["socket"]` in the fragment. Add `nav.d/<ID>.json` if needed.
   - Follow `?theme=`/`?lang=` if feasible.
7. **Self-updater.**
   - On openccu-lite, hide the update button, notice and modal, and show one line that points
     to the system's Addons page (`/addons`).
   - The updater's start command answers 403 with that text.
   - A release that still carries its updater sets `ui.own_updater: true`.
   - `update_check.cgi` may stay.
8. **Logs.**
   - Log to stdout, stderr or `logger`, not to growing files.
   - The log view keeps `/var/log/messages` on a CCU. On openccu-lite, it links
     `/system/log?unit=addon-<ID>` or uses the log API with a `logs:read` token.
   - No code may assume `/var/log/messages` exists.
9. **Metadata** (only for reader/writer addons). Add a second provider next to the ReGa one, as
   described in chapter 12, step 8:
   - version probe, `/snapshot`, `/events/sse?since=`;
   - local token for reads, `meta:write` for writes; off the system a token option or client
     pairing;
   - the state store (`GET /api/rpc/v1/state`) instead of a `getParamset` sweep at start, when
     `/version` says `capabilities.state`;
   - degrade on 401;
   - same output shape.
10. **Tests.**
    - Existing tests stay green.
    - Add a container variant with a `LITE=` line in `/VERSION`, no `/var/log/messages`, the
      service running as a non-root user with only the confined paths writable, and a fake
      `/api/auth/v1/state`. Cover the header accepted, a forged header refused, the `?sid=`
      fallback, and the detection: `LITE=` alone and `occulited` alone are openccu-lite, neither
      is a CCU.
    - Add provider tests against a fake `/api/meta/v1` for metadata addons.
11. **Docs.**
    - An "openccu-lite" section in the README: what works, what does not, the ports to open,
      that updates come from the system's Addons page.
    - A changelog entry (minor version).
12. **Manifest and catalogue.** Write `openccu-lite.json` where the packaging copies it to the
    root of the tarball: `format`, `id`, names and descriptions (de/en), homepage, licence,
    `release` (repository and asset pattern), `requires.architectures`, `ui` (icon, logo,
    `settings_url` if needed, `session_header: true` once step 6 ships) and the full `runtime`
    block, with a reason per key in its `note`. Start from the handbook's
    `templates/openccu-lite.json`. Validate it against `manifest.schema.json` (JSON Schema 2020-12:
    `npx ajv-cli validate --spec=draft2020 -s manifest.schema.json -d openccu-lite.json`). Draft
    the catalogue entry `{"git": "<repository>", "manifest": "<path of openccu-lite.json>"}` for
    the maintainer, who opens the pull request against occulited's `catalog/catalog.json`.

## How to verify on a system

If the maintainer has an openccu-lite system, give them this checklist; do not claim you ran it:

- install through the Addons page, confined;
- `systemctl status addon-<ID>.service`;
- `journalctl -u addon-<ID>.service` shows no `EROFS`, `EACCES` or `226/NAMESPACE` errors;
- start, stop and restart from the settings page;
- the settings page with and without `?sid=`;
- a forged `X-Occulite-Session` header from another host is refused;
- update over the previous release, with user data kept;
- a reboot;
- uninstall;
- the same package on a CCU3 and on OpenCCU, unchanged behaviour.

## Report

When you are done, report:

- the triage result;
- every file you changed, and why;
- the manifest's `runtime` block, with a reason for each entry;
- what you verified, and where (unit tests, container, real system);
- what you could not verify;
- open questions for the maintainer.

Do not push, tag or release. Report failures with their output.
