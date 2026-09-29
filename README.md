# ccu-addon-howto

> How to build addons ("Zusatzsoftware") for the Homematic CCU3, OpenCCU (formerly RaspberryMatic) and [openccu-lite](https://github.com/hobbyquaker/openccu-lite), for humans and for AI coding agents.

**Status 2026-09: rewritten from scratch in English.** Everything in here was verified on real
systems (original eQ-3 CCU3 firmware 3.89.8 on CCU3 hardware, OpenCCU 3.89.8 on x86_64 and on a
Raspberry Pi 4) while modernising [RedMatic](https://github.com/rdmtc/RedMatic) (Node-RED as an
addon) and [ccu-addon-mosquitto](https://github.com/homematic-community/ccu-addon-mosquitto)
(the Mosquitto MQTT broker as an addon), and cross-checked against the firmware sources. Every
non-obvious claim carries a source; the sources are collected in [docs/10-sources.md](docs/10-sources.md).
Pull requests welcome.

## Contents

| Chapter | What you learn |
| --- | --- |
| [01 Platforms](docs/01-platforms.md) | CCU3 firmware vs. OpenCCU vs. openccu-lite, architectures, libc, Tcl and busybox versions, read-only root, what `/usr/local` is |
| [02 Package and installation](docs/02-package-and-install.md) | The `.tar.gz` layout, `update_script`, exit codes, how each firmware installs (live vs. reboot + chroot), updates, migration, uninstall |
| [03 The rc.d script](docs/03-rc-script.md) | `init`/`start`/`stop`/`info`/`restart`/`uninstall`, the `info` fields the WebUI parses, boot order, safe mode |
| [04 WebUI integration](docs/04-webui.md) | The *Einstellungen* button (`hm_addons.cfg`), the update check, serving pages and CGIs through lighttpd, the CCU session, **Tcl 8.2 pitfalls** |
| [05 Binaries](docs/05-binaries.md) | No toolchain on the box, glibc 2.27 on the CCU3, self-contained musl binaries with patchelf, building in Alpine containers |
| [06 System integration](docs/06-system-integration.md) | Syslog, pid files, backups (`.nobackup`), monit, cron, firewall API, USB sticks, memory pressure |
| [07 Updates and releases](docs/07-updates-and-releases.md) | Update check protocol, self-update from the settings page, GitHub releases, version schemes, automatic releases |
| [08 Testing](docs/08-testing.md) | Container e2e test that replays the firmware installer, unit tests, hm-simulator for addons that talk to the CCU, headless browser against the real page, hardware checklist |
| [09 Guide for AI agents](docs/09-agent-guide.md) | Working rules, an `AGENTS.md` template, roadmap conventions, the trap list |
| [10 Sources](docs/10-sources.md) | Firmware files, GitHub sources, forum threads, example addons |
| [11 openccu-lite](docs/11-openccu-lite.md) | The CCU firmware without ReGaHSS: generated systemd units, confinement (own user, `ProtectSystem=strict`), the catalogue's `runtime` block, session gate and `X-Occulite-Session`, the metadata API, what is gone |
| [12 Porting to openccu-lite](docs/12-porting-to-openccu-lite.md) | Step-by-step checklist to make an existing addon run on all three firmwares from one package |
| [templates/](templates/) | Copy-and-adapt: `update_script`, the openccu-lite manifest `openccu-lite.json`, rc.d script, session check, query-string helpers, update check CGI, `update_addon`, container test, and the [openccu-lite porting prompt](templates/PORTING-PROMPT.md) for your coding agent |

## Ten facts that save you a day

1. An addon is a `.tar.gz` with an executable `update_script` at the top level. The firmware
   unpacks it into a temp dir below `/usr/local/tmp`, changes into it and runs
   `./update_script HM-RASPBERRYMATIC`. Exit `0` = done, `10` = "reboot me"; anything else is an
   error on OpenCCU. ([02](docs/02-package-and-install.md))
2. The original CCU3 firmware installs addons **during the shutdown of the reboot** that follows
   the upload, inside a chroot that copies `/bin /lib /sbin /etc /usr` next to your package.
   Nothing you start from `update_script` survives there. OpenCCU installs live and reboots only
   on exit code 10. ([02](docs/02-package-and-install.md))
3. Your only persistent home is `/usr/local`. The root filesystem is read-only and replaced by
   firmware updates. Put files in `/usr/local/addons/<name>`, the service script in
   `/usr/local/etc/config/rc.d/<name>`, web content behind a symlink in
   `/usr/local/etc/config/addons/www/<name>` (served as `/addons/<name>/`). ([02](docs/02-package-and-install.md), [04](docs/04-webui.md))
4. The rc.d script's `info` output is parsed line by line as `Key: value`; `Name:` is mandatory
   or the addon is invisible, `Version:`, `Info:`, `Update:`, `Config-Url:`, `Operations:` do the rest. ([03](docs/03-rc-script.md))
5. The *Einstellungen* button is one entry in `/usr/local/etc/config/hm_addons.cfg`, a flat
   Tcl `array get` list: ten lines of Tcl, no binary helper needed. ([04](docs/04-webui.md))
6. CGIs are run by `/bin/tclsh`. The original CCU3 firmware ships **Tcl 8.2.3**: no `dict`,
   no `{*}`, no `eq`/`ne`, no `2>@1`, no value-returning `regsub`/`scan`. OpenCCU has 8.6, so
   code that only ran on OpenCCU may be broken on the CCU3. ([04](docs/04-webui.md))
7. Every CGI that changes something must check the CCU session id the WebUI passes as
   `?sid=@xxxxxxxxxx@` through `tclrega.so` / `system.GetSessionVarStr`. ([04](docs/04-webui.md))
8. There is no compiler on the box and the CCU3 firmware has glibc 2.27. Ship self-contained
   binaries: musl builds from Alpine (packages or your own build in an Alpine container) with the
   loader and libraries inside the addon and the ELF interpreter/RPATH rewritten with `patchelf`.
   Never export `LD_LIBRARY_PATH` globally. ([05](docs/05-binaries.md))
9. The firmware backup is `tar` with `--exclude-tag=.nobackup`: drop a `.nobackup` file into
   directories that are only build output. Log through `logger` to `/var/log/messages`. ([06](docs/06-system-integration.md))
10. Test the install path exactly as the firmware does it (a Debian container with busybox `sh`
    replaying `install_addon`), then on the real firmwares: CCU3 firmware and OpenCCU differ in
    Tcl, glibc, installer and reboot behaviour. ([08](docs/08-testing.md))

## And on openccu-lite

openccu-lite installs the same package, but has no ReGaHSS, runs your rc.d script inside a
generated systemd unit, and runs your addon **as its own unprivileged user** by default. What
changes for you:

- write only to your own directories;
- keep the pid file in `/run/addon-<id>/`;
- log to the journal (stdout or `logger`);
- take the session from the `X-Occulite-Session` header, confirmed by the system;
- use the metadata API instead of ReGa for names and rooms;
- describe the addon and what it needs in a manifest, `openccu-lite.json`;
- let the system handle updates and firewall ports.

[11](docs/11-openccu-lite.md) explains the platform, [12](docs/12-porting-to-openccu-lite.md) is
the porting checklist, and [templates/PORTING-PROMPT.md](templates/PORTING-PROMPT.md) hands the
job to a coding agent.

## Who wrote this

Started 2019 by Sebastian Raff ([hobbyquaker](https://github.com/hobbyquaker)); the 2026 rewrite
was done by Claude (Anthropic) on behalf of hobbyquaker from the RedMatic 9 and
ccu-addon-mosquitto work. See [AUTHORS](AUTHORS).

## License

[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) for the text; the code in
[templates/](templates/) is released under the [MIT license](templates/LICENSE) so it can be
copied into any addon.
