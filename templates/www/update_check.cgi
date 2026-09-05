#!/bin/tclsh
#
#   Update check CGI (MIT, from ccu-addon-mosquitto), the "Update:" URL of
#   the rc.d info output. The Zusatzsoftware page fetches
#   ?cmd=check_version&version=<installed> and shows the response text
#   verbatim as the available version ("n/a" when unknown); the download
#   button opens ?cmd=download&version=<installed>. OpenCCU's daily
#   checkAddonUpdates.sh curls the bare URL and compares the lower-cased
#   response with the installed version string.
#
#   releases/latest excludes drafts and prereleases, so users only ever
#   see published releases. Tcl 8.2 compatible.
#

set checkURL    "https://api.github.com/repos/OWNER/REPO/releases/latest"
set downloadURL "https://github.com/OWNER/REPO/releases/latest"

source ../lib/querystring.tcl

if {[info exists cmd] && $cmd == "download"} {
    puts -nonewline "Content-Type: text/html; charset=utf-8\r\n\r\n"
    puts "<html><head><meta http-equiv='refresh' content='0; url=$downloadURL' /></head></html>"
    exit 0
}

puts -nonewline "Content-Type: text/plain; charset=utf-8\r\n\r\n"
catch {
    # tag names like 2.1.2+0 or v9.2.0; adjust the pattern to your scheme
    regexp {"tag_name":\s*"v?([0-9]+\.[0-9]+\.[0-9]+[^"]*)"} [exec /usr/bin/env curl -fsSL --max-time 15 $checkURL] dummy newversion
}
if {[info exists newversion]} {
    puts -nonewline $newversion
} else {
    puts -nonewline "n/a"
}
