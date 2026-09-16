# 01 Platforms

An addon runs on a Buildroot-based embedded Linux with busybox. There is no package manager, no
compiler, no sudo; everything runs as root. Two firmware families matter today
(a third, openccu-lite, is OpenCCU without ReGaHSS and with systemd; see [11](11-openccu-lite.md)):

| | Original CCU3 firmware (eQ-3) | OpenCCU (formerly RaspberryMatic) |
| --- | --- | --- |
| Hardware | CCU3 (Raspberry Pi 3 based, armv7l, 1 GB RAM) and "Charly" variants | Raspberry Pi 2/3/4/5, Tinkerboard, x86 (ova, intelnuc), containers (oci) |
| Kernel arch (`uname -m`) | `armv7l` | `armv7l` (rpi2, tinkerboard, oci_arm), `aarch64` (rpi3/4/5, oci_arm64), `x86_64` (ova, intelnuc, oci_amd64) |
| glibc | **2.27** (Buildroot 2018.08) | current (2.43 on 3.89.8) |
| busybox | 1.29 | 1.38 |
| Tcl (`/bin/tclsh`, runs every CGI) | **8.2.3** | 8.6 |
| `/VERSION` | `VERSION=3.89.8`, `PRODUCT=ccu3`, `PLATFORM=rpi3` | `VERSION=3.89.8.20260719`, `PRODUCT=ova` or `rpi4` etc., `PLATFORM=...` |
| Addon install | at the shutdown of a reboot, in a chroot | live, reboot only on exit code 10 |
| monit | no | yes (`/usr/local/etc/monit*.cfg` are included) |
| 32-bit compat loaders | n/a | yes: `/lib/ld-linux.so.2` on x86_64, `/lib/ld-linux-armhf.so.3` on aarch64, so old i386/armv7 helper binaries still run |
| Firewall library | `/lib/libfirewall.tcl` | `/lib/libfirewall.tcl`, plus `/bin/updateAddonConfig.tcl` and `/bin/checkAddonUpdates.sh` |
| USB sticks | `/media/usb1` to `/media/usb8` exist as empty mount points on a tmpfs | `/media/usb0` and up are created when a stick is mounted |

Sources: the values were read from the lab systems (`/VERSION`, `/lib/libc.so.6`, `busybox`,
`tclsh` with `info patchlevel`, `/lib`, `/media`), see [10-sources.md](10-sources.md).

## What is what on disk

- `/` is read-only and **replaced by every firmware update**. Never patch it from an addon unless
  you re-apply the patch at every boot from your rc.d script and accept that it may break with the
  next firmware (that is how CCU1/CCU2 addons did it, see the forum threads in [10](10-sources.md)).
- `/usr/local` is the writable user partition (ext4 on the SD card or disk). Everything an addon
  owns lives here:
  - `/usr/local/addons/<name>/` is your tree.
  - `/usr/local/etc/config/rc.d/<name>` is your service script (or a symlink into your tree).
  - `/usr/local/etc/config/addons/www/<name>` is your web root, served as
    `http://ccu/addons/<name>/` (`/www/addons` is a symlink to `/etc/config/addons/www`, and
    `/etc/config` is a symlink to `/usr/local/etc/config`).
  - `/usr/local/etc/config/hm_addons.cfg` holds the *Einstellungen* buttons ([04](04-webui.md)).
  - `/usr/local/etc/config/lighttpd/*.conf` is extra lighttpd configuration included by the
    firmware (OpenCCU and CCU3 firmware 3.61.5 and later), for proxy rules to your own HTTP server.
  - `/usr/local/etc/monit*.cfg`, `/usr/local/crontabs/root`, `/usr/local/etc/rc.local`,
    `/usr/local/etc/rc.prelocal`, `/usr/local/etc/profile.d/*.sh` ([06](06-system-integration.md)).
  - `/usr/local/tmp` is where uploads land (`new_addon.tar.gz`) and installers unpack; it is
    excluded from backups.
- `/etc/config/server.pem` is the CCU's own TLS certificate and key in one PEM file (the WebUI
  uses it for https); an addon may use it for its own TLS listeners.
- `/var/log/messages` is the busybox syslog. `/var/hm_mode` (`HM_MODE=NORMAL`) and
  `/etc/config/safemode` control whether addons are started at all ([03](03-rc-script.md)).

## Which platforms to support

RedMatic 9 and ccu-addon-mosquitto settled on **armv7l, aarch64 and x86_64**: the CCU3 firmware
and every OpenCCU variant. openccu-lite only runs **aarch64 and x86_64**, and never selects an
`armv7l` asset ([11](11-openccu-lite.md)). armv6l (Raspberry Pi 1 and Zero) was dropped in 2026: the CPU is too
weak for anything with a runtime and no current musl or Node builds exist for it. If you ship one
package per architecture, check `uname -m` in `update_script` and refuse a mismatch; exit code 13
is the conventional "unsupported platform" code and OpenCCU shows it as `Error (13)`.

The `busmatic` check found in old addons (a grep for the word in
`/www/api/methods/ccu/downloadFirmware.tcl`, then `exit 13`) targeted a CCU2 firmware variant.
On current firmwares the file does not contain the word; the check is dead code.
