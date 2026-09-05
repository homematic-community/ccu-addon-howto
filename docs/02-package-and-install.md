# 02 Package and installation

## The package

A CCU addon is a gzipped tar archive. At the top level it contains an executable `update_script`
and, by convention, one directory with the addon's files:

```
mosquitto-2.1.2+0.tar.gz
├── update_script          (executable, POSIX sh, the installer)
├── update_addon -> mosquitto/bin/update_addon   (optional helper, see 04)
├── mosquitto.cfg          (optional, the Einstellungen button, see 04)
└── mosquitto/             (your tree, copied to /usr/local/addons/mosquitto)
    ├── bin/  lib/  etc/  www/  var/  versions
```

Rules that follow from the installers (sources below):

- `update_script` must be **executable** inside the archive (`chmod 755` before packing) and must
  be **POSIX sh** (busybox `ash` runs it; no bashisms).
- Pack with `tar --owner=root --group=root -czf ... *` from inside the staging directory, or
  `tar czf addon.tar.gz -C staging .`. Do not pack a parent directory, do not include `.DS_Store`
  or `._*` files (macOS: `COPYFILE_DISABLE=1`), keep LF line endings. A wrong layout is the
  classic reason for "nothing happens after the upload"
  ([forum 2014](https://homematic-forum.de/forum/viewtopic.php?f=41&t=21839)).
- OpenCCU verifies **`*.sha256` files at the top level of the archive** with `sha256sum -c` before
  running `update_script` (exit 105/106 on mismatch): a free integrity check if you add one.
- Keep the archive small; the CCU3 unpacks it on an SD card and copies a whole root filesystem
  next to it (see below).

## How the firmware installs it

The user uploads the archive under *Einstellungen > Systemsteuerung > Zusatzsoftware*.
`cp_software.cgi` stores it as `/usr/local/tmp/new_addon.tar.gz` and then:

### OpenCCU: live

`/bin/install_addon` ([source](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/bin/install_addon)):

1. `mktemp -d -p /usr/local/tmp`, `tar -x` with `--no-same-owner --no-same-permissions`, delete the archive.
2. Requires an executable `update_script` (exit 104 otherwise), checks `*.sha256` files (105/106).
3. `cd` into the temp dir, `./update_script HM-RASPBERRYMATIC` with stdout and stderr discarded.
4. Remounts `/` and `/boot` read-only, deletes the temp dir, runs `ldconfig`, `sync`.
5. Returns the exit code of `update_script`. `cp_software.cgi` then shows: `0` = installed, no
   reboot; `10` = installed, rebooting; anything else = `Error (<code>)`.

Consequences: the working directory of `update_script` is deleted right after it returns, so a
service started from there must `cd /` first or it will later fail to spawn children from a
vanished cwd (RedMatic issue #599). The temp dir lives on the same partition as the addon.

### Original CCU3 firmware: at shutdown, in a chroot

`cp_software.cgi` touches `/usr/local/.doAddonInstall` and reboots. During the **shutdown**
`/etc/init.d/S00InstallAddon` (it only implements `stop()`) runs `/bin/install_addon`, which:

1. Unpacks to a temp dir below `/usr/local/tmp` and requires an executable `update_script`.
2. **Copies `/bin`, `/lib`, `/sbin`, `/etc` and everything in `/usr` except `local`** into the temp
   dir and bind-mounts `dev`, `proc`, `sys`, `dev/pts` and `/usr/local` into it (measured: about
   230 MB and 17k inodes on firmware 3.89.8).
3. `chroot`s into the temp dir and runs `./update_script HM-RASPBERRYMATIC`.
4. Unmounts and syncs. The temp dir is **not** removed. The following boot starts the addons.

Consequences: `update_script` runs in a copy of the root filesystem at shutdown. Anything it
starts is gone at boot, so never start a service from it when `/etc/init.d/S00InstallAddon`
exists. `/usr/local` inside the chroot is the real one. The leftover temp dir eats space and
inodes on the small `/usr/local` partition; a self-updater should remove stale
`/usr/local/tmp/tmp.*` directories (after releasing their mounts) before it downloads.

The exit code is ignored on this path: the CCU3 firmware always reboots after an upload. An
`update_script` still returns 10 on a fresh install and 0 on an update, because the same package
must work on OpenCCU and because a manual installation over ssh (unpack, run `update_script`,
start the service) is the fastest way to test.

Sources: `/bin/install_addon` and `/etc/init.d/S00InstallAddon` of CCU3 firmware 3.89.8 (read on
the device); `cp_software.cgi` in [eq-3/occu](https://github.com/eq-3/occu/blob/master/WebUI/www/config/cp_software.cgi)
(`action_install_start`, `action_install_go`); OpenCCU's `install_addon` (link above).

## What update_script has to do

See [templates/update_script](../templates/update_script) for a complete, tested example. The
steps:

1. Optional platform check: compare `uname -m` with the architecture the package was built for
   and `exit 13` on a mismatch. The old `busmatic` grep is dead code ([01](01-platforms.md)).
2. `mount | grep /usr/local || mount /usr/local`: historical, harmless, keep it.
3. Create `/usr/local/addons`, `/usr/local/etc/config/rc.d` and
   `/usr/local/etc/config/addons/www` with mode 755 if missing.
4. **Update detection**: if `/usr/local/etc/config/rc.d/<name>` exists this is an update. Stop
   the running service through it and remember `EXITCODE=0`; otherwise `EXITCODE=10`.
5. Remove what the addon owns from the previous version (`bin`, `lib`, `www`, ...) so stale files
   cannot survive; keep the user's data (`etc/`, `var/`). Then `cp -af <name> /usr/local/addons/`.
6. First-install defaults: copy `etc/<config>.default` to `etc/<config>` only when the latter is
   missing. Never overwrite user configuration on updates.
7. Migrations from older layouts of your own addon (rename keys, fold files, delete obsolete
   tools) happen here, idempotently.
8. Links: `ln -sfn /usr/local/addons/<name>/www /usr/local/etc/config/addons/www/<name>`
   (busybox `ln -sfT` refuses to replace an existing directory symlink, `-n` works) and
   `ln -sf /usr/local/addons/<name>/bin/<service> /usr/local/etc/config/rc.d/<name>`.
9. The *Einstellungen* button: `touch /usr/local/etc/config/hm_addons.cfg` and
   `./update_addon <name> <name>.cfg` ([04](04-webui.md)).
10. `sync`.
11. On an update (`EXITCODE=0`) and **only when `/etc/init.d/S00InstallAddon` does not exist**
    (that is: not inside the CCU3 chroot): `cd /` and start the service. OpenCCU does not reboot
    on 0 and nothing else would start it.
12. `exit $EXITCODE`.

Notes:

- The argument `HM-RASPBERRYMATIC` is passed by both firmwares today. Old scripts branch on an
  empty argument (CCU1), `CCU2` and `HM-RASPBERRYMATIC` and mount `/usr/local` themselves; only
  the last branch matters now.
- Output is discarded by OpenCCU's installer. Log to syslog with `logger -t <name>` for a trace,
  or write a log file below `/usr/local/tmp` while debugging.
- `update_script` runs as root with `umask 022`; keep secrets (password files, keys) at mode 600 yourself.
- Never delete `/usr/local/addons/<name>` wholesale on an update; users keep their data there.

## Uninstall

The WebUI runs `<rc.d script> uninstall` and afterwards deletes the rc.d script itself
(`action_operation` in `cp_software.cgi`; failures go to `/var/log/addon-uninstall-error.log`).
Your `uninstall` must stop the service and remove the button entry, the www symlink, any
lighttpd, monit or cron files you created, and the addon directory. Make sure no dangling symlink
stays behind: a dangling `/usr/local/etc/monit-<name>.cfg` breaks every monit reload
(RedMatic issue #521; a `-f` test misses a dangling link, use `-L`).

## Manual installation over ssh

Exactly what the firmware does, minus the reboot:

```sh
scp addon.tar.gz root@ccu:/usr/local/tmp/
ssh root@ccu 'cd /usr/local/tmp && rm -rf t && mkdir t && cd t && tar -xzf ../addon.tar.gz && ./update_script HM-RASPBERRYMATIC; echo "exit $?"; cd /; rm -rf /usr/local/tmp/t'
ssh root@ccu '/usr/local/etc/config/rc.d/<name> start'
```

On OpenCCU the WebUI path can be replayed 1:1: copy the archive to
`/usr/local/tmp/new_addon.tar.gz` and run `/bin/install_addon`; its exit code is what the WebUI
would show.
