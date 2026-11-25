# 10 Sources

Everything in this handbook was either read from a running firmware or from the sources below.
Firmware facts were verified on original CCU3 firmware 3.89.8 (CCU3 hardware) and OpenCCU
3.89.8.20260719 (x86_64 ova and Raspberry Pi 4) in September 2026.

## Firmware sources (OpenCCU, formerly RaspberryMatic)

Repository: [OpenCCU/OpenCCU](https://github.com/OpenCCU/OpenCCU) (the former `jens-maus/RaspberryMatic`).

- [buildroot-external/overlay/base/bin/install_addon](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/bin/install_addon): the live installer, exit codes 101 to 106, sha256 check, `ldconfig`.
- [buildroot-external/overlay/base/etc/init.d/S50lighttpd](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/etc/init.d/S50lighttpd): `restart` is stop and start, `reload` sends `USR1` to lighttpd-angel, which starts a new server and lets the old one finish its requests (`graceful shutdown started` in `/var/log/lighttpd-error.log`). Measured on OpenCCU 3.89.8 (November 2026) with a fresh install through the WebUI: a `restart` in `update_script` cut off `cp_software.cgi`'s `install_go` request about 0.2 s in (Chromium `ERR_INCOMPLETE_CHUNKED_ENCODING`, no reboot, service not started); with `reload` the WebUI showed the reboot notice and rebooted. OpenCCU 3.89.14's `cpMessageBox.LoadFromFile` reports such a broken request (status 0) as "Error while loading the following file". Found by [homematic-manager #141](https://github.com/hobbyquaker/homematic-manager/issues/141) and [ccu-addon-battery 1.5.6](https://github.com/hobbyquaker/ccu-addon-battery/releases/tag/v1.5.6).
- [buildroot-external/overlay/base/etc/init.d/S55InitAddons](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/etc/init.d/S55InitAddons) and [S98StartAddons](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/etc/init.d/S98StartAddons): `run-parts -a init|start|stop /etc/config/rc.d`, safe mode, `HM_MODE`, profile.d, rc.local, `oom_score_adj`, monit link cleanup.
- [buildroot-external/overlay/base/etc/init.d/S06InitSystem](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/etc/init.d/S06InitSystem): `/usr/local/tmp` handling, `.nobackup` there.
- [buildroot-external/overlay/base/etc/lighttpd/conf.d/cgi.conf](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/etc/lighttpd/conf.d/cgi.conf) (`.cgi` to `/bin/tclsh`, X-Sendfile for `/usr/local/tmp`) and [webui.conf](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/etc/lighttpd/conf.d/webui.conf) (`/addons` bypasses the WebUI proxy).
- [buildroot-external/overlay/base/lib/libfirewall.tcl](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/lib/libfirewall.tcl): `Firewall_loadConfiguration`, `Firewall_USER_PORTS`, `Firewall_MODE`, `Firewall_saveConfiguration`, `Firewall_configureFirewall`, MOST_OPEN vs RESTRICTIVE.
- [buildroot-external/overlay/base-openccu/bin/updateAddonConfig.tcl](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base-openccu/bin/updateAddonConfig.tcl) (by MDZ, CCU-Historian): the `hm_addons.cfg` command line wrapper.
- [buildroot-external/overlay/base-openccu/bin/checkAddonUpdates.sh](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base-openccu/bin/checkAddonUpdates.sh): how OpenCCU polls the `Update:` URLs and writes `/tmp/addon_updates.json`; [etc/crontab.root](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base-openccu/etc/crontab.root): once a day at 12:00 plus up to 15 minutes, skipped when `/etc/config/NoAddonUpdateCheck` exists.
- The shutdown order behind "the addons are stopped before `S00InstallAddon` runs": buildroot's busybox `rcK` stops the `/etc/init.d/S??*` scripts in reverse order, so `S98StartAddons stop` (`run-parts -a stop /etc/config/rc.d`) runs before `S00InstallAddon stop`. Read in OpenCCU's tree; the CCU3 firmware's init scripts come from the same lineage and were not re-read for this. The restart rule of `update_script` (run before → run after, the CCU3 start through `chroot /proc/1/root`) is tested with the installer's chroot replayed in a container: [ccu-addon-kit](https://github.com/hobbyquaker/ccu-addon-kit)'s end-to-end test.
- [buildroot-external/overlay/base-openccu/bin/createBackup.sh](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base-openccu/bin/createBackup.sh): `tar --exclude-tag=.nobackup`.
- [buildroot-external/patches/occu/0034-WebUI-Addon-Config.patch](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/patches/occu/0034-WebUI-Addon-Config.patch): adds `RemoveConfigPage` to the HomeMatic Tcl package.
- [buildroot-external/patches/occu/0031-WebUI-Fix-FileUpload](https://github.com/OpenCCU/OpenCCU/tree/master/buildroot-external/patches/occu/0031-WebUI-Fix-FileUpload): OpenCCU's patched `cp_software.cgi`.
- lighttpd's own request parser ([`src/request.c`](https://github.com/lighttpd/lighttpd1.4/blob/master/src/request.c)): a POST over HTTP/1.x without `Content-Length` and without `Transfer-Encoding` is answered 411 before any module runs; no configuration changes that. Homematic Manager's move of its settings and service CGIs to POST (`www/lib/session.tcl`, `request_is_post`, `post_params`, 3.0.0-beta.30) showed it.

## Firmware sources (eQ-3 OCCU)

Repository: [eq-3/occu](https://github.com/eq-3/occu), the published parts of the CCU firmware.

- [WebUI/www/config/cp_software.cgi](https://github.com/eq-3/occu/blob/master/WebUI/www/config/cp_software.cgi): the Zusatzsoftware page. `get_info` (parses `Key: value` from `<script> info.<lang>` and `<script> info`), `OPERATIONS` (`restart`, `uninstall`), the update check JavaScript (`?cmd=check_version&version=`, `?cmd=download&version=`), `action_install_start` (`new_addon.tar.gz`, `.doAddonInstall` + reboot on the CCU3), `action_install_go` (exit code handling), `action_operation` (`rm -rf $script` after uninstall, `/var/log/addon-uninstall-error.log`).
- [arm-gnueabihf/packages-eQ-3/WebUI/lib/tcl8.2/homematic/homematic.tcl](https://github.com/eq-3/occu/blob/master/arm-gnueabihf/packages-eQ-3/WebUI/lib/tcl8.2/homematic/homematic.tcl): `::HomeMatic::Addon::AddConfigPage`, `GetAll`, the `hm_addons.cfg` format (`array get`).
- Not on GitHub but read on the CCU3 firmware 3.89.8: `/bin/install_addon` (chroot installer), `/etc/init.d/S00InstallAddon` (runs it in `stop()`), `/etc/lighttpd/conf.d/proxy_normal.conf`, `/lib/tcl8.2/homematic/homematic.tcl`, `/lib/libfirewall.tcl`, `/www/config/cp_software.cgi`, `/www/config/cp_maintenance.cgi`.
- Read in the root filesystems of the CCU3 firmware 3.85.7 (eQ-3's `ccu3-3.85.7.tgz`, the version piVCCU 3 packages) and 3.89.11 (November 2026): `/bin/install_addon` is the same in both (`mktemp -d -p /usr/local/tmp`, the root copy, the binds, `chroot`, `umount` without a fallback, the directory never removed); `/etc/init.d/S06InitSystem` runs `rm -rf /usr/local/tmp/*` at every boot; `/www/config/backup.tcl` (`create_backup`) tars `/usr/local` with `--exclude=usr/local/tmp`, `--exclude-tag=.nobackup` and `--one-file-system`. The removal of the leftover temp dirs from `update_script` was tested with that `install_addon` run unchanged in a container (only a `lib64` link added for the x86_64 loader) and with the installer replayed in [ccu-addon-kit](https://github.com/hobbyquaker/ccu-addon-kit)'s end-to-end test and [ccu-addon-battery](https://github.com/hobbyquaker/ccu-addon-battery)'s install test.
- piVCCU: [pivccu/host3/pivccu-backup.sh](https://github.com/alexreinert/piVCCU/blob/master/pivccu/host3/pivccu-backup.sh) (`tar czf ... usr/local` over the bind-mounted user partition, no exclusions) and [pivccu/firmware3.patch](https://github.com/alexreinert/piVCCU/blob/master/pivccu/firmware3.patch) (leaves `install_addon`, `S00InstallAddon` and the `/usr/local/tmp` cleanup of `S06InitSystem` as they are).

## openccu-lite

Repositories: [hobbyquaker/openccu-lite](https://github.com/hobbyquaker/openccu-lite) (the
firmware, branch `main`) and [hobbyquaker/occulited](https://github.com/hobbyquaker/occulited)
(its system service, branch `master`). Chapters [11](11-openccu-lite.md) and
[12](12-porting-to-openccu-lite.md) were first read from their sources in September 2026
(`1.0.0-dev.1`) and checked on an x86_64 OVA and a Raspberry Pi 4, then re-read against the first
public release [`v1.0.0-dev.28`](https://github.com/hobbyquaker/openccu-lite/releases) (occulited
`570f283`):

- the addon unit generator,
  [`occu-addons`](https://github.com/hobbyquaker/openccu-lite/blob/main/buildroot-external/overlay/lite/usr/lib/systemd/system-generators/occu-addons),
  the rc.d wrapper
  [`addon-rc-wrapper`](https://github.com/hobbyquaker/openccu-lite/blob/main/buildroot-external/overlay/lite/usr/libexec/occu/addon-rc-wrapper)
  and the boot `init` pass
  [`lite-init-addons`](https://github.com/hobbyquaker/openccu-lite/blob/main/buildroot-external/overlay/lite/usr/libexec/occu/lite-init-addons),
  and, in the images after `1.0.0-dev.30`, the restore check `lite-addon-payload` beside them and
  the `usbstorage` owner of FAT, exFAT and NTFS sticks in
  [`usbmount.conf`](https://github.com/hobbyquaker/openccu-lite/blob/main/buildroot-external/overlay/lite/etc/usbmount/usbmount.conf);
- occulited's addon scripts: `info` and `uninstall` as the addon user and what the system removes
  after an uninstall (`internal/system/services.go`, `internal/system/addons.go`); for
  `1.0.0-dev.37` the policy files' removal, the `{ok, output, system_removed}` answer, the
  `addon-install` journal lines and the uid registry (`internal/system/addonuids.go`), as
  [`docs/system-api.md`](https://github.com/hobbyquaker/occulited/blob/master/docs/system-api.md)'s
  `POST /addons/{id}/uninstall` row documents them;
- occulited's addon policy (the confinement drop-in, `internal/system/addonpolicy.go`), its CGI
  runner and static file server, the lighttpd fragment check (`internal/system/lighttpdropin.go`),
  the ReGa and ELF scans, and the menu parser;
- the lighttpd session gate, and the fork's lighttpd patch that takes a POST without
  `Content-Length` as an empty body
  ([`board/lite/patches/lighttpd/`](https://github.com/hobbyquaker/openccu-lite/tree/main/buildroot-external/board/lite/patches/lighttpd));
- the `tclrega.so` shim;
- the manifest: [manifest-format.md](https://github.com/hobbyquaker/occulited/blob/master/docs/manifest-format.md),
  [manifest.schema.json](https://github.com/hobbyquaker/occulited/blob/master/docs/manifest.schema.json),
  `internal/manifest`;
- the catalogue: [catalog-format.md](https://github.com/hobbyquaker/occulited/blob/master/docs/catalog-format.md),
  [catalog/catalog.json](https://github.com/hobbyquaker/occulited/blob/master/catalog/catalog.json);
- the metadata API: [meta-api.md](https://github.com/hobbyquaker/occulited/blob/master/docs/meta-api.md),
  [meta-format.md](https://github.com/hobbyquaker/occulited/blob/master/docs/meta-format.md) and the
  conformance corpus [fixtures/](https://github.com/hobbyquaker/occulited/tree/master/fixtures);
- the system and auth APIs, lite-rpc, the addon CGIs and the embedding contract:
  [system-api.md](https://github.com/hobbyquaker/occulited/blob/master/docs/system-api.md);
- the firmware's user documents: [addons.md](https://github.com/hobbyquaker/openccu-lite/blob/main/docs/addons.md),
  [porting-from-rega.md](https://github.com/hobbyquaker/openccu-lite/blob/main/docs/porting-from-rega.md),
  [PORTING-PROMPT.md](https://github.com/hobbyquaker/openccu-lite/blob/main/docs/PORTING-PROMPT.md)
  (the metadata porting prompt), [security.md](https://github.com/hobbyquaker/openccu-lite/blob/main/docs/security.md).
- where `init` and `start` run, and what a daemon started in `init` does: measured on
  `1.0.0-dev.12` (a root addon whose script starts its daemon in `init`: the daemon in
  `occu-init-addons.service` as root, its own unit `active (exited)`) and `1.0.0-dev.32` (the same
  script shape confined, with systemd's left-over process warning, and as root, where the unit
  never started the daemon); the boot pass and the generated `ExecStartPre` in the generator and
  `lite-init-addons` above.
- the Node.js client [occulite-client](https://github.com/hobbyquaker/occulite-client) 0.2.0: its
  README and [docs/porting.md](https://github.com/hobbyquaker/occulite-client/blob/main/docs/porting.md)
  (offering both paths, credentials and pairing, detection, CommonJS).
- the openccu-lite column of the table in [01](01-platforms.md): the release's build configuration
  ([`buildroot-external/configs/`](https://github.com/hobbyquaker/openccu-lite/tree/main/buildroot-external/configs),
  the `/VERSION` lines in
  [`board/lite/post-build.sh`](https://github.com/hobbyquaker/openccu-lite/blob/main/buildroot-external/board/lite/post-build.sh),
  the USB mount points in
  [`overlay/lite/etc/usbmount/usbmount.conf`](https://github.com/hobbyquaker/openccu-lite/blob/main/buildroot-external/overlay/lite/etc/usbmount/usbmount.conf)),
  the CycloneDX SBOMs published with
  [`v1.0.0-dev.28`](https://github.com/hobbyquaker/openccu-lite/releases/tag/v1.0.0-dev.28)
  (glibc 2.44, busybox 1.38.0, Tcl 8.6.15, tcllib 1.21), and the install job in system-api.md.

Ported addons that show the result:

- RedMatic 9.4+ (header login for the Node-RED editor, `/api/auth/v1/login`, the journal as a
  log fallback);
- ccu-addon-mosquitto 2.1.2+2 (pid file and log paths when not root);
- Homematic Manager (header auth, a data directory outside the addon tree, an admin-only
  settings page);
- hm2mqtt.js (the metadata provider next to the ReGa one).

## Example addons

- [homematic-community/ccu-addon-mosquitto](https://github.com/homematic-community/ccu-addon-mosquitto): Mosquitto 2.1, source build in Alpine containers, patchelf, settings page with listeners, TLS, users, bridges, firewall, persistence on USB, self-update, e2e and parser tests, automatic releases.
- [rdmtc/RedMatic](https://github.com/rdmtc/RedMatic): Node-RED, Node.js 24 from Alpine on armv7l, bundled git, monit, telemetry, safe mode, progress-bar self-update, wiki.
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
