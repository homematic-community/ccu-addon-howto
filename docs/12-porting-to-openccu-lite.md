# 12 Porting an addon to openccu-lite

This is the checklist for making an existing CCU3 / OpenCCU addon run on
[openccu-lite](https://github.com/hobbyquaker/openccu-lite). [11](11-openccu-lite.md) has the
background. [templates/PORTING-PROMPT.md](../templates/PORTING-PROMPT.md) is this chapter as a
prompt for a coding agent.

**The one rule: one package for all three firmwares.** Keep every CCU code path. Detect
openccu-lite at runtime and add an `if` where it differs. A user who moves a backup between a
CCU and openccu-lite must not have to reconfigure your addon, and on a CCU nothing may change.

## Step 0: which kind of addon is it?

```sh
grep -rnE 'dom\.(GetObject|CreateObject|DeleteObject)|rega_script|tclrega|:8181|rega\.exe|hmscript|homematic\.cgi|system\.(Exec|GetVar)|/var/log/messages|/var/run/|start-stop-daemon|iptables|libfirewall|monit|checkAddonUpdates|updateAddonConfig|:2001|:2010|:2000' .
```

| What you find | Kind | Work |
| --- | --- | --- |
| Only the `check_session` call | **ABI-only** (most addons: brokers, bridges, tools) | Steps 1–7. No new API |
| Device names, rooms, functions from ReGa | **Metadata reader or writer** | Steps 1–7, then step 8 |
| System variables, programs, HM-Script, `homematic.cgi` as the core feature | **ReGa-bound** (CUxD-style, XML-API, script runners) | Nothing to port: there is no ReGa and never will be. Say so in your README |

## Step 1: packaging

- **Architectures.**
  - Publish one asset per `uname -m`: `aarch64` and `x86_64` for openccu-lite, plus `armv7l` if
    you still support the stock CCU3.
  - Put the architecture in the asset name (`<name>-<arch>-<version>.tar.gz`) and publish a
    `.sha256` sibling ([07](07-updates-and-releases.md)).
  - An `armv7l` asset is never chosen on openccu-lite: its ARM images are 64-bit.
  - Build native `.node` modules per architecture. The box disables an addon whose programs
    cannot run on it.
- **The version inside the package must equal the release tag.** Otherwise the box offers the
  same update forever.
- **A pure shell, Tcl or JS addon** needs one package and no ELF work.
- **Ship `openccu-lite.ok`** (an empty file) in `/usr/local/addons/<id>/` once the port is done.
  Without it, the ReGa scan may disable your addon after a switch, because your CCU code path is
  still in it.
- **No systemd unit files, no `.service` in the package.** They are ignored.

## Step 2: `update_script`

- **Leave the CCU logic alone** ([02](02-package-and-install.md)): `update_script` still runs as
  root with `HM-RASPBERRYMATIC`.
- **Create the directories your daemon writes to** inside `/usr/local/addons/<id>/`. You can also
  use `/usr/local/etc/config/addons/<id>/`, but create it yourself: older images fail the unit
  when it is missing. A confined daemon cannot create anything outside its paths.
- **Starting the service after an update** can stay as it is. After the install, occulited:
  - moves a daemon that `update_script` started into its unit;
  - restarts an addon that was running before the update when the script's own start failed.

  If you want the start to happen in the unit right away, use this branch (RedMatic does):

  ```sh
  if grep -qx 'VARIANT=lite' /VERSION 2>/dev/null; then
      systemctl start addon-<id>.service 2>/dev/null || true
  elif [ ! -e /etc/init.d/S00InstallAddon ]; then
      cd / && /usr/local/etc/config/rc.d/<id> start
  fi
  ```
- **`Config-Url`.** If your `Config-Url` is not your settings page, write the right one when
  `VARIANT=lite`.
- **`ln -sf` over `rc.d/<id>`** is fine: the box adopts the new script again.
- **Firewall.** Do not touch `firewall.conf` or `iptables` on openccu-lite. Ports are
  declared in the catalogue (step 7).

## Step 3: the rc.d script

- **`start` backgrounds the daemon and returns.** Inside the unit, a foreground daemon would
  block until the 300 s timeout. `setsid`, `start-stop-daemon -b` or `nohup … &` are all fine.
  `cd /` first, as before.
- **The pid file** goes to `/run/addon-<id>/` or into your addon directory when you are not root
  (`[ "$(id -u)" != 0 ]`). `/var/run/<id>.pid` is root's.
- **`stop`** must really stop the daemon. The cgroup cleans up after it, but a clean shutdown
  (a flushed database) is still your job.
- **`info` stays as it is.** It is cheap and is called often.
- **`uninstall`** still runs as root today; do not rely on that. Remove only what you created:
  the button, the www link, your lighttpd drop-in, your `nav.d` file.
- **Wait for the network after boot, CCU3 only.** Skip the wait on openccu-lite: the unit
  already starts after the network and the radio daemons.
- **Don't raise `oom_score_adj` by writing to `/proc`.** A confined user may not write it; the
  unit already sets 100. Guard the write, or skip it on openccu-lite.

## Step 4: confinement

Walk through what the daemon, its CGIs and its helper scripts touch, and fix or declare each
item:

| The addon does | On openccu-lite |
| --- | --- |
| writes config or data in its own directory | fine |
| writes under `/usr/local/<something>` | declare it in `data_dirs` (`/usr/local/<id>` is automatic) |
| writes elsewhere (`/etc/config/…`, `/media/usb*`) | declare it in `paths`, or move it |
| writes a file in `/tmp` that a root process may create first | use `/run/addon-<id>/` |
| reads `/etc/config/server.pem` | fine (`certs` group) |
| reads other root files (`/etc/config/*.uuid`, `/etc/shadow`, …) | redesign, or declare `root` |
| binds a port < 1024 | `capabilities: ["CAP_NET_BIND_SERVICE"]`, or use a high port |
| opens a serial or USB device | `groups: ["dialout"]` (or the device's group) |
| changes the firewall | show the state and link the box's firewall page instead; declare `ports` |
| calls `chown`, `mount`, `iptables`, `ip link` | root only. Avoid it, or declare `root: true` |
| runs `journalctl` | not as the addon user (step 6) |
| installs cron or monit files | cron runs as root and monit does not exist; keep scheduling and supervision inside the daemon |
| patches the read-only root | stop. It is not allowed on openccu-lite |

Aim for no `root`. Test with the addon confined: that is the default for every new install.

## Step 5: web UI and session

- **Session check.** Replace `lib/session.tcl` with
  [templates/lib/session.tcl](../templates/lib/session.tcl) and call `request_session_ok` instead
  of `check_session $sid`:
  - on openccu-lite it takes the `X-Occulite-Session` header and confirms it with
    `GET /api/auth/v1/state`;
  - everywhere else it falls back to `?sid=` and ReGa.

  Add a `role` check for admin-only pages.
- **Your own server** (Node, Go, …):
  - on openccu-lite, read the `X-Occulite-Session` request header and confirm it the same way;
  - elsewhere, keep your old login;
  - never trust the header on a CCU.
  - For Node-RED, use `adminAuth.tokenHeader: 'x-occulite-session'`.
- **Pass `?sid=` on only where it arrived.** A page opened without `?sid=` (after
  `header_since`) must work without it, so don't fail on a missing `sid` when the header is
  there.
- **No ReGa scripts in CGIs** other than the session check. The shim raises a Tcl error for
  anything else.
- **CGIs are buffered and run as your user.** Move streaming, long polling and progress output to
  your own server or to a status file that the page polls.
- **Logins.** If your addon logs users in against the CCU (ReGa user objects, UDP 1998), switch
  to `POST /api/auth/v1/login` on openccu-lite.
- **Frontend.** Keep its proxied path under `/addons/`. Add a `nav.d/<id>.json` if your lighttpd
  drop-in is not a plain `proxy.server` mapping. Honour `?theme=` and `?lang=` and the
  `openccu-lite:theme` message if you can. Allow same-origin framing.
- **Hide the self-updater on openccu-lite** (button, notice, modal). Show one line such as
  "Updates are installed from the openccu-lite Addons page" with a link to `/addons`. Make the
  updater's start command answer `403` with the same text. `update_check.cgi` may stay.

## Step 6: logs

- **Write to stdout, stderr or `logger`.** The journal collects them under `addon-<id>` or your
  tag. Don't write growing log files to the SD card.
- **The log view on your settings page.**
  - On a CCU, keep `grep` on `/var/log/messages`.
  - On openccu-lite, link `/system/log?unit=addon-<id>`, or read
    `GET /api/system/v1/log?unit=addon-<id>` with an addon token that has `logs:read`.
  - Root addons can call `journalctl -u addon-<id>.service` directly.
- **"Last error" displays** must not assume `/var/log/messages` exists.

## Step 7: the catalogue entry

Ask the openccu-lite addon catalogue to list your addon, and give the maintainers:

- `id`, the names and descriptions in German and English, homepage, repository, licence;
- the architectures, and the release asset pattern;
- **the `runtime` block**: `needs`, `ports` with `port_info`, `data_dirs`, `paths`, `groups`,
  `capabilities`, `api_scopes`, `settings_url` if needed, and `session.header_since` once step 5
  shipped. Leave `root` out unless there is no other way.

An addon without a `runtime` block is shown as "undeclared".

## Step 8: names, rooms and functions (metadata addons only)

Keep the ReGa provider and add a second one with the **same public surface**:

1. **Detection** at start and on reconnect: `GET http://127.0.0.1/api/meta/v1/version`.
   - A JSON answer with `"api":"meta"` means openccu-lite.
   - A 404 or HTML answer means a CCU: stop probing.
   - A refused connection or a timeout means the box is still booting: retry once a minute.
2. **Load `GET /snapshot`**, then follow `GET /events/sse?since=<revision>`.
   - Reload the snapshot on an `import` or `resync` event.
   - The stream opens with `: connected` and sends a heartbeat every 30 s.
3. **Persist the snapshot** in its own file next to your ReGa cache.
4. **Map the data.**
   - Objects are keyed by `<interface>.<address>`; there are no numeric ids.
   - Rooms and functions are path trees. A channel in `room/eg/bad` is also in `room/eg`.
   - Build the flat name lists your users already see, and keep your output shape unchanged.
   - Treat enum ids as data.
5. **Credentials.**
   - On the box, read `/usr/local/etc/occulite/local-token` (`meta:read`) by default.
   - For writes (`PATCH /objects/{ref}`, your `meta.<id>` namespace), use the user's session or
     a token with `meta:write`: your own from `api_scopes`, or one the user created.
   - Off the box, use a token option.
   - A `401` means run without names and log it once; never crash.
6. **ReGa-only features** (system variables, programs, scripts) stay accepted in the
   configuration, log one line on openccu-lite ("not available on this box"), and are
   documented as CCU-only.

The full API reference is in the [openccu-lite repository](https://github.com/hobbyquaker/openccu-lite).

## Step 9: test

- **The CCU paths:** your existing tests, unchanged and green. On a CCU nothing may differ.
- **Container test** ([08](08-testing.md)): add a variant with `VARIANT=lite` and `LITE=…` in
  `/VERSION` and without `/var/log/messages`. Run the service as a non-root user with only the
  confined writable paths writable, and send the session header through a fake `/api/auth/v1/state`.
- **On an openccu-lite box:**
  - install through the Addons page, confined;
  - `systemctl status addon-<id>.service`;
  - `journalctl -u addon-<id>.service`: no `EROFS`, `EACCES` or `226/NAMESPACE` errors;
  - start, stop and restart from your settings page;
  - the settings page opened from the shell, once with and once without `?sid=`;
  - a request with a forged `X-Occulite-Session` header from another host must fail;
  - an update over the previous release, with user data kept;
  - a reboot;
  - uninstall;
  - an OpenCCU backup restored onto openccu-lite with your addon in it.
- **Report** what you verified on which box, and what only passed in the container.

## Step 10: document

Add an "openccu-lite" section to your README:

- what works;
- what does not (ReGa features);
- which ports the user must open;
- where the token comes from (metadata addons);
- that updates come from the box's Addons page.

Add a changelog entry. A port is a minor version: nothing is removed.
