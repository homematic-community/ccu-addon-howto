# 08 Testing

Three layers, cheapest first. All of them exist in ccu-addon-mosquitto and RedMatic and can be copied.

## 1. Unit tests without a CCU

- Shell: `sh -n` and `bash -n` on every script, `shellcheck -S error -s sh` for the addon scripts
  (they run on busybox ash) and `shellcheck -S error` for bash build scripts.
- Tcl: no tclsh on the build machine is needed for syntax, but there is no substitute for running
  the CGIs on a CCU3 with Tcl 8.2 ([04](04-webui.md)).
- Browser JavaScript: structure the page script so the pure logic (a config parser, version
  comparison) is exported when `document` is undefined, then test it with plain `node`
  (`test/parser.test.js` in the Mosquitto addon has 18 cases, no framework).

## 2. Container end-to-end test that replays the firmware installer

A Debian container is close enough to OpenCCU for the whole install path when it gets what the
CCU has: busybox as `/bin/sh` (`ln -sf /bin/busybox /bin/sh`), `busybox syslogd -O
/var/log/messages`, `tcl` for `update_addon` and the CGIs' helpers, `curl`, `openssl`, `iproute2`,
`procps`, the directories `/usr/local/tmp`, `/usr/local/etc/config/rc.d`,
`/usr/local/etc/config/addons/www`, `/etc/config` and a CCU-style `server.pem` (certificate and
key concatenated). Then replay `install_addon`:

```sh
dir=$(mktemp -d -p /usr/local/tmp)
tar -C "$dir" --no-same-owner --no-same-permissions -xf /dist/addon.tar.gz
(cd "$dir" && ./update_script HM-RASPBERRYMATIC); rc=$?
rm -rf "$dir"
```

and assert: exit 10 on the fresh install, links and `hm_addons.cfg` entry present, service
starts and answers, exit 0 on the update with the service restarted and user data preserved,
your migrations from old layouts, the self-update worker against a local `busybox httpd`
serving `dist/`, stop, uninstall leaves nothing behind. This is what runs in CI on every push
([template](../templates/test/e2e-replay.sh),
[Mosquitto e2e-inner.sh](https://github.com/homematic-community/ccu-addon-mosquitto/blob/master/test/e2e-inner.sh),
[RedMatic e2e-inner.sh](https://github.com/rdmtc/RedMatic/blob/master/test/e2e-inner.sh)).
It found real bugs before any hardware was touched: Mosquitto 2.x refusing anonymous clients
after a migration, a Windows-style `install` helper, a `--test-config` that saved an empty database.

What the container cannot test: Tcl 8.2, the CCU3 chroot install, the CCU session (`tclrega.so`
needs ReGaHSS), lighttpd's environment, the firewall library, real USB media.

## 3. Real hardware

Have one of each: original CCU3 firmware on CCU3 hardware, OpenCCU on x86_64 (a VM is fine),
OpenCCU on an aarch64 Pi. Checklist per box:

- Manual install over ssh ([02](02-package-and-install.md)), `rc.d` start, syslog lines, ports.
- Every CGI through lighttpd with a real session from the JSON API, and once with a wrong sid.
- The settings page in a headless browser: playwright-core against `http://ccu/addons/<name>/settings.cgi?sid=@..@`,
  reading the DOM after each action and collecting `pageerror`, console errors and HTTP >= 400.
  On some chromium builds playwright's actionability checks hang; dispatch DOM `click()` and
  `change` events from `page.evaluate` instead of `page.click`.
- The WebUI upload path: on OpenCCU `/bin/install_addon` with the archive at
  `/usr/local/tmp/new_addon.tar.gz` (exit code as the WebUI would show it); on the CCU3 the real
  upload with its reboot at least once per release cycle.
- Update from the previous public release (install it first, then your package) and, if the
  layout changed, from the oldest version still in use.
- The self-update worker against a package served by the CCU's own lighttpd (drop it into your
  www directory and point the worker's base URL at `http://127.0.0.1/addons/<name>/test/`);
  the CCU cannot usually reach your development machine.
- Uninstall through the WebUI operation, then reinstall.
- Keep addresses and credentials of the test systems out of the repository.

## Reading the box

Useful one-liners for a session on a CCU:

```sh
cat /VERSION; uname -m; /lib/libc.so.6 | head -1; echo 'puts [info patchlevel]' | tclsh
ls /usr/local/etc/config/rc.d; cat /usr/local/etc/config/hm_addons.cfg
grep <name> /var/log/messages | tail; netstat -tlnp
cd /usr/local/addons/<name>/www && QUERY_STRING='cmd=status' tclsh service.cgi   # run a CGI by hand
```
