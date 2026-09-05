# 03 The rc.d script

`/usr/local/etc/config/rc.d/<name>` is the only thing the firmware knows about your addon after
the installation. It is a POSIX sh script called with one argument.

## Who calls it when

| Caller | Call | When |
| --- | --- | --- |
| `/etc/init.d/S55InitAddons` | `run-parts -a init /etc/config/rc.d` | early in the boot, before the Homematic services; `HM_MODE` must be `NORMAL`, skipped in safe mode. OpenCCU runs `/usr/local/etc/rc.prelocal` first. |
| `/etc/init.d/S98StartAddons` | `run-parts -a start /etc/config/rc.d` | at the end of the boot, after ReGaHSS, rfd, HmIP server; sources `/etc/profile.d/*.sh` and `/usr/local/etc/profile.d/*.sh` first; then `/usr/local/etc/rc.local`. Skipped in safe mode. |
| `S98StartAddons stop` | `run-parts -a stop /etc/config/rc.d` | at shutdown and reboot |
| `cp_software.cgi` (Zusatzsoftware page) | `<script> info` and `<script> info.de` / `info.en` | every time the page is rendered |
| `cp_software.cgi` | `<script> restart`, `<script> uninstall` | the buttons in the *Operations* column; after `uninstall` the WebUI deletes the script |
| OpenCCU `checkAddonUpdates.sh` | `<script> info` | periodically, to show update notices |
| your own settings page | `start`, `stop`, `restart`, `reload`, `status` | through your CGIs |

`run-parts` gives the calls no terminal; output goes nowhere. Both init scripts set
`oom_score_adj` 100 for the addons on OpenCCU, so under memory pressure the kernel prefers to
kill addons over Homematic services; raise it further for a heavy service (RedMatic sets 800 for
Node-RED).

Sources: `S55InitAddons`, `S98StartAddons`
([OpenCCU](https://github.com/OpenCCU/OpenCCU/tree/master/buildroot-external/overlay/base/etc/init.d),
same logic in the CCU3 firmware), `cp_software.cgi` ([eq-3/occu](https://github.com/eq-3/occu/blob/master/WebUI/www/config/cp_software.cgi)),
[checkAddonUpdates.sh](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base-openccu/bin/checkAddonUpdates.sh).

## The info output

`get_info` in `cp_software.cgi` runs `<script> info.<lang>` (the WebUI user's language, `de` or
`en`) and then `<script> info`, and parses every line matching `^([^:]+): (.*)$` into an array;
repeated keys are joined with newlines. Unknown commands must therefore exit quietly (no usage
text on stdout: it would be parsed too).

| Key | Meaning |
| --- | --- |
| `Name:` | **Mandatory.** Without it the addon is not listed at all. Also the sort key. |
| `Version:` | Shown as installed version, appended as `&version=` to the update check. |
| `Info:` | HTML shown in the info column; several lines allowed (logo `<img>`, links). |
| `Update:` | URL of your update check CGI, e.g. `/addons/<name>/update_check.cgi` ([04](04-webui.md)). |
| `Config-Url:` | URL of your settings page; the WebUI opens `<url>?sid=<session>` in a new window. |
| `Operations:` | Space separated subset of `restart uninstall`; each becomes a button. |

A `restart` operation only makes sense for a service; `uninstall` should always be offered.
Everything after `info` must be cheap: the page runs it for every addon on every render.

## Commands

- `init` (from S55): create runtime directories, re-apply patches to the read-only root if you
  really must, generate config that depends on the machine. Keep it fast. Many addons do nothing here.
- `start`: refuse if already running; `cd /`; start the daemon detached (`start-stop-daemon -S -b
  -m -p /var/run/<name>.pid --exec ...` or your own loader); log a start line with `logger`.
  Since boot order is not guaranteed for network readiness, wait a few seconds after a fresh boot
  if your service binds early (RedMatic sleeps 30 s when `/proc/uptime` is below 120 s).
- `stop`: signal the pid, wait, `kill -9` as a last resort, remove the pid file. Return 1 when
  nothing was running (callers such as `update_script` ignore it).
- `restart`, `reload` (SIGHUP where the daemon supports it), `status` (a JSON line is handy for
  your settings page): your own conventions.
- `uninstall`: [02](02-package-and-install.md).

The complete script used by ccu-addon-mosquitto is in
[templates/rc.d-script](../templates/rc.d-script); RedMatic's `bin/redmatic` is the more
elaborate variant with monit, telemetry and IPv6 handling.

## Safe mode and HM_MODE

`/etc/config/safemode` (set from the WebUI's recovery options) skips the addon init and start
completely; the CCU3 firmware deletes the flag after one boot. `HM_MODE` other than `NORMAL`
(e.g. the HmIP LAN gateway mode) skips addons as well. Do not fight this: a user in safe mode
wants your addon off.
