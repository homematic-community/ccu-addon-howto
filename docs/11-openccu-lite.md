# 11 openccu-lite

[openccu-lite](https://github.com/hobbyquaker/openccu-lite) is a Homematic CCU firmware built
from OpenCCU **without ReGaHSS**. It keeps the radio stack (`rfd`, `hs485d`, `HMIPServer`) and
replaces init scripts and busybox services with **systemd**. A Go service,
[`occulited`](https://github.com/hobbyquaker/occulited), handles device names, rooms and
functions, logins, system administration and addon management. There is no built-in WebUI. The
user picks a frontend (Homematic Manager, Node-RED via RedMatic, …) and installs it as an addon.

This chapter describes openccu-lite as an addon platform: what is the same as on OpenCCU, what
is different, and what is gone. [12](12-porting-to-openccu-lite.md) turns this into a porting
checklist. [templates/PORTING-PROMPT.md](../templates/PORTING-PROMPT.md) is the same checklist
as a prompt for a coding agent.

**Status: September 2026, openccu-lite `1.0.0-dev.28`,** the first public release (a
pre-release for test systems, [releases](https://github.com/hobbyquaker/openccu-lite/releases)).
Everything below was read from the code and the documents of that release; the first version of
this chapter (`1.0.0-dev.1`) was also checked on test systems (x86_64 OVA, Raspberry Pi 4). The
list at the end names what may still change.

**The references this chapter summarises** (normative where they say so):

| Document | What it defines |
| --- | --- |
| [occulited `docs/manifest-format.md`](https://github.com/hobbyquaker/occulited/blob/master/docs/manifest-format.md) and [`manifest.schema.json`](https://github.com/hobbyquaker/occulited/blob/master/docs/manifest.schema.json) | the addon manifest `openccu-lite.json` |
| [occulited `docs/catalog-format.md`](https://github.com/hobbyquaker/occulited/blob/master/docs/catalog-format.md) | the addon catalogue |
| [occulited `docs/meta-api.md`](https://github.com/hobbyquaker/occulited/blob/master/docs/meta-api.md) and [`meta-format.md`](https://github.com/hobbyquaker/occulited/blob/master/docs/meta-format.md) | the metadata API: names, rooms, functions |
| [occulited `docs/system-api.md`](https://github.com/hobbyquaker/occulited/blob/master/docs/system-api.md) | the system and auth APIs, lite-rpc, the addon CGIs, the embedding contract |
| [openccu-lite `docs/addons.md`](https://github.com/hobbyquaker/openccu-lite/blob/main/docs/addons.md) | addons on the system: the ReGa and architecture checks, confinement, the start/stop wrapper |
| [openccu-lite `docs/porting-from-rega.md`](https://github.com/hobbyquaker/openccu-lite/blob/main/docs/porting-from-rega.md) | the mapping from ReGa to the metadata API, and what has no replacement |

## Platform at a glance

| | OpenCCU | openccu-lite |
| --- | --- | --- |
| Architectures (`uname -m`) | armv7l, aarch64, x86_64 | **aarch64** (rpi3- and rpi4-class images) and **x86_64** (OVA). Both also run 32-bit binaries of their own family through `/lib32` (multilib) |
| Init | busybox init, `/etc/init.d/S*` | systemd, journald, udevd |
| ReGaHSS, HM-Script, system variables, programs | yes | **no** |
| WebUI (`/webui`, `/config/*.cgi`, `/api/homematic.cgi`) | yes | **no**. The shell at `/` is occulited's admin UI |
| Addon package format | `.tar.gz` + `update_script` | **unchanged**, plus an optional manifest `openccu-lite.json` at the root of the tarball |
| rc.d script | run by `run-parts` | run inside a **generated unit** `addon-<id>.service` |
| Addon runs as | root | its **own user** `addon-<id>` by default (confined) |
| Logs | `/var/log/messages` | **journal only**; no `/var/log/messages`, no syslogd |
| Tcl | 8.6 | 8.6, with tcllib and `package require HomeMatic` |
| `tclrega.so` | real ReGa client | a **shim** that answers the session check and nothing else |
| Node.js, Python | no | no. Ship your own runtime |
| monit, `checkAddonUpdates.sh`, `updateAddonConfig.tcl` | yes | no |
| Firewall | `firewall.conf` via `libfirewall.tcl`, default `MOST_OPEN` | occulited's own rule list, default policy **DROP** on a fresh system; `libfirewall` is not in the image. Addon ports are switches the user opens |
| Radio interfaces | 2001/2000/2010 via lighttpd, plus the daemons' own ports | **loopback only**: `rfd` 127.0.0.1:32001, `hs485d` :32000, `HMIPServer` :32010. The daemons run as their own users (`rfd`, `hs485d`, `hmipserver`). Classic RPC from the LAN is an opt-in; lite-rpc (`/api/rpc/v1`) is the API way |

**Detection: one rule.** A system is openccu-lite when **`/VERSION` has a `LITE=` line, or
`/usr/bin/occulited` is an executable file**. The same rule in every language:

```sh
grep -q '^LITE=' /VERSION 2>/dev/null || [ -x /usr/bin/occulited ]      # sh
```
```tcl
[regexp -line {^LITE=} $version] || [file exists /usr/bin/occulited]   ;# Tcl (templates/lib/session.tcl)
```
```js
/^LITE=/m.test(fs.readFileSync('/VERSION', 'utf8')) || fs.existsSync('/usr/bin/occulited')   // JS
```

`/VERSION` keeps OpenCCU's `VERSION`, `PRODUCT` and `PLATFORM` lines; the image build appends
`VARIANT=lite` and `LITE=<version>` (`1.0.0-dev.30`, say). **`VARIANT=lite` is written too, but it
is not the marker to test.** A CCU3 and OpenCCU have neither the `LITE=` line nor `occulited`.
RedMatic, hm2mqtt.js, ccu-addon-mosquitto and Homematic Manager all use this rule. A CGI can also
look for `SERVER_SOFTWARE=occulited` in its environment. For the metadata API use the version
probe described below, not `/VERSION`.

**Switching.** `/usr/local` survives an update from OpenCCU to openccu-lite and back. Addons
installed on OpenCCU therefore come along. On the first boot after a switch, occulited:

- **disables addons that use ReGa.** It has a built-in list (CUxD, XML-API, Programmdrucker,
  E-Mail, Sonos, HM-Script runners) and scans the addon's own files for idioms such as
  `dom.GetObject`, `dom.CreateObject`, `:8181/`, `rega.exe`, `hmscript`, `ivtype`. An addon is
  exempt when it is in the catalogue, when its manifest does not say `requires.rega: true`, or
  when it carries the marker file `openccu-lite.ok`;
- **disables addons whose binaries cannot run here.** It reads the ELF header of every file in
  the addon directory and its www directory, `node_modules` included. Nothing exempts from this
  check.

In both cases "disabled" means the rc.d script loses its executable bit. The user can turn the
addon back on. An addon disabled for its binaries and known to the catalogue gets a *Reinstall
from the catalogue* button.

## Installation and the generated unit

Upload, catalogue install and catalogue update all end in the same place: OpenCCU's
`/bin/install_addon`, which runs your `update_script HM-RASPBERRYMATIC` as root, exactly as in
[02](02-package-and-install.md) (stdout discarded, exit 0 / 10 / 13 / 101–106).
`update_script` runs as root in a transient scope, never confined. occulited writes the
script's output to the journal as `addon-install`.

**Before** `update_script` runs, occulited reads `openccu-lite.json` from the root of the archive
(below). **After** it returns, occulited applies the manifest to the addon whose rc.d entry the
install created or changed, then:

1. puts its start/stop wrapper in front of the rc.d script again and regenerates the units;
2. if `update_script` started your daemon, stops it and starts it again **inside**
   `addon-<id>.service`, so the unit tracks it;
3. gives the addon's directories back to the addon user if the addon is confined.

A systemd generator writes one unit per executable `/usr/local/etc/config/rc.d/<id>` (busybox
`run-parts` name rules, nothing in safe mode):

```ini
[Unit]
After=network.target lighttpd.service occulited.service occu-addons.service <needs>
PartOf=addons.target
Before=addons.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecCondition=+/usr/libexec/occu/lite-addon-payload <id>     # images after 1.0.0-dev.30, see Backups
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

**A daemon that ends is restarted** (since `1.0.0-dev.30`) when the manifest declares
`runtime.daemon: true`. systemd cannot do it for a oneshot unit, so occulited watches it: when the
unit is still *active* but no process is left in it, occulited restarts the unit (your `stop`,
then your `start`) after 2 s, doubling up to 5 minutes, and starts from 2 s again once the daemon
has run for two minutes. Three such restarts within 15 minutes are a *crash-loop* warning on the
Status page. A unit the user stopped, or one whose `start` failed, is left alone. An addon without
the declaration is not restarted; it only gets the *Exited* warning. For your script this means:

- `stop` must succeed on a daemon that is already gone;
- a `start` that cannot work (a bad configuration) should fail with a non-zero exit, not start a
  daemon that dies a second later: a failed start is the unit's *failed* state, which names the
  cause, while a dying daemon is restarted until the backoff reaches five minutes.

**When a unit starts** follows the manifest's `runtime` block:

- undeclared: after `rfd` and `HMIPServer`, whose RPC answers once their units are active;
- `needs: []`: right after the network, the web server and occulited (a broker, a web page);
- `needs: ["rfd"]` and the like: after exactly those interface processes;
- `start: "early"`: before the interface processes, which the unit only *wants*. Declare it only
  when the addon retries within seconds and logs no errors while it waits. The user can switch
  the early start off, globally and per addon.

Units are not ordered against each other; addons start side by side.

**What the early start asks of an addon in practice**, as Homematic Manager, hm2mqtt.js and
RedMatic do it:

- retry the interface `init` after 1, 2, 4 and 8 s, then every 15 s;
- log a refused connection before the interface was ever subscribed as info, not as a warning;
  a refusal after it had been subscribed, and every other error, stays a warning;
- do not decide "am I on a CCU" by a listening interface port: before `rfd` runs there is none.
  `/etc/config/InterfacesList.xml` is there from the first second;
- an interface probe must go on probing the interfaces it did not find at the first try;
- replace a BIN-RPC client whose socket is gone before the next attempt instead of waiting for its
  own reconnect timer;
- a callback for an init id you have not registered yet (the interface process re-announcing the
  previous run's subscription) is normal, not a warning.

To test the wait without a reboot: `systemctl restart addon-<id>` also pulls `rfd` and
`HMIPServer` up again (the unit *wants* them); `systemctl stop rfd hmipserver; systemctl restart
--job-mode=ignore-requirements addon-<id>` keeps them down while your addon starts.

**`init`** of a root addon runs at boot as root, before the radio daemons, as on a CCU. For a
confined addon it runs **inside its unit, as the addon user, right before `start`** (an
`ExecStartPre` after the ownership step below), with the unit's sandbox: only the addon's own
directories and what the manifest declares are writable. The boot pass skips a confined addon's
`init`. An addon without an `init` case is fine: that step's exit status is ignored. The boot
pass runs the rc.d entries only, never a `<id>.script` file directly.

**Do not ship a systemd unit.** A `.service` file or drop-in inside your addon directory is
ignored, and the journal says so. The addon user owns that directory, so a unit file there
would let the addon grant itself root. What the daemon needs goes into the manifest (below).

**Start/stop buttons keep working.** occulited moves your script to `rc.d/<id>.script` and puts a
wrapper in its place as `rc.d/<id>`:

- `start`, `stop` and `restart` called from outside the unit, for example from your settings
  CGI, become `systemctl <action> addon-<id>.service`;
- when the caller is the addon user, the wrapper sends a request to occulited with the addon's
  control token (`/run/occulite/addon-tokens/<id>`) instead;
- every other command passes through unchanged. For a confined addon, `info` (every listing:
  the menu, the Addons page, the update check) and `uninstall` run as the addon user, with
  `HOME=/usr/local/addons/<id>` and the firmware `PATH`. The unit is stopped before `uninstall`.
  Afterwards the system removes, as root, what the script could not: the rc.d entry, the
  `www/<id>` link, the `hm_addons.cfg` entry, its copy of your lighttpd fragment, and your
  standard directories once the script emptied them. A directory with anything left in it stays,
  so an addon that keeps its configuration for a reinstall keeps it. An `rm` of those entries in
  your script fails quietly as the addon user; that is expected.

If an update copies a fresh script over the wrapper, the script is adopted again after the
install. You need not change anything for this.

## Confinement

By default an addon runs as `addon-<id>` (uid ≥ 30000, home `/usr/local/addons/<id>`, shell
`/bin/false`). The unit gets this drop-in:

```ini
[Service]
User=addon-<id>
Group=addon-<id>
SupplementaryGroups=<runtime.groups> certs
AmbientCapabilities=<runtime.capabilities>     # with CapabilityBoundingSet= the same list
CapabilityBoundingSet=                          # empty when none are declared
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

**Your tree is yours alone** (since `1.0.0-dev.29`). The same step also closes a confined
addon's directories to everyone else: it takes group-write and the world's read and write bits
off, so a directory ends at most `0751` (traversable, not listable) and a file at most `0640`
(a program `0751`), with the group the addon's own. One addon cannot read another's
configuration, sessions or credentials, which is new: on a CCU every addon is root and reads
everything. What stays readable is your `www` tree and the directory that holds it, because the
system serves them to the browser. So:

- **keep secrets out of `www`**;
- **write a credential file `0600` yourself.** The step only ever tightens, never loosens, and
  it runs before the next start, not when you write the file;
- an addon that reached into another addon's files (a shared token, a configuration) needs its
  own copy, or a location both deliberately share.

What this means for your code:

- **Writable**, in short:
  - your addon directory;
  - `/usr/local/etc/config/addons/<id>/`;
  - `/run/addon-<id>/`, owned by you: put the pid file there, **not** in `/var/run/<id>.pid`;
  - whatever the manifest declares.

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
- **Root is not everything.** A root addon has no `CAP_SYS_ADMIN`: `mount -o remount,rw /`
  answers *permission denied*. `/firmware/rftypes` is writable at boot anyway (an overlay on the
  user partition), so device descriptions go there without a remount and survive firmware
  updates. Only an addon that truly has to mount declares `capabilities: ["CAP_SYS_ADMIN"]` beside
  `root: true`.
- **Settings CGIs** run as the addon user too (see below), but without the unit's sandbox.
- **Upgrades.** Addons that were already installed when a system moved to openccu-lite stay
  root until the user confines them. A newly installed addon is confined. An addon without a
  `runtime` block is confined **and** shown as "undeclared", so a user who sees it fail knows
  where to look. Since `1.0.0-dev.29`, a block that says only the start order (`needs`, `start`,
  with or without a `note`) keeps the mark too, because the start order says nothing about what the addon needs to
  run. Any other key removes it, `daemon` and `api_scopes` included: an addon that needs nothing
  beyond its own directories declares `{"daemon": true, "needs": [...], "start": "early"}`, or
  `{}` when it keeps no process running.

## The manifest and the catalogue

**An addon describes itself in one file, `openccu-lite.json`, at the root of its tarball**
(beside `update_script`). The CCU3 and OpenCCU ignore it. At install and update occulited reads
it out of the archive before `update_script` runs and applies it as declared; the accepted copy is
kept root-owned outside the addon's directory. The file in your addon directory is never read
again. The full format is
[manifest-format.md](https://github.com/hobbyquaker/occulited/blob/master/docs/manifest-format.md);
validate against [manifest.schema.json](https://github.com/hobbyquaker/occulited/blob/master/docs/manifest.schema.json).

```json
{
  "format": 1,
  "id": "mosquitto",
  "name": "Mosquitto",
  "description": {"de": "Der MQTT-Broker …", "en": "The MQTT broker …"},
  "homepage": "https://github.com/homematic-community/ccu-addon-mosquitto",
  "licence": "EPL-2.0",
  "release": {"github": "homematic-community/ccu-addon-mosquitto",
              "asset": "mosquitto-{arch}-{version}.tar.gz"},
  "requires": {"architectures": ["armv7l", "aarch64", "x86_64"]},
  "ui": {"icon": "mosquitto/www/icon.svg", "session_header": true},
  "runtime": {"daemon": true, "needs": [], "ports": [1883, 8883]}
}
```

- **Identity:** `format` (1), `id` (the rc.d name), `name`, `description`, `homepage`,
  `licence`, an informational `version`. Texts are `{"de": …, "en": …}` or one string.
- **`release`:** `github` (`owner/repo`), `asset` with `{arch}` and `{version}`, or a per-arch
  `assets` map, and `fallback_asset` for an architecture-independent package. A sibling
  `<asset>.sha256` is verified when present, so publish one ([07](07-updates-and-releases.md)).
- **`requires`:** `architectures`, the oldest `lite` version, `forms` (`sd`, `ova`), and
  `rega: true` for an addon that needs the ReGa. **A manifest without `rega` says the addon runs
  without it**, which replaces the `openccu-lite.ok` marker.
- **`ui`:** `icon`, `logo` (and `_dark` variants) as paths inside the package; `settings_url`
  when your `Config-Url` is not the settings page; `session_header: true` when this version reads
  the session header everywhere the shell opens it (below); `own_updater: true` when it still
  carries an updater of its own.
- **`runtime`**, what the unit is built from:

| Key | Meaning |
| --- | --- |
| `root` | `true` for an addon that genuinely needs root. Shown as unsafe |
| `capabilities` | e.g. `["CAP_NET_BIND_SERVICE"]`, `CAP_NET_RAW`. A confined addon may not declare a root-equivalent one (below) |
| `groups` | supplementary groups, e.g. `["dialout"]`. A confined addon may not declare `occulite` or `root` (below) |
| `data_dirs` | extra directories under `/usr/local/` that are chowned to the addon and writable. `/usr/local/<id>` is taken automatically when it exists |
| `paths` | extra writable paths, not chowned |
| `ports`, `port_info` | ports the daemon listens on, with protocol, TLS and a label. Each is a switch in the firewall, **closed by default** |
| `needs` | `[]`, or any of `rfd`, `hmipserver`, `hs485d`: what the unit waits for. Undeclared means after `rfd` and `HMIPServer` |
| `start` | `"early"`: starts before the interface processes (above) |
| `daemon` | `true` when the rc.d `start` leaves a process running (a broker, a server). The unit is a oneshot that stays *active* either way; with `daemon`, a unit whose processes are all gone shows as *Exited* (red, with *Start* offered and a Status warning) instead of *Completed*, and the system restarts the unit when its daemon ends (above). Leave it out for an addon that only prepares things. The system also learns it once the unit has held a process, but only the declaration covers the very first start |
| `api_scopes` | scopes for the addon's own API token (below) |
| `note` | why the addon needs what it declares, and what it contacts outside the system; shown on the Addons page |

**What a confined addon may not declare** (since `1.0.0-dev.29`): the capabilities that are root
in effect, `CAP_SYS_ADMIN`, `CAP_SYS_MODULE`, `CAP_SYS_RAWIO`, `CAP_SYS_PTRACE`,
`CAP_SYS_CHROOT`, `CAP_SYS_BOOT`, `CAP_DAC_OVERRIDE`, `CAP_DAC_READ_SEARCH`, `CAP_FOWNER`,
`CAP_CHOWN`, `CAP_SETUID`, `CAP_SETGID`, `CAP_SETPCAP`, `CAP_MKNOD`, `CAP_BPF`,
`CAP_MAC_ADMIN`, `CAP_MAC_OVERRIDE` and `CAP_NET_ADMIN` (it can flush the firewall or reroute
the system's traffic), and the groups `occulite` (the privilege helper's group, root by proxy)
and `root`. Such a manifest is **refused at install**: the journal says why, the package installs
as if it carried no manifest, and nothing on the list ever reaches a confined unit. An
addon that truly needs one of them runs as root: `root: true` in the manifest, or the user's
choice on the Services page, shown as *root (unsafe)*. A root addon may declare any of them.

**The catalogue** is one JSON file in the occulited repository,
[`catalog/catalog.json`](https://github.com/hobbyquaker/occulited/blob/master/catalog/catalog.json)
([catalog-format.md](https://github.com/hobbyquaker/occulited/blob/master/docs/catalog-format.md)).
It only says **where** each addon's manifest is: `{"git": "<repository>", "manifest": "<path of
openccu-lite.json in it>"}`, plus `untested: true` for an addon nobody has tried on openccu-lite
yet. To be listed, open a pull request with one entry. For an addon whose author ships no
manifest, the catalogue maintainers keep an adapter manifest under `catalog/manifests/<id>.json`.

The image carries a copy of the catalogue. **Nothing is fetched until the user asks**: *Check for
updates* on the Addons page reads the catalogue, every entry's manifest at its latest release tag,
and the latest releases. A daily check is a switch, off on a fresh system. A catalogue install
resolves the release from the manifest, downloads the asset, checks its `.sha256`, and hands the
archive to the same installer an upload takes.

## Web integration

### How pages are served

- `/addons/<id>/` is your `/usr/local/etc/config/addons/www/<id>` as on a CCU, but lighttpd runs
  as its own user and does not open addon files. **occulited serves the static files**, as its
  own unprivileged user: a link out of your addon's tree answers 404, and a directory answers
  `index.htm`, `index.html`, `index.xhtml` or `default.htm`.
- **Every request under `/addons/` passes a session gate.** Without a live login, lighttpd
  answers with a redirect to `/login`. A settings page that forgot its own check is no longer
  open to the LAN; your CGIs must still check (next section).
- `*.cgi` and `*.ccc` under `/addons/` are **executed by occulited**, not by lighttpd's mod_cgi:
  - the interpreter is `/bin/tclsh`, and the working directory is the script's directory;
  - the CGI runs as the addon user when confined, as root otherwise;
  - the environment has `SERVER_SOFTWARE=occulited`, `HTTPS=on`, `REMOTE_ADDR`, and the usual
    CGI variables;
  - timeout 5 minutes, request body up to 64 MiB;
  - a POST without `Content-Length` arrives as an empty body (the CCU3 and OpenCCU answer 411
    for it, [04](04-webui.md#change-state-only-on-a-post)). Change state only on a POST there
    too;
  - the output is **buffered**, so a streaming or long-polling CGI does not work. Use your own
    server for that;
  - `X-Sendfile:` works for files under `/usr/local/tmp/`, including files your user wrote with
    mode 0600, and nowhere else.
- **Your own HTTP server** is reached through a lighttpd fragment, as in [04](04-webui.md), but
  **ship it as `etc/lighttpd.conf` in your addon's tree** (a rendered file; a template may be
  `.in` and rendered by your scripts). occulited validates it and writes a root-owned copy to
  `/usr/local/etc/config/lighttpd/<id>.conf` at every install and before every lighttpd start; it
  removes its copy when your fragment is gone. Your addon never writes that directory on
  openccu-lite. A fragment that fails the check is refused and the reason written to
  `<id>.conf.rejected`. Allowed: `url.redirect*`, `url.rewrite*`, `url.access-deny`,
  `proxy.server/header/forwarded/balance` to this system only (127.0.0.1, ::1, localhost, or a
  unix socket in your tree), `setenv.*` headers, `alias.url` and `server.errorfile-prefix` inside
  your tree, a few more static and limit settings, and `$HTTP[...]` conditions. Not allowed:
  `include`, `include_shell`, `$SERVER["socket"]`, `cgi.*`, `magnet.*`, `auth.*`, `ssl.*`,
  variables. WebSockets pass. Keep the proxied path under `/addons/`, otherwise the gate and the
  session header do not apply to it.

### Sessions

Session ids on openccu-lite are 26 characters (`[A-Z2-7]`). A login sets two cookies with the
same id (`HttpOnly`, `SameSite=Lax`): the **session cookie** `occulite_session`
(`__Secure-occulite_session` over HTTPS) with `Path=/api`, which reaches the API and nothing
else, and the **gate cookie** `occulite_gate` (`__Secure-occulite_gate`) with `Path=/addons/`,
which opens the addon pages and is no credential on the API. So no request to your pages, CGIs or
proxied server carries the API's cookie. (Up to `1.0.0-dev.30` there was one cookie,
`occulite_session` at `Path=/`; the split is in the images after it.)

**`?sid=@xxxxxxxxxx@` still works as a legacy alias.**

- The ten characters are *not* the session. The gate and the `tclrega.so` shim accept them;
  occulited's API never does.
- The system appends the alias only for addons whose manifest does not declare
  `ui.session_header`, and never for a proxied frontend.
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
→ {"authenticated": true, "sid": "...", "user": "...", "level": "administer", "role": "admin", ...}
```

`level` is one of `read`, `operate`, `configure`, `administer`; `role` (`admin` for
`administer`, else `user`) is still answered for older clients.

Rules for the header:

- **Trust it only on openccu-lite.** A CCU forwards a client's header untouched, and your loopback
  port is open to every local process. Apply the detection rule above first and validate every
  value against `/state`.
- Accept a session only when `/state` answers `authenticated: true` with the same `sid`. Refuse
  API tokens there.
- Fall back to `?sid=` and the shim when there is no header.
- Admin-only settings pages check `role` (or `level`).

[templates/lib/session.tcl](../templates/lib/session.tcl) does all of this. It is Tcl 8.2 safe,
and on a CCU it behaves exactly as before. For Node-RED, set `adminAuth.tokenHeader:
'x-occulite-session'`, with a `tokens()` function that asks `/state`.

Once a release reads the header everywhere the shell opens it, set `"ui": {"session_header":
true}` in that release's manifest; the shell then opens it without `?sid=`. Keep accepting
`?sid=`, because every CCU still sends it.

An addon that logs users in itself (formerly through ReGa's user objects and UDP 1998) uses
`POST /api/auth/v1/login {"username","password"}`.

### Requests from other sites

A browser sends a `SameSite=Lax` cookie on a top-level navigation from another site, and on every
request from the *same site*, which includes another port of this host. So the system checks
where a request under `/addons/` comes from when its only credential is the cookie (since
`1.0.0-dev.28`; lighttpd's gate and occulited's CGI runner apply the same rule):

- **`Sec-Fetch-Site: cross-site` or `same-site`:** refused with `403` and
  `{"error":"cross-site",…}`, except a top-level navigation (a `GET` of a document). That one
  opens your page **without its query string** (a `302` to the bare path), so a link from
  elsewhere cannot carry `?cmd=…`.
- **`same-origin` or `none`** (a typed URL, a bookmark) passes.
- **A browser without `Sec-Fetch-*` headers:** a `GET` passes; a `POST`, `PUT` or `DELETE`
  passes only when its `Origin` (else its `Referer`) names this system, or when it sends
  neither.
- **Not affected:** a request accepted by its `?sid=`, which another site cannot know; API calls
  with a header credential (a token, or the session as `Authorization: Bearer`, which is what your
  backend sends with the `X-Occulite-Session` value); your own pages calling your own paths.

Each refusal is a journal line that names the addon. What follows for an addon:

- **Change state only on a POST** ([04](04-webui.md#change-state-only-on-a-post)), never on a
  `GET` with a query. The system's redirect is a backstop, not the protection: on a CCU there is
  none.
- **A page your own server delivers on its own port** (Node-RED on `:1880`, say) that posts to
  `/addons/<id>/…` with the cookie is refused (`same-site`). Call from the page's own origin, or
  from your backend with the header credential.
- **A page that calls the system API from the browser** (images after `1.0.0-dev.30`): the
  request carries the session cookie (its path is `/api`), and a `POST`, `PUT`, `PATCH` or
  `DELETE` on that cookie alone also needs the header `X-Occulite-Request` with any value, or it
  is refused with `403 request-header`. A call with `Authorization: Bearer` needs none.

### Menu: settings page vs. frontend

- **Settings page**: your `Config-Url:` from `info` (and `hm_addons.cfg`). It is shown as the
  *Settings* button on the Addons page and framed at `/addon-settings/<id>`.
  - If your `Config-Url` is not the settings page (Homematic Manager's hands over to its app),
    let `update_script` write the right one on openccu-lite (the detection rule above), or name
    it in the manifest's `ui.settings_url`.
- **Frontend**: a lighttpd fragment that proxies a plain path under `/addons/` makes the addon an
  entry in the addon menu; the user can pin it as a tab. For anything the parser cannot read,
  declare the entry explicitly in `/usr/local/etc/config/nav.d/<id>.json`:

```json
{"id": "<id>", "label": {"de": "…", "en": "…"}, "icon": "/addons/<id>/icon.svg",
 "href": "/addons/<id>/", "target": "iframe", "order": 50, "keep_alive": false}
```

- **Embedding.** Pages are embedded as same-origin iframes, and up to three stay loaded while
  other pages show, so a WebSocket survives a switch.
  - The shell appends `?theme=system|light|dark&lang=de|en`, sets the `ol-theme` and `ol-lang`
    cookies, and posts `{type: "openccu-lite:theme", theme, lang}` when the user changes either.
    Follow them if you can.
  - A page that forbids framing (`X-Frame-Options`, `frame-ancestors`) is opened in a new tab
    instead.
- The icon and logo the Addons page, the menu and the tab bar show come from the manifest's `ui`
  block.

## APIs an addon can use

- **Radio interfaces.** Read the URLs from `/etc/config/InterfacesList.xml`, don't hard-code
  2001/2010. On openccu-lite they are loopback ports (32001, 32000, 32010, VirtualDevices
  `127.0.0.1:39292/groups`). Callbacks to your listener on 127.0.0.1 work. The CCU's lighttpd
  proxy ports (2001, 2010, 9292, their TLS twins) exist only when the user switches classic RPC
  on for the LAN; clients off the system use lite-rpc.
- **lite-rpc**, `/api/rpc/v1` (the lite-rpc section of
  [system-api.md](https://github.com/hobbyquaker/occulited/blob/master/docs/system-api.md)): the
  interface processes through the system's web server with a token, for a program on or off the
  system.
  - Calls: `POST /xmlrpc/{interface}` (XML-RPC) or `POST /json/{interface}` (JSON-RPC 2.0).
    Each method needs a scope tier (`rpc:read`, `rpc:operate`, `rpc:configure`, `rpc:admin`);
    `init` is never forwarded. In JSON, `{"double": n}` sends a `double` whatever `n` looks like
    (a `FLOAT` datapoint written as `1`).
  - Events: `GET /events` (Server-Sent Events) or `GET /events/ws` (WebSocket) instead of a
    callback server, with resume by `Last-Event-ID` and a `resync` when the buffer (5 minutes)
    was not enough.
  - **The state store:** `GET /state` answers the last value of every datapoint the system keeps
    (the service datapoints and what the app's cards draw) with `ts`, `lc` (since when) and
    `confirmed`: one read at start instead of a `getParamset` sweep. Open the stream with its
    `event_id` and nothing is lost in between.
  - **The history:** `GET /history?interface=&address=&datapoint=` answers the last 500 rows of
    one series, for the datapoints on the system's list.
- **Metadata API**, `http://127.0.0.1/api/meta/v1`. This is the replacement for names, rooms
  and functions from ReGa.
  - **Detection:** `GET /version` → `{"api":"meta","version":1,…}` without authentication.
    Anything else (404, HTML) means a CCU. Its `capabilities` object says what else this system
    offers (`pairing`, `state`, `history`, the API majors, `json_double`); treat a missing key as
    absent.
  - **Reading:** `GET /snapshot`, `/objects[?enum=room/eg]`, `/objects/{ref}`, `/enums`,
    `/enums/{enum}/tree`.
  - **Writing:** `PATCH /objects/{ref}` for the name, the enums, and your own `meta.<id>`
    namespace; `POST /objects:bulk`.
  - **Change events:** `GET /events/sse` (Server-Sent Events, `?since=<revision>`, a
    `{"kind":"resync"}` answer means reload the snapshot).
  - **Objects** are keyed by `<interface>.<address>` (`BidCos-RF.JEQ0230153:1`). There are no
    numeric ids.
  - **Rooms and functions** are path trees (`room/eg/wohnzimmer`).
  - The API is frozen for version 1. The full reference is
    [meta-api.md](https://github.com/hobbyquaker/occulited/blob/master/docs/meta-api.md), the
    document format [meta-format.md](https://github.com/hobbyquaker/occulited/blob/master/docs/meta-format.md),
    and the mapping from ReGa
    [porting-from-rega.md](https://github.com/hobbyquaker/openccu-lite/blob/main/docs/porting-from-rega.md).
- **Credentials**, sent as `Authorization: Bearer …`:
  - `/usr/local/etc/occulite/local-token` is readable by every addon and has scope `meta:read`
    only;
  - your addon's own token, `/run/occulite/addon-tokens/<id>.api`, carries the scopes from
    `runtime.api_scopes`. It is never `*`, `auth:admin`, `power` or `backup`;
  - a request can use the user's session from the header;
  - a user can create an API token on the system and paste it into your configuration;
  - **client pairing**, for a program that runs elsewhere in the local network (or an addon's
    off-system mode): it asks for access per area (`POST /api/auth/v1/pairing/request`, devices, names and system at
    a level each), shows a six-digit code, and an administrator who sees the same code on the
    Status page approves it. The program then gets an ordinary API token. An administrator can
    narrow it later; the program rotates it itself with `POST /api/auth/v1/tokens/self/rotate`.

  A `403` names the missing scope. Scopes include `meta:read`, `meta:write`, `system:read`,
  `logs:read`, `system:write`, `addons:write`, `led`, and for lite-rpc `rpc:read`,
  `rpc:operate`, `rpc:configure`, `rpc:admin`.
- **System API**, `/api/system/v1`
  ([system-api.md](https://github.com/hobbyquaker/occulited/blob/master/docs/system-api.md)).
  Useful routes: the journal of your unit (`GET /log?unit=addon-<id>`, scope `logs:read`), the
  addon list, and the status LED.

**Gone, with no emulation:**

- ReGaHSS and its ports 8181/8183, `rega.exe`/`tclrega.exe`, HM-Script, `dom.*`;
- system variables, programs, favourites, service-message and alarm variables;
- the WebUI JSON-RPC `/api/homematic.cgi` (`Session.login`, `Device.listAll`, `Interface.*`);
- `/config/*.cgi`;
- `checkAddonUpdates.sh`, `updateAddonConfig.tcl`, `hm_autoconf`;
- `checkInternet` and `/var/status/hasInternet`: the system contacts the internet only when the
  user asks it to;
- `libfirewall.tcl` and `firewall.conf`.

## Logs, backups, firewall, updates

- **Logs.** Everything your unit writes to stdout and stderr lands in the journal as
  `addon-<id>`, and so do `logger -t <tag>` lines. There is no `/var/log/messages` to grep.
  - Log to stdout or `logger`, and don't write log files that grow on the SD card.
  - Your settings page cannot run `journalctl` as the addon user. Link the system's log page
    (`/system/log?unit=addon-<id>`) or read `GET /api/system/v1/log` with a `logs:read` token.
- **Backups** are OpenCCU's `createBackup.sh` and honour `.nobackup` ([06](06-system-integration.md)):
  the contents of a tagged directory are left out, as on a CCU. After a restore an addon whose
  program was in such directories comes back with its settings and data but without its program.
  - From the images after `1.0.0-dev.30` such an addon is **not started**: the unit's
    `ExecCondition` skips it (inactive, not failed, one journal line) when the rc.d script behind
    the wrapper is missing or points to nothing, or when every tagged program directory holds
    nothing but its tag (`tmp`, `cache` and what is under `var` do not count).
  - The Addons page and Status say "installed before the restore; reinstall it", with a
    *Reinstall* button where the catalogue knows the addon. Nothing is reinstalled
    automatically.
  - So tag your **program** directories, never the ones with settings or data. An addon that
    wants its program in every backup leaves its directories untagged (RedMatic's
    `ccuBackup: full` does).
- **Firewall.**
  - occulited owns it: one rule list, on a fresh system with the default policy DROP; the web
    ports, and SSH while it is enabled, are open from local networks.
  - Declared ports appear as switches, closed until the user opens them.
  - A confined addon cannot change the firewall. Show the state if you like, and tell the user
    where to open the port.
  - The user's own rules may name port ranges and UDP; a manifest declares single ports.
- **monit and cron.** There is no monit; systemd tracks the unit. crond reads
  `/usr/local/crontabs/root` and runs as root, so keep scheduling inside the addon.
- **Updates.** Installs and updates go through the catalogue, which runs your own
  `update_script`.
  - **Hide your own self-updater on openccu-lite** ([07](07-updates-and-releases.md)). It
    bypasses the unit and the ownership steps. Show a line pointing to the system's Addons page
    instead, and answer your update CGI's start command with 403 there. Set `ui.own_updater`
    for a release that still carries one.
  - `Update:` and your `update_check.cgi` may stay. The system's own update check runs when the
    user asks, or daily when the user switched that on.

## Not final yet

As of `1.0.0-dev.28`, these may still change:

- signed releases, and catalogue installs refused without a valid signature.

Build against what is described above as current, and check this chapter again before a release.
