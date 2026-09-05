# Templates

Copy-and-adapt files, all taken from working addons (ccu-addon-mosquitto, RedMatic) and tested
on the original CCU3 firmware and OpenCCU. MIT licensed, see [LICENSE](LICENSE).

| File | Purpose | Chapter |
| --- | --- | --- |
| [update_script](update_script) | installer: platform check, update detection, links, button, exit codes, service start on live updates | [02](../docs/02-package-and-install.md) |
| [rc.d-script](rc.d-script) | service script: start/stop/restart/reload/status/info/uninstall, pid handling, `.nobackup`, syslog | [03](../docs/03-rc-script.md) |
| [lib/session.tcl](lib/session.tcl) | CCU session check through `tclrega.so` | [04](../docs/04-webui.md) |
| [lib/querystring.tcl](lib/querystring.tcl) | query string and form parsing, `run` helper, JSON quoting; Tcl 8.2 safe | [04](../docs/04-webui.md) |
| [www/update_check.cgi](www/update_check.cgi) | the `Update:` URL: newest GitHub release or `n/a`, download redirect | [04](../docs/04-webui.md), [07](../docs/07-updates-and-releases.md) |
| [bin/update_addon](bin/update_addon) | the Einstellungen button in `hm_addons.cfg`, add and remove, no binary helper | [04](../docs/04-webui.md) |
| [test/e2e-replay.sh](test/e2e-replay.sh) | container test replaying OpenCCU's `install_addon` (fresh install, update, uninstall) | [08](../docs/08-testing.md) |
| [AGENTS.md](AGENTS.md) | instructions file for AI coding agents working on an addon repository | [09](../docs/09-agent-guide.md) |

For a complete settings page (HTML, CSS, JS, the config/service/password/certificate/firewall/
media/log/update CGIs) take ccu-addon-mosquitto's `addon_files/mosquitto/www/`; for a self-update
worker its `bin/mosquitto-update` or RedMatic's `bin/redmatic-update`.
