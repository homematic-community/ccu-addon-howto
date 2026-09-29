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
  - Build native `.node` modules per architecture. The system disables an addon whose programs
    cannot run on it.
- **The version inside the package must equal the release tag.** Otherwise the system offers the
  same update forever.
- **A pure shell, Tcl or JS addon** needs one package and no ELF work.
- **Ship a manifest, `openccu-lite.json`, at the root of the tarball** (beside `update_script`)
  once the port is done: what the addon is, where its releases are, and what it needs at runtime
  (step 7). The CCU3 and OpenCCU ignore it. A manifest without `requires.rega: true` also says
  "runs without ReGa", so the ReGa scan does not disable your addon after a switch although your
  CCU code path is still in it. Without a manifest, the empty marker file `openccu-lite.ok` in
  `/usr/local/addons/<id>/` says the same.
- **No systemd unit files, no `.service` in the package.** They are ignored.
- **`.nobackup` on program directories only** ([06](06-system-integration.md)), never on the ones with
  settings or data. After a restore, openccu-lite does not start an addon whose tagged program
  directories came back empty, and offers a reinstall
  ([11](11-openccu-lite.md#logs-backups-firewall-updates)).

## Step 2: `update_script`

- **Leave the CCU logic alone** ([02](02-package-and-install.md)): `update_script` still runs as
  root with `HM-RASPBERRYMATIC`.
- **Create the directories your daemon writes to** inside `/usr/local/addons/<id>/`. You can also
  use `/usr/local/etc/config/addons/<id>/`, but create it yourself: older images fail the unit
  when it is missing. A confined daemon cannot create anything outside its paths.
- **Starting the service after an update** can stay as it is. After the install, occulited:
  - moves a daemon that `update_script` started into its unit;
  - restarts an addon that was running before the update when the script's own start failed.

  If you want the start to happen in the unit right away, use this branch, with the detection
  rule from [11](11-openccu-lite.md#platform-at-a-glance) (a `LITE=` line in `/VERSION` or an
  executable `/usr/bin/occulited`; never `VARIANT=lite`):

  ```sh
  if grep -q '^LITE=' /VERSION 2>/dev/null || [ -x /usr/bin/occulited ]; then
      systemctl start addon-<id>.service 2>/dev/null || true
  elif [ ! -e /etc/init.d/S00InstallAddon ]; then
      cd / && /usr/local/etc/config/rc.d/<id> start
  fi
  ```
- **`Config-Url`.** If your `Config-Url` is not your settings page, write the right one on
  openccu-lite (the same rule), or name it in the manifest's `ui.settings_url`.
- **`ln -sf` over `rc.d/<id>`** is fine: the system adopts the new script again.
- **Firewall.** Do not touch `firewall.conf` or `iptables` on openccu-lite (there is no
  `libfirewall`). Ports are declared in the manifest (step 7).
- **A lighttpd fragment** for your own server: ship it as `etc/lighttpd.conf` in your addon's
  tree. Keep linking or copying it into `/usr/local/etc/config/lighttpd/` for the CCU; on
  openccu-lite the system writes its own validated copy there and your script must not
  ([11](11-openccu-lite.md#how-pages-are-served)).

## Step 3: the rc.d script

- **`start` backgrounds the daemon and returns.** Inside the unit, a foreground daemon would
  block until the 300 s timeout. `setsid`, `start-stop-daemon -b` or `nohup … &` are all fine.
  `cd /` first, as before.
- **The pid file** goes to `/run/addon-<id>/` or into your addon directory when you are not root
  (`[ "$(id -u)" != 0 ]`). `/var/run/<id>.pid` is root's.
- **`stop`** must really stop the daemon. The cgroup cleans up after it, but a clean shutdown
  (a flushed database) is still your job. It must also succeed when the daemon is already gone:
  with `runtime.daemon: true` the system restarts an ended daemon with your `stop` and `start`.
- **A `start` that cannot work fails** with a non-zero exit (a bad configuration), rather than
  starting a daemon that dies at once and is then restarted in a loop.
- **`info` stays as it is.** It is cheap and is called often.
- **`init`** of a confined addon runs in its unit as the addon user, right before `start`, not
  as root at boot. Do nothing there that needs root; answer `init` with nothing (not a usage
  line) if you have no use for it.
- **The daemon starts in `start`, never in `init`.** A script that starts it in `init` and
  answers `start` with *use init to start* leaves a root addon's daemon outside its unit (the
  boot pass's `init` runs as root elsewhere) and a confined addon's as a left-over process in its
  unit; [chapter 11](11-openccu-lite.md) says what follows. Move the start into `start`, or
  branch on `/proc/self/cgroup` naming `addon-<id>.service` if the CCU behaviour must stay.
- **Keep the daemon's stdout and stderr** instead of sending them to `/dev/null`: inside the
  unit they are its journal.
- **`uninstall`** runs as the addon user when the addon is confined, as root otherwise. Remove
  only what you created: the button, the www link, your lighttpd drop-in, your `nav.d` file, and
  let a failed removal pass. After a confined addon's `uninstall` the system removes the rc.d
  entry, the www link, the `hm_addons.cfg` entry, its copy of your lighttpd fragment and your
  emptied directories itself.
- **Wait for the network after boot, CCU3 only.** Skip the wait on openccu-lite: the unit
  already starts after the network, and after the radio daemons unless the manifest says
  otherwise (`needs`, `start`).
- **Don't raise `oom_score_adj` by writing to `/proc`.** A confined user may not write it; the
  unit already sets 100. Guard the write, or skip it on openccu-lite.

## Step 4: confinement

Walk through what the daemon, its CGIs and its helper scripts touch, and fix or declare each
item:

| The addon does | On openccu-lite |
| --- | --- |
| writes config or data in its own directory | fine |
| writes under `/usr/local/<something>` | declare it in `data_dirs` (`/usr/local/<id>` is automatic) |
| writes elsewhere (`/etc/config/…`) | declare it in `paths`, or move it |
| uses a USB stick (`/media/usb*`) | `groups: ["usbstorage"]` and `paths: ["/media"]` (FAT, exFAT and NTFS sticks) |
| writes a file in `/tmp` that a root process may create first | use `/run/addon-<id>/` |
| reads `/etc/config/server.pem` | fine (`certs` group) |
| reads other root files (`/etc/config/*.uuid`, `/etc/shadow`, …) | redesign, or declare `root` |
| reads another addon's files (its token, its configuration) | not possible: a confined addon's tree is closed to others. Keep your own copy, or a location both share deliberately |
| writes a secret (password file, token, key) | write it `0600`, and never under `www`, which stays world-readable |
| binds a port < 1024 | `capabilities: ["CAP_NET_BIND_SERVICE"]`, or use a high port |
| opens a serial or USB device | `groups: ["dialout"]` (or the device's group) |
| changes the firewall | show the state and point to the system's firewall settings instead; declare `ports` |
| calls `chown`, `iptables`, `ip link` | root only. Avoid it, or declare `root: true` |
| needs `CAP_NET_ADMIN`, `CAP_SYS_ADMIN`, `CAP_DAC_OVERRIDE` or another root-equivalent capability, or the `occulite` group | refused for a confined addon ([11](11-openccu-lite.md#the-manifest-and-the-catalogue)): redesign, or declare `root: true` |
| calls `mount` | not even as root. Avoid it; only if there is no other way, `root: true` plus `capabilities: ["CAP_SYS_ADMIN"]` |
| runs `journalctl` | not as the addon user (step 6) |
| installs cron or monit files | cron runs as root and monit does not exist; keep scheduling and supervision inside the daemon |
| patches the read-only root | stop. It is not allowed on openccu-lite. Device descriptions go to `/firmware/rftypes`, which is writable there, with no remount |

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
  `ui.session_header`) must work without it, so don't fail on a missing `sid` when the header is
  there.
- **State changes only on a POST** ([04](04-webui.md#change-state-only-on-a-post)). On
  openccu-lite a link from another site opens your page without its query, and a cross-site
  request with the cookie is refused
  ([11](11-openccu-lite.md#requests-from-other-sites)); a page on your server's own port that
  posts to `/addons/<id>/` counts as another site. Browser calls to `/api/…` that change state
  send `X-Occulite-Request: 1` (or the session as `Authorization: Bearer`).
- **No ReGa scripts in CGIs** other than the session check. The shim raises a Tcl error for
  anything else.
- **CGIs are buffered and run as your user.** Move streaming, long polling and progress output to
  your own server or to a status file that the page polls.
- **Logins.** If your addon logs users in against the CCU (ReGa user objects, UDP 1998), switch
  to `POST /api/auth/v1/login` on openccu-lite.
- **Frontend.** Keep its proxied path under `/addons/`, and keep the lighttpd fragment inside
  what the system accepts (proxying to this system only, no `include`, no `cgi.*`, no
  `$SERVER["socket"]`). Add a `nav.d/<id>.json` if your fragment is not a plain `proxy.server`
  mapping. Honour `?theme=` and `?lang=` and the
  `openccu-lite:theme` message if you can. Allow same-origin framing.
- **Hide the self-updater on openccu-lite** (button, notice, modal). Show one line such as
  "Updates are installed from the openccu-lite Addons page" with a link to `/addons`. Make the
  updater's start command answer `403` with the same text. `update_check.cgi` may stay. A release
  that still carries its own updater sets `ui.own_updater: true`.

## Step 6: logs

- **Write to stdout, stderr or `logger`.** The journal collects them under `addon-<id>` or your
  tag. Don't write growing log files to the SD card.
- **The log view on your settings page.**
  - On a CCU, keep `grep` on `/var/log/messages`.
  - On openccu-lite, link `/system/log?unit=addon-<id>`, or read
    `GET /api/system/v1/log?unit=addon-<id>` with an addon token that has `logs:read`.
  - Root addons can call `journalctl -u addon-<id>.service` directly.
- **"Last error" displays** must not assume `/var/log/messages` exists.

## Step 7: the manifest and the catalogue entry

Write `openccu-lite.json` ([11](11-openccu-lite.md#the-manifest-and-the-catalogue), the format in
[manifest-format.md](https://github.com/hobbyquaker/occulited/blob/master/docs/manifest-format.md);
[templates/openccu-lite.json](../templates/openccu-lite.json) is a working one) and have your
packaging copy it to the root of the tarball, beside `update_script`:

- `format`, `id` (the rc.d name), `name` and `description` in German and English, `homepage`,
  `licence`;
- `release`: the GitHub repository and the asset pattern with `{arch}` and `{version}`;
- `requires.architectures`;
- `ui`: `icon` and `logo` inside the package, `settings_url` if needed, `session_header: true`
  once step 5 shipped, `own_updater` if you keep an updater;
- **the `runtime` block**: `needs`, `start: "early"` only when the addon retries within seconds
  without error lines, `daemon: true` when `start` leaves a process running (leave it out for an
  addon that only prepares things), `ports` with `port_info`, `data_dirs`, `paths`, `groups`,
  `capabilities`, `api_scopes`, and a `note` saying why and what the addon contacts outside the
  system. Leave `root` out unless there is no other way.

Validate it with
[manifest.schema.json](https://github.com/hobbyquaker/occulited/blob/master/docs/manifest.schema.json)
(`npx ajv-cli validate --spec=draft2020 -s manifest.schema.json -d openccu-lite.json`; the schema
is JSON Schema 2020-12, and without `--spec=draft2020` ajv refuses the schema itself). An addon
without a `runtime` block is shown as "undeclared", and so is one whose block says only `needs`
and `start`: add `daemon: true` (or any key that is true for it), or `{}` for an addon that keeps
no process.

Declare `start: "early"` only after the addon does what
[11](11-openccu-lite.md#installation-and-the-generated-unit) lists: it retries within seconds,
logs no warning while the interfaces are not up yet, and does not take a missing interface port
for a CCU.

To be listed in the catalogue, open a pull request against
[occulited's `catalog/catalog.json`](https://github.com/hobbyquaker/occulited/blob/master/catalog/catalog.json)
with one entry: `{"git": "<your repository>", "manifest": "<path of openccu-lite.json in it>"}`
([catalog-format.md](https://github.com/hobbyquaker/occulited/blob/master/docs/catalog-format.md)).
The system reads the manifest at your latest release tag, so release once after adding it.

## Step 8: names, rooms and functions (metadata addons only)

Keep the ReGa provider and add a second one with the **same public surface**. For a Node.js
addon that is: keep your CCU path (homematic-xmlrpc, binrpc, homematic-rega) and add an
openccu-lite backend on [occulite-client](https://github.com/hobbyquaker/occulite-client); its
[porting guide](https://github.com/hobbyquaker/occulite-client/blob/main/docs/porting.md) walks
through it with hm2mqtt.js. Load it lazily, in the code path that found openccu-lite, so a CCU
never loads it. The points below are what such a backend does, in any language:

1. **Detection** at start and on reconnect: `GET http://127.0.0.1/api/meta/v1/version`.
   - A JSON answer with `"api":"meta"` means openccu-lite.
   - A 404 or HTML answer means a CCU: stop probing.
   - A refused connection or a timeout means the system is still booting: retry once a minute.
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
   - On the system, read `/usr/local/etc/occulite/local-token` (`meta:read`) by default.
   - For writes (`PATCH /objects/{ref}`, your `meta.<id>` namespace), use the user's session or
     a token with `meta:write`: your own from `api_scopes`, or one the user created.
   - Off the system, use a token option, or ask for one with client pairing
     ([11](11-openccu-lite.md#apis-an-addon-can-use)).
   - A `401` means run without names and log it once; never crash.
6. **Values at start.** An addon that reads every datapoint with `getParamset` when it starts
   can read them in one call from lite-rpc's state store (`GET /api/rpc/v1/state`) when
   `/version`'s `capabilities.state` is true, and keep the sweep for the CCU.
7. **ReGa-only features** (system variables, programs, scripts) stay accepted in the
   configuration, log one line on openccu-lite ("not available on this system"), and are
   documented as CCU-only.

The full API reference is [meta-api.md](https://github.com/hobbyquaker/occulited/blob/master/docs/meta-api.md)
in the occulited repository, the mapping from ReGa and what has no replacement are
[porting-from-rega.md](https://github.com/hobbyquaker/openccu-lite/blob/main/docs/porting-from-rega.md)
in the openccu-lite repository, and occulited's
[`fixtures/`](https://github.com/hobbyquaker/occulited/tree/master/fixtures) are the conformance
corpus to test a reader against.

## Step 9: test

- **The CCU paths:** your existing tests, unchanged and green. On a CCU nothing may differ.
- **Container test** ([08](08-testing.md)): add a variant with `LITE=<version>` (and
  `VARIANT=lite`, as the images write both) in `/VERSION` and without `/var/log/messages`, and one
  with an executable `occulited` but no `LITE=` line: both must count as openccu-lite, a
  `/VERSION` with neither as a CCU. Run the service as a non-root user with only the
  confined writable paths writable, and send the session header through a fake `/api/auth/v1/state`.
- **On an openccu-lite system:**
  - install through the Addons page, confined;
  - `systemctl status addon-<id>.service`;
  - `journalctl -u addon-<id>.service`: no `EROFS`, `EACCES` or `226/NAMESPACE` errors;
  - start, stop and restart from your settings page;
  - the settings page opened from the shell, once with and once without `?sid=`;
  - a request with a forged `X-Occulite-Session` header from another host must fail;
  - an update over the previous release, with user data kept;
  - a reboot;
  - with `start: "early"`: `systemctl stop rfd hmipserver; systemctl restart
    --job-mode=ignore-requirements addon-<id>`, then start them again; the journal shows retries
    as info and no warning;
  - uninstall;
  - an OpenCCU backup restored onto openccu-lite with your addon in it.
- **Report** what you verified on which system, and what only passed in the container.

## Step 10: document

Add an "openccu-lite" section to your README:

- what works;
- what does not (ReGa features);
- which ports the user must open;
- where the token comes from (metadata addons);
- that updates come from the system's Addons page.

Add a changelog entry. A port is a minor version: nothing is removed.
