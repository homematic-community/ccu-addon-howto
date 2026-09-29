# Templates

Copy-and-adapt files, all taken from working addons (ccu-addon-mosquitto, RedMatic) and tested
on the original CCU3 firmware and OpenCCU (`lib/session.tcl` also on openccu-lite). MIT licensed, see [LICENSE](LICENSE).

| File | Purpose | Chapter |
| --- | --- | --- |
| [update_script](update_script) | installer: platform check, update detection, links, button, exit codes, service start on live updates | [02](../docs/02-package-and-install.md) |
| [openccu-lite.json](openccu-lite.json) | the addon manifest for openccu-lite, at the root of the tarball beside `update_script` (ccu-addon-mosquitto's, validated against occulited's `manifest.schema.json`); the CCU3 and OpenCCU ignore it | [11](../docs/11-openccu-lite.md#the-manifest-and-the-catalogue), [12](../docs/12-porting-to-openccu-lite.md#step-7-the-manifest-and-the-catalogue-entry) |
| [rc.d-script](rc.d-script) | service script: start/stop/restart/reload/status/info/uninstall, pid handling, `.nobackup`, syslog | [03](../docs/03-rc-script.md) |
| [lib/session.tcl](lib/session.tcl) | CCU session check through `tclrega.so`; on openccu-lite the `X-Occulite-Session` header confirmed by the box (`request_session_ok`) | [04](../docs/04-webui.md), [11](../docs/11-openccu-lite.md) |
| [lib/querystring.tcl](lib/querystring.tcl) | query string and form parsing, `run` helper, JSON quoting; Tcl 8.2 safe | [04](../docs/04-webui.md) |
| [www/update_check.cgi](www/update_check.cgi) | the `Update:` URL: newest GitHub release or `n/a`, download redirect | [04](../docs/04-webui.md), [07](../docs/07-updates-and-releases.md) |
| [bin/update_addon](bin/update_addon) | the Einstellungen button in `hm_addons.cfg`, add and remove, no binary helper | [04](../docs/04-webui.md) |
| [test/e2e-replay.sh](test/e2e-replay.sh) | container test replaying OpenCCU's `install_addon` (fresh install, update, uninstall) | [08](../docs/08-testing.md) |
| [AGENTS.md](AGENTS.md) | instructions file for AI coding agents working on an addon repository | [09](../docs/09-agent-guide.md) |
| [PORTING-PROMPT.md](PORTING-PROMPT.md) | prompt for a coding agent: make an existing addon fully openccu-lite compatible | [12](../docs/12-porting-to-openccu-lite.md) |

For a complete settings page (HTML, CSS, JS, the config/service/password/certificate/firewall/
media/log/update CGIs) take ccu-addon-mosquitto's `addon_files/mosquitto/www/`; for a self-update
worker its `bin/mosquitto-update` or RedMatic's `bin/redmatic-update`.
