# 04 WebUI integration

Three touch points: the *Einstellungen* button, the update check on the Zusatzsoftware page, and
your own settings page served by the CCU's lighttpd.

## The Einstellungen button: hm_addons.cfg

The button in *Einstellungen > Systemsteuerung > Zusatzsoftware* comes from
`/usr/local/etc/config/hm_addons.cfg`. The file is a flat Tcl list as written by `array get`:
`<id> {<dict>} <id> {<dict>} ...`, where each dict has the keys `ID`, `CONFIG_URL`,
`CONFIG_NAME` and `CONFIG_DESCRIPTION` (itself `de {<li>...</li>} en {<li>...</li>}`):

```
mosquitto {CONFIG_URL /addons/mosquitto/settings.cgi CONFIG_DESCRIPTION {de {<li>Mosquitto MQTT Broker</li>} en {<li>Mosquitto MQTT Broker</li>}} ID mosquitto CONFIG_NAME Mosquitto}
```

The firmware's own API is `::HomeMatic::Addon::AddConfigPage id url name description` in
`package require HomeMatic` (`/lib/tcl8.2/homematic/homematic.tcl` on the CCU3,
`/usr/lib/tcl8.6/homematic/` on OpenCCU). OpenCCU adds `RemoveConfigPage` through its patch
[0034-WebUI-Addon-Config](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/patches/occu/0034-WebUI-Addon-Config.patch)
and a command line wrapper
[`/bin/updateAddonConfig.tcl -a id -url ... -name ... -de ... -en ...` / `-d id`](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base-openccu/bin/updateAddonConfig.tcl);
the original CCU3 firmware has neither the removal nor the wrapper. So ship your own tiny
tclsh script that reads the file with `array set`, sets or unsets `addons(<id>)` and writes
`array get` back: [templates/bin/update_addon](../templates/bin/update_addon). It works on Tcl 8.2
and in a test container. (RedMatic carries i386/armv7 ELF helpers named `update_addon` for this;
they only run through the CCUs' 32-bit compat loaders and not at all in an x86_64 container.)

Call it from `update_script` after `touch hm_addons.cfg`, and with only the id from `uninstall`.
The `Config-Url` in your rc.d `info` output makes the same button appear in the Zusatzsoftware
list; `hm_addons.cfg` puts it into the Systemsteuerung overview.

## The update check on the Zusatzsoftware page

For every addon whose `info` has an `Update:` line, the page fetches
`<Update URL>?cmd=check_version&version=<installed>` with `XMLHttpRequest` and writes the
**response text as-is** into the "available version" cell (initially `n/a`). The download button
opens `<Update URL>?cmd=download&version=<installed>` in a new window. OpenCCU's daily
`checkAddonUpdates.sh` additionally curls the bare `Update:` URL and reports "Update available"
when the lower-cased response differs from `Version:` and is not `n/a`.

So the CGI returns plain text: the newest version string, or `n/a`; and on `cmd=download` an HTML
redirect to your release page. Query the GitHub releases API (`/repos/<owner>/<repo>/releases/latest`
excludes drafts and prereleases) rather than a raw file on the default branch, so users only see
real releases. See [templates/www/update_check.cgi](../templates/www/update_check.cgi). Note the
CCU compares strings, not versions: if you show prereleases in your own page, compare properly
there ([07](07-updates-and-releases.md)).

## Serving pages and CGIs

lighttpd serves `/addons/` from `/usr/local/etc/config/addons/www` (the `/www/addons` symlink)
and passes it through even when the WebUI proxy rules are active
([webui.conf](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/etc/lighttpd/conf.d/webui.conf):
`/addons` is in the exclusion list; the CCU3 firmware's `proxy_normal.conf` has the same list).
[cgi.conf](https://github.com/OpenCCU/OpenCCU/blob/master/buildroot-external/overlay/base/etc/lighttpd/conf.d/cgi.conf)
assigns `.cgi` to `/bin/tclsh` and enables `X-Sendfile` for `/usr/local/tmp` (that is how a CGI
hands out a big download: build the file there, print `X-Sendfile: /usr/local/tmp/x.tar.gz`).
Index files are `index.htm`, `index.html`, `index.cgi`.

Facts about the CGI environment, all verified on both firmwares:

- The CGI's working directory is its own directory (resolved through the symlink), so
  `source ../lib/session.tcl` reaches `/usr/local/addons/<name>/lib/`.
- `PATH` lacks `/sbin` and `/usr/sbin`: call `/sbin/ip`, `/usr/sbin/iptables` with full paths.
- Nothing is cached; a CGI runs as root on every request. Keep the per-request work small and
  never do slow network calls from a CGI that the page polls.
- A Tcl error before the header is printed gives a lighttpd 500 with the WebUI's "not ready"
  page as body; the message itself is only visible when you run the CGI by hand:
  `cd /usr/local/addons/<name>/www && QUERY_STRING='cmd=status' tclsh service.cgi`.
- Your own HTTP server (Node-RED, a REST API) is reached through a proxy rule in
  `/usr/local/etc/config/lighttpd/<name>.conf` (see RedMatic's `etc/lighttpd.conf`), restart
  lighttpd once after creating it (`/etc/init.d/S50lighttpd restart`).

## The CCU session

The WebUI opens `Config-Url?sid=@xxxxxxxxxx@` (ten alphanumerics between `@`). Every CGI that
reads or changes anything must validate that id, otherwise anyone on the LAN can reconfigure the
addon without logging in. The check is a ReGaHSS script through `tclrega.so`:

```tcl
load tclrega.so
proc check_session sid {
    if {[regexp {@([0-9a-zA-Z]{10})@} $sid all sidnr]} {
        set res [lindex [rega_script "Write(system.GetSessionVarStr('$sidnr'));"] 1]
        if {$res != ""} { return 1 }
    }
    return 0
}
```

([templates/lib/session.tcl](../templates/lib/session.tcl); the same call is what
`cp_software.cgi` uses to find the user name.) Pass the sid on to every request your page makes.
Read-only status polls that expose nothing sensitive (pid, version) may skip the check to keep the
polling cheap, everything else must not. Sessions expire; show a "session invalid, close this
page" overlay when a CGI answers with your error marker.

For scripted tests get a session from the JSON API: `POST /api/homematic.cgi` with
`{"method":"Session.login","params":{"username":"Admin","password":"..."}}` returns
`"result": "<id>"` (note the space); use it as `@<id>@`, log out with `Session.logout`.

## Change state only on a POST

**A CGI changes state only on a POST; a GET only shows.** A link such as
`settings.cgi?cmd=config&mode=x` or `service.cgi?cmd=restart` fires from anything that makes the
browser load it: a link or a redirect on another site, an `<img>`, a prefetch. The session check
does not help when the credential travels on its own: your own login cookie, openccu-lite's
session cookie (`SameSite=Lax`, which a top-level navigation carries), or a `?sid=` that leaked
through a `Referer` or a log.

- Make every former link a button in a small `<form method="post">`, or a `fetch` with
  `method: 'POST'`.
- Read the fields from the body (`CONTENT_LENGTH` bytes of stdin,
  `application/x-www-form-urlencoded`) and ignore change fields in the query. On Tcl 8.2 that is
  `read stdin $len`; `read_form` in [templates/lib/querystring.tcl](../templates/lib/querystring.tcl)
  does it and reads nothing unless the request is a POST.
- Keep the session check on the POST; the `sid` may stay in the query.

**lighttpd on the CCU3 and OpenCCU answers a POST without `Content-Length` with `411 Length
Required`** before the CGI runs, for example `curl -X POST` with no body. Send a body, even an
empty one (`curl --data ''`); a browser's `fetch` with an empty body already sends
`Content-Length: 0`. openccu-lite takes such a POST as an empty body
([11](11-openccu-lite.md#how-pages-are-served)), but the same addon still runs on the other two.

## Tcl on the CCU: write for 8.2

The original CCU3 firmware runs **Tcl 8.2.3** (`/lib/tcl8.2`), OpenCCU 8.6. Code that passes on
OpenCCU can be a syntax error on the CCU3. Verified list of things that do not exist in 8.2:

| Not in 8.2 | Use instead |
| --- | --- |
| `dict` | a flat key/value list with `lsearch -exact`, or `array set` |
| `{*}$args` | `eval cmd $args` (args must be a proper list) |
| `eq`, `ne`, `in` in `expr` | `==`, `!=` (strings compare fine), `string equal`, `lsearch` |
| `exec ... 2>@1` | `exec sh -c "cmd 2>&1"` with shell-quoted arguments (a `run` helper, see [templates/lib/querystring.tcl](../templates/lib/querystring.tcl)) |
| `regsub pattern string repl` returning the result | `regsub pattern string repl var` |
| `scan $hex %x` returning the value | `scan $hex %x var` |
| `lassign`, `lrepeat`, `lset`, `string is` with `-strict`, `apply`, `try` | plain list ops, `catch` |
| `file normalize`, `glob -directory` | build paths by hand |

Also: never `subst` user input (a query string containing `[exec ...]` would run), decode URL
parameters character by character, quote every argument you pass to `sh -c`, and put a literal
`{` only outside braced `if {...}` conditions (Tcl counts braces inside strings there: a
`string match "{*"` inside `if {}` is "missing close-brace" and a 500). `tclsh` on the CCU3 also
lacks `json`, `http` and `tls` packages; use `curl` or `wget` via `exec`.

## Designing the page

What worked well for RedMatic and ccu-addon-mosquitto:

- One `settings.cgi` that checks the session and serves a static `settings.html`; small
  single-purpose CGIs behind it (`getconfig`, `setconfig`, `service`, `passwd`, `cert`,
  `firewall`, `media`, `log`, `update`, `update_check`); one CSS, one JS, no framework (RedMatic's
  Bootstrap + jQuery + Font Awesome bundle is 2 MB; a hand-written card stylesheet is 5 KB).
- Passwords and other secrets travel in the POST body as `application/x-www-form-urlencoded`,
  never in the query string (lighttpd logs it).
- Validate what you write before you install it: Mosquitto has `--test-config`, Node-RED a
  settings loader; a broken config that stops the daemon is the worst user experience.
- Show the daemon status and, when it is stopped, the last error line from `/var/log/messages`
  so a failed start explains itself ("Address in use", bad certificate).
- The page is served by lighttpd, not by your daemon, so it keeps working while your daemon
  restarts or updates itself: that is what makes a self-update with progress feedback possible ([07](07-updates-and-releases.md)).
- German is the WebUI's primary language; RedMatic and the Mosquitto addon are German with an
  English README.
