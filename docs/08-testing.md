# 08 Testing

Three layers, cheapest first. All of them exist in ccu-addon-mosquitto and RedMatic and can be copied;
the simulator layer (1b) exists in node-red-contrib-ccu and hm2mqtt.js.

## 1. Unit tests without a CCU

- Shell: `sh -n` and `bash -n` on every script, `shellcheck -S error -s sh` for the addon scripts
  (they run on busybox ash) and `shellcheck -S error` for bash build scripts.
- Tcl: no tclsh on the build machine is needed for syntax, but there is no substitute for running
  the CGIs on a CCU3 with Tcl 8.2 ([04](04-webui.md)).
- Browser JavaScript: structure the page script so the pure logic (a config parser, version
  comparison) is exported when `document` is undefined, then test it with `node --test`
  (`test/parser.test.js` in the Mosquitto addon has 18 cases, no framework).

Node.js is the test tool of choice here, but only as a tool: nothing of it ships in the addon.

## 1b. Addons that talk to the CCU: test against hm-simulator, not against a CCU

Addons that are *clients* of the CCU (Node-RED nodes, MQTT bridges, anything that does `init`
on the RPC interfaces or runs ReGa scripts) have a second layer that needs no CCU either.
The CCU offers three things such an addon talks to: `rfd` (BidCos-RF, binrpc on port 2001),
`HmIPServer` (xmlrpc on port 2010) and ReGaHSS (script execution over HTTP on port 8181).
[hobbyquaker/hm-simulator](https://github.com/hobbyquaker/hm-simulator) (npm) fakes them:

- binrpc on 2001 and xmlrpc on 2010; incoming `init`, `ping`, `system.listMethods`,
  `getParamsetDescription`; outgoing `listDevices`, `newDevices`, `deleteDevices`, `event`,
  `system.multicall`;
- devices and their paramsets from JSON files (`simulator-data/`), behaviour scripts that press
  buttons or open windows on a timer (`simulator-behaviors/`), and an in-process API to inject
  events from a test: `hmSim.api.emit('setValue', 'rfd', 'BidCoS-RF:1', 'PRESS_SHORT', true)`;
- a ReGa mock (`hmSim.regaSim`, port 8181) with variables, programs, rooms, functions and
  channel names whose state the test can change directly before it triggers a poll.

Use it in-process (`new HmSim(options)` in `before`, `close()` in `after`) rather than as a
separate process, so a test can manipulate simulator state and wait for the resulting message.
Delete the cache files the client writes (`ccu_*.json`: devices, paramsets, ReGa names, values)
before each run, or a test passes on stale data. Its README says it "is far away from a complete
simulation": no `MASTER`/`LINK` paramsets, no error responses, no service messages, only the
devices its authors needed. The plan (September 2026) is to have it extended substantially with
AI help: more devices and paramset types, proper error responses, service messages, a scriptable
ReGa side. Check the repository before writing a private mock, and contribute missing pieces
there rather than into your addon's `test/`.

Two projects show what to test at this layer and how, and are worth a look as prior art before
writing the first test:

- [node-red-contrib-ccu](https://github.com/rdmtc/node-red-contrib-ccu) `test/`: mocha,
  should.js and `node-red-node-test-helper` against hm-simulator. `utils.js` builds the simulator
  options (devices, ReGa data, ports, behaviour scripts) and removes the cache files;
  `rpc_spec.js` covers `setValue`, events on several channels, both interfaces, the `cache` and
  `change` flags; `regahss_spec.js` changes `regaSim.variables` and asserts the next poll;
  `context_spec.js` the Node-RED context.
- [hm2mqtt.js](https://github.com/hobbyquaker/hm2mqtt.js) `test/`: node:test, no framework, no
  simulator process. `rpc.test.js` injects fake binrpc/xmlrpc client and server objects and asserts
  the whole subscription lifecycle: `init` with URL and id, unsubscribe with an empty URL,
  `listDevices` answering the device list, `event` and `system.multicall`, `ping` after half the
  timeout, re-`init` after 60 s without an event, one warning and a retry every 30 s when `init`
  fails, CUxD as binrpc on port 8701. `rega.test.js` uses a `fakeRega()` returning channels, rooms,
  functions, variables (with `valueType` and `enum`) and programs, and asserts change detection
  across polls. `cast.test.js`, `values.test.js` and `interfaces.test.js` cover type casting,
  `roles.test.js`/`hadiscovery.test.js` the derived metadata, `e2e.test.js` the package.

The checklist that falls out of both: every RPC method you call and every one you serve; the
subscription lifecycle (init, unsubscribe, ping, re-init on silence, retry on failure); the
paramset description cache on disk and the ReGa name cache (stale, missing, corrupt); type
casting per `TYPE` (`BOOL`, `ACTION`, `ENUM` with `VALUE_LIST`, `FLOAT`/`INTEGER` with
`MIN`/`MAX`, `STRING`), `WORKING`/`DIRECTION` hints in a multicall; ReGa script results (the
JSON-in-`WriteLine` convention, timestamps, enum values) and what happens when ReGa answers slowly
or not at all. Wire-level simulator and in-process fakes are complementary: the fakes are fast
and deterministic for lifecycle and error paths, the simulator catches serialisation and
protocol mistakes the fakes cannot see.

## 2. Container end-to-end test that replays the firmware installer

A Debian container is close enough to OpenCCU for the whole install path when it gets what the
CCU has: busybox as `/bin/sh` (`ln -sf /bin/busybox /bin/sh`), `busybox syslogd -O
/var/log/messages`, `tcl` for `update_addon` and the CGIs' helpers, `curl`, `openssl`, `iproute2`,
`procps`, a tmpfs on `/media`, the directories `/usr/local/tmp`, `/usr/local/etc/config/rc.d`,
`/usr/local/etc/config/addons/www`, `/etc/config` and a CCU-style `server.pem` (certificate and
key concatenated). Start it with `--init` (a reaping pid 1, or stopped daemons linger as zombies
that `pgrep` still finds) and `--privileged` when you want bind mounts for USB-stick tests.
Then replay `install_addon`:

```sh
dir=$(mktemp -d -p /usr/local/tmp)
tar -C "$dir" --no-same-owner --no-same-permissions -xf /dist/addon.tar.gz
(cd "$dir" && ./update_script HM-RASPBERRYMATIC); rc=$?
rm -rf "$dir"
```

and assert: exit 10 on the fresh install, links and `hm_addons.cfg` entry present, service
starts and answers, exit 0 on the update with the service restarted and user data preserved,
your migrations from old layouts, the self-update worker against a local `busybox httpd`
serving `dist/`, stop, uninstall leaves nothing behind. In the Mosquitto addon this is
`test/e2e.test.js` (node:test): the test starts the container itself, runs the steps through
`docker exec` and checks the broker with the `mqtt` npm client over published ports, so every
check is an assertion rather than a grep. A shell skeleton of the same replay is in
[templates/test/e2e-replay.sh](../templates/test/e2e-replay.sh). It found real bugs before any
hardware was touched: Mosquitto 2.x refusing anonymous clients after a migration, a
Windows-style `install` helper, a `--test-config` that saved an empty database.

## 2b. The web UI in the same container

The CGIs and the settings page can be tested for real without a CCU: install `lighttpd` and
`tcl-dev`/`gcc` in the container, add the firmware's CGI rules (`cgi.assign .cgi -> tclsh`,
`/addons` from `/usr/local/etc/config/addons/www`, X-Sendfile for `/usr/local/tmp`, the init
script's PATH with `/sbin`), compile a **stub `tclrega.so`** whose `rega_script` answers
`STDOUT <output> sessionId {} httpUserAgent {}` and treats a session id as valid when it matches a
file, stub `/lib/libfirewall.tcl` with the same procedures writing to `/tmp`, and put a fake
`curl` first in PATH that answers GitHub API lookups from a file. Then:

- call every CGI with every command and error path over HTTP (invalid session, missing
  parameters, invalid input, unknown command);
- drive the page with headless chromium (playwright) and verify every setting against the running
  daemon: listeners, certificate sources, users with write-only passwords, ACL, log types,
  persistence location with a bind-mounted stick, firewall, bridges, a failed start's error
  display, the self-update through the page (a repacked package with a higher version served by
  `busybox httpd`), tabs, an expired session, a failing CGI. Dispatch DOM `click()` and `change`
  events from `page.evaluate` rather than `page.click` (actionability checks hang on some headless
  builds), have the page count its saves so tests wait for the right one, and remember that
  buttons stay disabled while a command runs;
- measure browser coverage of the page script with `page.coverage` and fail below a threshold.
  Chromium's precise coverage only reports scripts that are still alive, so snapshot before every
  reload and merge the snapshots (largest ranges first, then OR the pages).

The Mosquitto addon's `test/webui.test.js` and `test/lib/` are the reference (24 cases, about
2.5 minutes, 94 % coverage of the page script). What the container still cannot test: Tcl 8.2,
the CCU3 chroot install, the real `tclrega.so`, real USB media.

## 3. Real hardware

Have one of each: original CCU3 firmware on CCU3 hardware, OpenCCU on x86_64 (a VM is fine),
OpenCCU on an aarch64 Pi. Checklist per box:

- Manual install over ssh ([02](02-package-and-install.md)), `rc.d` start, syslog lines, ports.
- A smoke script per box (status, pub/sub with the bundled clients, TLS, the settings page and
  status CGI with a real session) that runs in one minute for all boxes, for every release.
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
