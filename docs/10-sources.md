# 10 Sources

Everything in this handbook was either read from a running firmware or from the sources below.
Firmware facts were verified on original CCU3 firmware 3.89.8 (CCU3 hardware) and OpenCCU
3.89.8.20260719 (x86_64 ova and Raspberry Pi 4) in September 2026.

## Firmware sources (OpenCCU, formerly RaspberryMatic)

Repository: [OpenCCU/OpenCCU](https://github.com/OpenCCU/OpenCCU) (the former `jens-maus/RaspberryMatic`).

- [buildroot-external/overlay/base/bin/install_addon](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/bin/install_addon): the live installer, exit codes 101 to 106, sha256 check, `ldconfig`.
- [buildroot-external/overlay/base/etc/init.d/S55InitAddons](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/etc/init.d/S55InitAddons) and [S98StartAddons](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/etc/init.d/S98StartAddons): `run-parts -a init|start|stop /etc/config/rc.d`, safe mode, `HM_MODE`, profile.d, rc.local, `oom_score_adj`, monit link cleanup.
- [buildroot-external/overlay/base/etc/init.d/S06InitSystem](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/etc/init.d/S06InitSystem): `/usr/local/tmp` handling, `.nobackup` there.
- [buildroot-external/overlay/base/etc/lighttpd/conf.d/cgi.conf](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/etc/lighttpd/conf.d/cgi.conf) (`.cgi` to `/bin/tclsh`, X-Sendfile for `/usr/local/tmp`) and [webui.conf](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/etc/lighttpd/conf.d/webui.conf) (`/addons` bypasses the WebUI proxy).
- [buildroot-external/overlay/base/lib/libfirewall.tcl](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/lib/libfirewall.tcl): `Firewall_loadConfiguration`, `Firewall_USER_PORTS`, `Firewall_MODE`, `Firewall_saveConfiguration`, `Firewall_configureFirewall`, MOST_OPEN vs RESTRICTIVE.
- [buildroot-external/overlay/base-openccu/bin/updateAddonConfig.tcl](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base-openccu/bin/updateAddonConfig.tcl) (by MDZ, CCU-Historian): the `hm_addons.cfg` command line wrapper.
- [buildroot-external/overlay/base-openccu/bin/checkAddonUpdates.sh](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base-openccu/bin/checkAddonUpdates.sh): how OpenCCU polls the `Update:` URLs.
- [buildroot-external/overlay/base-openccu/bin/createBackup.sh](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base-openccu/bin/createBackup.sh): `tar --exclude-tag=.nobackup`.
- [buildroot-external/patches/occu/0034-WebUI-Addon-Config.patch](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/patches/occu/0034-WebUI-Addon-Config.patch): adds `RemoveConfigPage` to the HomeMatic Tcl package.
- [buildroot-external/patches/occu/0031-WebUI-Fix-FileUpload](https://github.com/OpenCCU/OpenCCU/tree/master/buildroot-external/patches/occu/0031-WebUI-Fix-FileUpload): OpenCCU's patched `cp_software.cgi`.

## Firmware sources (eQ-3 OCCU)

Repository: [eq-3/occu](https://github.com/eq-3/occu), the published parts of the CCU firmware.

- [WebUI/www/config/cp_software.cgi](https://github.com/eq-3/occu/blob/master/WebUI/www/config/cp_software.cgi): the Zusatzsoftware page. `get_info` (parses `Key: value` from `<script> info.<lang>` and `<script> info`), `OPERATIONS` (`restart`, `uninstall`), the update check JavaScript (`?cmd=check_version&version=`, `?cmd=download&version=`), `action_install_start` (`new_addon.tar.gz`, `.doAddonInstall` + reboot on the CCU3), `action_install_go` (exit code handling), `action_operation` (`rm -rf $script` after uninstall, `/var/log/addon-uninstall-error.log`).
- [arm-gnueabihf/packages-eQ-3/WebUI/lib/tcl8.2/homematic/homematic.tcl](https://github.com/eq-3/occu/blob/master/arm-gnueabihf/packages-eQ-3/WebUI/lib/tcl8.2/homematic/homematic.tcl): `::HomeMatic::Addon::AddConfigPage`, `GetAll`, the `hm_addons.cfg` format (`array get`).
- Not on GitHub but read on the CCU3 firmware 3.89.8: `/bin/install_addon` (chroot installer), `/etc/init.d/S00InstallAddon` (runs it in `stop()`), `/etc/lighttpd/conf.d/proxy_normal.conf`, `/lib/tcl8.2/homematic/homematic.tcl`, `/lib/libfirewall.tcl`, `/www/config/cp_software.cgi`, `/www/config/cp_maintenance.cgi`.

## openccu-lite

Repository: [hobbyquaker/openccu-lite](https://github.com/hobbyquaker/openccu-lite).
Chapters [11](11-openccu-lite.md) and [12](12-porting-to-openccu-lite.md) were read from its
sources and its addon documentation in September 2026 (`1.0.0-dev.1`), and checked on an x86_64
OVA and a Raspberry Pi 4:

- the addon unit generator and the rc.d wrapper;
- occulited's addon policy (the confinement drop-in), its CGI runner, the ReGa and ELF scans,
  and the menu parser;
- the lighttpd session gate;
- the `tclrega.so` shim;
- the metadata, system and auth API references;
- the addon catalogue format.

Ported addons that show the result:

- RedMatic 9.4+ (header login for the Node-RED editor, `/api/auth/v1/login`, the journal as a
  log fallback);
- ccu-addon-mosquitto 2.1.2+2 (pid file and log paths when not root);
- Homematic Manager (header auth, a data directory outside the addon tree, an admin-only
  settings page);
- hm2mqtt.js (the metadata provider next to the ReGa one).

## Example addons

- [homematic-community/ccu-addon-mosquitto](https://github.com/homematic-community/ccu-addon-mosquitto): Mosquitto 2.1, source build in Alpine containers, patchelf, settings page with listeners, TLS, users, bridges, firewall, persistence on USB, self-update, e2e and parser tests, automatic releases. Its `roadmap-archive/` records every finding with dates.
- [rdmtc/RedMatic](https://github.com/rdmtc/RedMatic): Node-RED, Node.js 24 from Alpine on armv7l, bundled git, monit, telemetry, safe mode, progress-bar self-update, wiki. `HANDOFF.md` and `roadmap-archive/` document the 2026 modernisation.
- [homematic-community/XML-API](https://github.com/homematic-community/XML-API): the classic minimal addon (Tcl CGIs only); its `update_script` still shows the CCU1/CCU2 branches, its rc.d script the `info` fields.
- [jens-maus/hm_pdetect](https://github.com/jens-maus/hm_pdetect), [CUxD](https://cuxd.de/), [CCU-Historian](https://github.com/mdzio/ccu-historian): further long-lived addons worth reading.

## Test tooling and prior art for CCU clients

- [hobbyquaker/hm-simulator](https://github.com/hobbyquaker/hm-simulator): partial CCU simulation for automated tests (rfd binrpc on 2001, HmIPServer xmlrpc on 2010, ReGa mock on 8181, behaviour scripts, in-process event API). Planned to be extended substantially (September 2026).
- [rdmtc/node-red-contrib-ccu](https://github.com/rdmtc/node-red-contrib-ccu) `test/`: mocha tests against hm-simulator (`rpc_spec.js`, `regahss_spec.js`, `context_spec.js`, `utils.js`, `simulator-data/`, `simulator-behaviors/`).
- [hobbyquaker/hm2mqtt.js](https://github.com/hobbyquaker/hm2mqtt.js) `test/`: node:test with in-process fakes for binrpc/xmlrpc and ReGa (`rpc.test.js`, `rega.test.js`, `cast.test.js`, `values.test.js`, `interfaces.test.js`, `e2e.test.js`).

## Forum threads (homematic-forum.de)

- [Addon-Paket für die CCU erstellen? (2011)](https://homematic-forum.de/forum/viewtopic.php?f=26&t=5985): put files under `/usr/local/addons`, link them into `/usr/local/etc/config/addons/www` instead of patching `/www`; `update_script` must be executable.
- [Frage zur AddOn-Programmierung (2012)](https://homematic-forum.de/forum/viewtopic.php?t=10179): why persistent changes to the read-only root belong into an rc.d step, not into `update_script`.
- [Eigenes Addon (2014)](https://homematic-forum.de/forum/viewtopic.php?f=41&t=21839): the `tar -C dir .` packaging rule and the `.DS_Store` trap.
- [CCU3 - AddOns (2018)](https://homematic-forum.de/forum/viewtopic.php?t=45118): RaspberryMatic addons run on the CCU3.

## Other

- [Mosquitto documentation](https://mosquitto.org/documentation/) and [ChangeLog](https://github.com/eclipse-mosquitto/mosquitto/blob/master/ChangeLog.txt) (2.1: `password_file` and `acl_file` deprecated in favour of plugins, built-in websockets, `--test-config`).
- [Alpine Linux](https://alpinelinux.org/) packages and [musl](https://musl.libc.org/) dynamic linking (`ldso/dynlink.c`: RPATH search along `needed_by`).
- [patchelf](https://github.com/NixOS/patchelf), [tonistiigi/binfmt](https://github.com/tonistiigi/binfmt) for ARM containers on x86.
- The 2019 version of this howto (German skeleton) is in the git history of this repository.
