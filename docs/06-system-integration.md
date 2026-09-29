# 06 System integration

## Logging

There is no journal; busybox `syslogd` writes `/var/log/messages` (rotated to `messages.0`).
Log from shell with `logger -t <name> -p daemon.info "..."`; daemons with a syslog option
(`log_dest syslog` in Mosquitto) appear as `mosquitto[pid]:`. For a Node process without native
modules RedMatic pipes stdout/stderr into persistent `logger` processes per severity
(`lib/logger.js`) instead of a native syslog module. Your settings page's "download log" is then
`grep <name> /var/log/messages.0 /var/log/messages` plus `df`, `free`, `netstat`, `iptables` and
your config, sent with `Content-Type: text/plain`.

## Running a daemon

- `start-stop-daemon -S -q -b -m -p /var/run/<name>.pid --exec <binary> -- <args>` puts the
  process in the background and writes the pid file. `/var/run` is a tmpfs, so a stale pid file
  cannot survive a reboot; still verify the pid (`/proc/<pid>/cmdline`) before trusting it and fall
  back to `pidof`.
- `cd /` before starting anything from `update_script` or a CGI: the OpenCCU installer deletes
  its temp dir, and lighttpd's cwd for a CGI is your www directory, which an update replaces.
- Run as root; the CCU has no service users, and `mosquitto` would try to drop privileges to a
  user that does not exist (`user root` in its config).
- Memory: the CCU3 has 1 GB. Raise `oom_score_adj` of a heavy service (RedMatic writes 800 into
  `/proc/<pid>/oom_score_adj`) so the kernel kills it before the Homematic services.
- Network on the CCU3 firmware comes up late; wait for it after a fresh boot (`/proc/uptime`).
  RedMatic also found the CCU3's eth0 without an IPv6 link-local address after boot and creates it
  by toggling `disable_ipv6` (needed for Matter/mDNS).

## Backups

OpenCCU's `createBackup.sh` tars `/usr/local` with `--exclude-tag=.nobackup`
([source](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base-openccu/bin/createBackup.sh)),
`--one-file-system` and without `/usr/local/tmp`. Put a `.nobackup` file into every directory that
is pure build output (`bin`, `lib`, `www`, `node_modules`) and keep only configuration and data
(`etc`, `var`) backup-worthy; RedMatic offers a switch to include everything. A restore on another
CCU then needs the addon package installed again, which is what users expect. The CCU3 firmware's
backup (`cp_maintenance.cgi`) does not know `.nobackup`, so a CCU3 backup with a large addon can
exceed what the WebUI restores comfortably; document it.

## monit (OpenCCU only)

`/etc/monitrc` includes `/usr/local/etc/monit*.cfg`. Link your own `check process` file there,
`monit reload`, and remove the link on uninstall with a `-L` test (a dangling link breaks every
later reload; OpenCCU's `S98StartAddons` cleans dangling links at boot since 2024, the CCU3
firmware has no monit at all). RedMatic generates its limit from `MemTotal` at every start.

## cron

Busybox crond reads `/usr/local/crontabs/root` (`/etc/config/crontab` on the CCU3 firmware);
append your line with `crontab -` semantics or edit the file and `kill -HUP` crond. Keep the
addon's own scheduling inside the addon where possible.

## The CCU firewall

Both firmwares configure iptables from `/etc/config/firewall.conf` through
`/lib/libfirewall.tcl` ([OpenCCU source](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/lib/libfirewall.tcl);
the CCU3 firmware ships the same API). `MODE = MOST_OPEN` means INPUT policy ACCEPT (every port
reachable, the compatibility default), `RESTRICTIVE` means INPUT policy DROP with only the
firmware services and the user ports ("Port-Freigabe") allowed. User ports go through a
local-only chain on current OpenCCU, i.e. LAN sources only.

An addon that opens ports can read and change this the same way the WebUI's
`Firewall.setConfiguration` API method does:

```tcl
source /lib/libfirewall.tcl
Firewall_loadConfiguration            ;# fills Firewall_MODE, Firewall_USER_PORTS, Firewall_SERVICES, Firewall_IPS
lappend Firewall_USER_PORTS 1883      ;# if not already there
Firewall_saveConfiguration            ;# writes firewall.conf (USERPORTS = ...)
Firewall_configureFirewall            ;# applies iptables rules
```

ccu-addon-mosquitto's `firewall.cgi` shows per listener whether the firewall lets the port
through and offers one button to add the listener ports; the CCU's own firewall page shows them
afterwards. Do not rewrite `firewall.conf` yourself.

## USB sticks and other storage

Sticks are mounted by the firmware at `/media/usb<N>`. On the CCU3 firmware the mount points
`usb1` to `usb8` always exist as empty directories on a tmpfs, so a directory test says nothing;
check `/proc/mounts` for a mount at `/media/usb<N>` and never create data directories below
`/media` unless the mount is there (data written to the tmpfs vanishes at reboot). Use a
subdirectory per addon on a stick. Sticks protect the SD card from write cycles; RedMatic's
context store and the Mosquitto persistence database can live there.

On openccu-lite a confined addon does not run as root. From the images after `1.0.0-dev.30`, sticks
with FAT, exFAT or NTFS are mounted owned by root and the group `usbstorage` (umask 0007); an
addon that wants to use them declares `"groups": ["usbstorage"], "paths": ["/media"]` in its
manifest ([11](11-openccu-lite.md#confinement)). Sticks with ext2/3/4, f2fs or hfsplus keep their
own owners and modes.

## Certificates

`/etc/config/server.pem` holds the CCU's certificate and private key (mode 600 on OpenCCU). It is
self-signed with the hostname as CN. Addons use it for their TLS listeners (`certfile` and
`keyfile` both pointing at it work for Mosquitto). `openssl` exists on every firmware (1.0.2 on
the CCU3, 3.x on OpenCCU) for generating an own certificate; pass SANs through a config file,
`-addext` needs 1.1.1.

## Environment for your own scripts

`S98StartAddons` sources `/etc/profile.d/*.sh` and `/usr/local/etc/profile.d/*.sh` before
starting addons, and runs `/usr/local/etc/rc.local` (and `rc.prelocal` before the init phase on
OpenCCU) with a 120 s timeout. `lighttpd`'s CGI environment does not source these. A CGI or a
cron job therefore has a minimal `PATH` (`/sbin` missing): use absolute paths.

## Read-only root patches

If you must change something under `/` (lighttpd rules were the classic case before
`/usr/local/etc/config/lighttpd/*.conf` existed), do it in the rc.d `init` step with
`mount -o remount,rw /` ... `mount -o remount,ro /`, idempotently, and expect it to break with the
next firmware. RedMatic stopped patching `cp_security.cgi` and `lighttpd.conf` with version 9 and
requires CCU3 firmware 3.61.5 or current OpenCCU instead. See the 2012 forum thread in
[10](10-sources.md) for the CCU1/CCU2 history of this practice.
