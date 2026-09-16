# 11 openccu-lite

[openccu-lite](https://github.com/hobbyquaker/openccu-lite) is a Homematic CCU firmware built
from OpenCCU **without ReGaHSS**. It keeps the radio stack (`rfd`, `hs485d`, `HMIPServer`) and
replaces init scripts and busybox services with **systemd**. A Go service, `occulited`, handles
device names, rooms and functions, logins, system administration and addon management. There is
no built-in WebUI. The user picks a frontend (Homematic Manager, Node-RED via RedMatic, …) and
installs it as an addon.

This chapter describes openccu-lite as an addon platform: what is the same as on OpenCCU, what
is different, and what is gone. [12](12-porting-to-openccu-lite.md) turns this into a porting
checklist. [templates/PORTING-PROMPT.md](../templates/PORTING-PROMPT.md) is the same checklist
as a prompt for a coding agent.

**Status: September 2026, openccu-lite `1.0.0-dev.1`.** The project is not released yet.
Everything below was read from the code and checked on lab boxes (x86_64 OVA, Raspberry Pi 4)
unless it is marked *planned*. The list at the end names what may still change.

## Platform at a glance

| | OpenCCU | openccu-lite |
| --- | --- | --- |
| Architectures (`uname -m`) | armv7l, aarch64, x86_64 | **aarch64** (rpi3- and rpi4-class images) and **x86_64** (OVA). Both also run 32-bit binaries of their own family through `/lib32` (multilib) |
| Init | busybox init, `/etc/init.d/S*` | systemd, journald, udevd |
| ReGaHSS, HM-Script, system variables, programs | yes | **no** |
| WebUI (`/webui`, `/config/*.cgi`, `/api/homematic.cgi`) | yes | **no**. The shell at `/` is occulited's admin UI |
| Addon package format | `.tar.gz` + `update_script` | **unchanged** |
| rc.d script | run by `run-parts` | run inside a **generated unit** `addon-<id>.service` |
| Addon runs as | root | its **own user** `addon-<id>` by default (confined) |
| Logs | `/var/log/messages` | **journal only**; no `/var/log/messages`, no syslogd |
| Tcl | 8.6 | 8.6, with tcllib and `package require HomeMatic` |
| `tclrega.so` | real ReGa client | a **shim** that answers the session check and nothing else |
| Node.js, Python | no | no. Ship your own runtime |
| monit, `checkAddonUpdates.sh`, `updateAddonConfig.tcl` | yes | no |
| Firewall default | `MOST_OPEN` | `RESTRICTIVE`; addon ports are opened per port by the user |
| Radio interfaces | 2001/2000/2010 via lighttpd, plus the daemons' own ports | **loopback only**: `rfd` 127.0.0.1:32001, `hs485d` :32000, `HMIPServer` :32010 |

**Detection.** `/VERSION` keeps OpenCCU's `VERSION`, `PRODUCT` and `PLATFORM` lines and adds
`VARIANT=lite` and `LITE=<version>`. Use `grep -qx 'VARIANT=lite' /VERSION` in shell and
`regexp -line {^LITE=}` in Tcl. `/usr/bin/occulited` is a second signal. A CGI can also look
for `SERVER_SOFTWARE=occulited` in its environment. For the metadata API use the version probe
described below, not `/VERSION`.

**Switching.** `/usr/local` survives an update from OpenCCU to openccu-lite and back. Addons
installed on OpenCCU therefore come along. On the first boot after a switch, occulited:

- **disables addons that use ReGa.** It has a built-in list (CUxD, XML-API, Programmdrucker,
  E-Mail, Sonos, HM-Script runners) and scans the addon's own files for idioms such as
  `dom.GetObject`, `dom.CreateObject`, `:8181/`, `rega.exe`, `hmscript`, `ivtype`;
- **disables addons whose binaries cannot run here.** It reads the ELF header of every file in
  the addon directory and its www directory, `node_modules` included.

In both cases "disabled" means the rc.d script loses its executable bit. The user can turn the
addon back on.

## Installation and the generated unit

Upload, catalogue install and catalogue update all end in the same place: OpenCCU's
`/bin/install_addon`, which runs your `update_script HM-RASPBERRYMATIC` as root, exactly as in
[02](02-package-and-install.md) (stdout discarded, exit 0 / 10 / 13 / 101–106).
`update_script` runs as root in a transient scope, never confined. occulited logs the install
and uninstall to the journal as `addon-install`.

After `update_script` returns, occulited:

1. regenerates the units;
2. if `update_script` started your daemon, stops it and starts it again **inside**
   `addon-<id>.service`, so the unit tracks it;
3. gives the addon's directories back to the addon user if the addon is confined.

A systemd generator writes one unit per executable `/usr/local/etc/config/rc.d/<id>` (busybox
`run-parts` name rules, nothing in safe mode):

```ini
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '. /etc/profile; exec /usr/local/etc/config/rc.d/<id> start'
ExecStop=/bin/sh -c '. /etc/profile; exec /usr/local/etc/config/rc.d/<id> stop'
KillMode=control-group
TimeoutStartSec=300
TimeoutStopSec=120
OOMScoreAdjust=100
UMask=0002
SyslogIdentifier=addon-<id>
```

Your rc.d script therefore keeps its contract from [03](03-rc-script.md):

- `start` puts the daemon in the background and returns;
- `stop` stops the daemon;
- the cgroup catches whatever was left behind.

`init` still runs as root at boot. Units start after the network, lighttpd, occulited and,
unless the addon declares otherwise, `rfd` and `HMIPServer`.

**Do not ship a systemd unit.** A `.service` file or drop-in inside your addon directory is
ignored, and the journal says so. The addon user owns that directory, so a unit file there
would let the addon grant itself root. What the daemon needs goes into the catalogue entry
(below).

**Start/stop buttons keep working.** occulited moves your script to `rc.d/<id>.script` and puts a
wrapper in its place as `rc.d/<id>`:

- `start`, `stop` and `restart` called from outside the unit, for example from your settings
  CGI, become `systemctl <action> addon-<id>.service`;
- when the caller is the addon user, the wrapper sends a request to occulited with the addon's
  control token (`/run/occulite/addon-tokens/<id>`) instead;
- every other command passes through unchanged.

If an update copies a fresh script over the wrapper, the script is adopted again after the
install. You need not change anything for this.

## Confinement

By default an addon runs as `addon-<id>` (uid ≥ 30000, home `/usr/local/addons/<id>`, shell
`/bin/false`). The unit gets this drop-in:

```ini
[Service]
User=addon-<id>
Group=addon-<id>
SupplementaryGroups=certs <runtime.groups>
AmbientCapabilities=<runtime.capabilities>      # empty bounding set when none are declared
NoNewPrivileges=yes
ProtectSystem=strict
ProtectKernelTunables=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
RuntimeDirectory=addon-<id>
RuntimeDirectoryPreserve=yes
ReadWritePaths=-/usr/local/addons/<id> -/usr/local/etc/config/addons/<id> -/usr/local/etc/config/rc.d \
               -/run -/var/log -/tmp -/var/tmp <runtime.data_dirs> <runtime.paths>
```

Before every start, a root step gives the addon's own directories back to the addon user. It
does not follow links.

What this means for your code:

- **Writable**, in short:
  - your addon directory;
  - `/usr/local/etc/config/addons/<id>/`;
  - `/run/addon-<id>/`, owned by you: put the pid file there, **not** in `/var/run/<id>.pid`;
  - whatever the catalogue entry grants.

  Everything else is read-only, `/usr/local/etc/config` included. A write elsewhere fails with
  `EROFS` or `EACCES` in the journal.
- **Not root:**
  - no `chown`;
  - no binding to ports below 1024 without `CAP_NET_BIND_SERVICE`;
  - no `iptables`: the firewall is the user's (see below);
  - no reading root-only files. `/etc/config/server.pem` is readable through the `certs` group,
    other root files in `/etc/config` are not;
  - no `journalctl`.
- **`/tmp` is shared**, not private. `fs.protected_regular` then stops you from rewriting a file
  in `/tmp` that another user created. Keep temporary files in `/run/addon-<id>/` or in your own
  directory.
- **Devices** only through a declared group, such as `dialout` for a serial adapter.
- **No sudo, no polkit, no root helper.** The only privileged thing an addon can ask for is
  starting, stopping and restarting its own unit (the wrapper above). An addon that really needs
  root declares it (`runtime.root`). The user can also switch any addon to root on the Services
  page, behind a warning that calls it unsafe.
- **Settings CGIs** run as the addon user too (see below), but without the unit's sandbox.
- **Upgrades.** Addons that were already installed when a box moved to openccu-lite stay root
  until the user confines them. A newly installed addon is confined. An addon without a
  `runtime` block in the catalogue is confined **and** shown as "undeclared", so a user who sees
  it fail knows where to look.

**Not built yet, and not final:**

- root addons without `CAP_SYS_ADMIN`;
- the radio daemons under users of their own, with device groups;
- lighttpd drop-ins and www links taken as validated copies instead of followed symlinks;
- `info`, `init` and `uninstall` of a confined addon running as the addon user instead of root.

An addon that declares what it needs is not affected by any of these.

## The catalogue and the `runtime` block

openccu-lite has an addon catalogue: a JSON index that the box downloads daily and shows on its
Addons page. An entry is written by the catalogue maintainers, not shipped inside your package:

- `id`: the rc.d name;
- names and descriptions in German and English;
- links and licence;
- the architectures;
- how to find the release asset: `release.github`, plus `release.asset` with `{arch}` and
  `{version}`, or a per-arch `release.assets` map. A sibling `<asset>.sha256` is verified when
  present, so publish one ([07](07-updates-and-releases.md));
- a **`runtime` block**, which is what the box builds the unit from:

| Key | Meaning |
| --- | --- |
| `root` | `true` for an addon that genuinely needs root. Shown as unsafe |
| `capabilities` | e.g. `["CAP_NET_BIND_SERVICE"]` |
| `groups` | supplementary groups, e.g. `["dialout"]` |
| `data_dirs` | extra directories under `/usr/local/` that are chowned to the addon and writable. `/usr/local/<id>` is taken automatically when it exists |
| `paths` | extra writable paths, not chowned |
| `ports`, `port_info` | ports the daemon listens on, with protocol, TLS and a label. They appear as firewall switches, **closed by default** |
| `needs` | `[]`, or any of `rfd`, `hmipserver`, `hs485d`: what the unit waits for. Undeclared means after `rfd` and `HMIPServer` |
| `session.header_since` | the first version of your addon that reads the session header (below). From that version on, the box stops appending `?sid=` |
| `settings_url` | the settings page, when your `Config-Url:` is something else |
| `api_scopes` | scopes for the addon's own API token (below) |

Two files in your package matter too:

- **`openccu-lite.ok`**, an empty file in `/usr/local/addons/<id>/`, says "ported, runs without
  ReGa". It exempts the addon from the ReGa scan; your ReGa code path for the CCU can stay. It
  does not exempt the addon from the architecture check.
- **`openccu-lite.env`** for icons and logos is *planned*.

## Web integration

### How pages are served

- lighttpd serves `/addons/<id>/` from `/usr/local/etc/config/addons/www/<id>` as on a CCU.
- **Every request under `/addons/` passes a session gate.** Without a live login, lighttpd
  answers with a redirect to `/login`. A settings page that forgot its own check is no longer
  open to the LAN; your CGIs must still check (next section).
- `*.cgi` and `*.ccc` under `/addons/` are **executed by occulited**, not by lighttpd's mod_cgi:
  - the interpreter is `/bin/tclsh`, and the working directory is the script's directory;
  - the CGI runs as the addon user when confined, as root otherwise;
  - the environment has `SERVER_SOFTWARE=occulited`, `HTTPS=on`, `REMOTE_ADDR`, and the usual
    CGI variables;
  - timeout 5 minutes, request body up to 64 MiB;
  - the output is **buffered**, so a streaming or long-polling CGI does not work. Use your own
    server for that;
  - `X-Sendfile:` works for files under `/usr/local/tmp/`, including files your user wrote with
    mode 0600, and nowhere else.
- **Your own HTTP server** is reached through a lighttpd drop-in
  `/usr/local/etc/config/lighttpd/<id>.conf`, as in [04](04-webui.md). WebSockets pass. Keep the
  proxied path under `/addons/`, otherwise the gate and the session header do not apply to it.

### Sessions

Session ids on openccu-lite are 26 characters (`[A-Z2-7]`). The browser carries them in the
`occulite_session` cookie over HTTP and `__Secure-occulite_session` over HTTPS.

**`?sid=@xxxxxxxxxx@` still works as a legacy alias.**

- The ten characters are *not* the session. The gate and the `tclrega.so` shim accept them;
  occulited's API never does.
- The box appends the alias only for addons that have not declared the header, and never for a
  proxied frontend.
- The user can switch the alias off, globally or per addon.
- The session check from [04](04-webui.md), `rega_script "Write(system.GetSessionVarStr(...))"`,
  keeps working through the shim. It is the **only** ReGa call the shim answers; any other
  script raises a Tcl error.

**The better way is the header `X-Occulite-Session`.**

- The gate adds it to every request it lets through under `/addons/`: static files, XHRs,
  CGIs (as `HTTP_X_OCCULITE_SESSION`), the proxied server, and WebSocket upgrades.
- lighttpd removes any copy a client sent, in any spelling.
- It holds the credential the gate accepted, without the `@` wrapping.
- It says only that *a* session exists. To learn the user and the role, ask:

```
GET http://127.0.0.1/api/auth/v1/state
Authorization: Bearer <header value>
→ {"authenticated": true, "sid": "...", "user": "...", "role": "admin", ...}
```

Rules for the header:

- **Trust it only on openccu-lite.** A CCU forwards a client's header untouched, and your loopback
  port is open to every local process. Check `/VERSION` first and validate every value against
  `/state`.
- Accept a session only when `/state` answers `authenticated: true` with the same `sid`. Refuse
  API tokens there.
- Fall back to `?sid=` and the shim when there is no header.
- Admin-only settings pages check `role`.

[templates/lib/session.tcl](../templates/lib/session.tcl) does all of this. It is Tcl 8.2 safe,
and on a CCU it behaves exactly as before. For Node-RED, set `adminAuth.tokenHeader:
'x-occulite-session'`, with a `tokens()` function that asks `/state`.

Once a release reads the header everywhere the shell opens it, ask for
`runtime.session.header_since: "<that version>"` in the catalogue entry. Keep accepting `?sid=`,
because older boxes and every CCU still send it.

An addon that logs users in itself (formerly through ReGa's user objects and UDP 1998) uses
`POST /api/auth/v1/login {"username","password"}`.

### Menu: settings page vs. frontend

- **Settings page**: your `Config-Url:` from `info` (and `hm_addons.cfg`). It is shown as the
  *Settings* button on the Addons page and framed at `/addon-settings/<id>`.
  - If your `Config-Url` is not the settings page (Homematic Manager's hands over to its app),
    let `update_script` write the right one when `VARIANT=lite`.
  - Alternatively, the catalogue's `settings_url` names it.
- **Frontend**: a lighttpd drop-in that proxies a plain path under `/addons/` makes the addon a
  menu entry. For anything the parser cannot read, declare the entry explicitly in
  `/usr/local/etc/config/nav.d/<id>.json`:

```json
{"id": "<id>", "label": {"de": "…", "en": "…"}, "icon": "/addons/<id>/icon.svg",
 "href": "/addons/<id>/", "target": "iframe", "order": 50, "keep_alive": false}
```

- **Embedding.** Pages are embedded as same-origin iframes.
  - The shell appends `?theme=system|light|dark&lang=de|en`, sets the `ol-theme` and `ol-lang`
    cookies, and posts `{type: "openccu-lite:theme", theme, lang}` when the user changes either.
    Follow them if you can.
  - A page that forbids framing (`X-Frame-Options`, `frame-ancestors`) is opened in a new tab
    instead.
- `hm_addons.cfg` and `nav.d` both stay supported. *Planned:* the Addons page is being reworked
  into one card list with a pin toggle for frontends, and the separate addon menu goes away.
  Declare your entries as above and let the box place them.

## APIs an addon can use

- **Radio interfaces.** Read the URLs from `/etc/config/InterfacesList.xml`, don't hard-code
  2001/2010. On openccu-lite they are loopback ports (32001, 32000, 32010, VirtualDevices
  `127.0.0.1:39292/groups`). The CCU's lighttpd proxy ports do not exist, not even on loopback.
  Callbacks to your listener on 127.0.0.1 work. Clients off the box cannot connect today;
  optional remote access is *planned*.
- **Metadata API**, `http://127.0.0.1/api/meta/v1`. This is the replacement for names, rooms
  and functions from ReGa.
  - **Detection:** `GET /version` → `{"api":"meta","version":1,…}` without authentication.
    Anything else (404, HTML) means a CCU.
  - **Reading:** `GET /snapshot`, `/objects[?enum=room/eg]`, `/objects/{ref}`, `/enums`,
    `/enums/{enum}/tree`.
  - **Writing:** `PATCH /objects/{ref}` for the name, the enums, and your own `meta.<id>`
    namespace; `POST /objects:bulk`.
  - **Change events:** `GET /events/sse` (Server-Sent Events, `?since=<revision>`, a
    `{"kind":"resync"}` answer means reload the snapshot).
  - **Objects** are keyed by `<interface>.<address>` (`BidCos-RF.JEQ0230153:1`). There are no
    numeric ids.
  - **Rooms and functions** are path trees (`room/eg/wohnzimmer`).
  - The API is frozen for version 1. The full reference is the metadata API document in the
  [openccu-lite repository](https://github.com/hobbyquaker/openccu-lite).
- **Credentials**, sent as `Authorization: Bearer …`:
  - `/usr/local/etc/occulite/local-token` is readable by every addon and has scope `meta:read`
    only;
  - your addon's own token, `/run/occulite/addon-tokens/<id>.api`, carries the scopes from
    `runtime.api_scopes`. It is never `*`, `auth:admin`, `power` or `backup`;
  - a request can use the user's session from the header;
  - a user can create a token on the box and paste it into your configuration.

  A `403` names the missing scope. Scopes include `meta:read`, `meta:write`, `system:read`,
  `logs:read`, `system:write`, `addons:write`, `led`.
- **System API**, `/api/system/v1`. Useful routes: the journal of your unit
  (`GET /log?unit=addon-<id>`, scope `logs:read`), the addon list, and the status LED. Send
  `Content-Length` on `POST` and `PUT`.

**Gone, with no emulation:**

- ReGaHSS and its ports 8181/8183, `rega.exe`/`tclrega.exe`, HM-Script, `dom.*`;
- system variables, programs, favourites, service-message and alarm variables;
- the WebUI JSON-RPC `/api/homematic.cgi` (`Session.login`, `Device.listAll`, `Interface.*`);
- `/config/*.cgi`;
- `checkAddonUpdates.sh`, `updateAddonConfig.tcl`, `hm_autoconf`.

*Planned:* `/var/status/hasInternet` and `checkInternet` go as well.

## Logs, backups, firewall, updates

- **Logs.** Everything your unit writes to stdout and stderr lands in the journal as
  `addon-<id>`, and so do `logger -t <tag>` lines. There is no `/var/log/messages` to grep.
  - Log to stdout or `logger`, and don't write log files that grow on the SD card.
  - Your settings page cannot run `journalctl` as the addon user. Link the box's log page
    (`/system/log?unit=addon-<id>`) or read `GET /api/system/v1/log` with a `logs:read` token.
- **Backups** are OpenCCU's `createBackup.sh` and honour `.nobackup` ([06](06-system-integration.md)).
- **Firewall.**
  - The default is `RESTRICTIVE`.
  - Declared ports appear on the firewall page as switches, closed until the user opens them.
  - A confined addon cannot change the firewall. Show the state if you like, and tell the user
    where to open the port.
  - *Planned:* port ranges, UDP and multicast (mDNS, Matter, HomeKit).
- **monit and cron.** There is no monit; systemd tracks the unit. crond reads
  `/usr/local/crontabs/root` and runs as root, so keep scheduling inside the addon.
- **Updates.** Installs and updates go through the catalogue, which runs your own
  `update_script`.
  - **Hide your own self-updater on openccu-lite** ([07](07-updates-and-releases.md)). It
    bypasses the unit and the ownership steps. Show a line pointing to the box's Addons page
    instead, and answer your update CGI's start command with 403 there.
  - `Update:` and your `update_check.cgi` may stay.
  - *Planned:* automatic update checks become opt-in.

## Not final yet

As of `1.0.0-dev.1`, these may still change:

- the Addons page and menu rework;
- the update guideline, and an optional "has its own updater" catalogue flag;
- `openccu-lite.env`;
- early and parallel addon start (`runtime.start`);
- dropping `CAP_SYS_ADMIN` from root addons;
- port ranges and multicast in `ports`;
- a `runtime.logs` switch;
- signed catalogue installs;
- the session cookie kept away from `/addons/`, with API writes from addon pages then needing a
  header credential;
- remote RPC access;
- daemon users;
- the handling of lighttpd drop-ins and www symlinks.

Build against what is described above as current, and check this chapter again before a release.
