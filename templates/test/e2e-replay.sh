#!/bin/bash
#
#   Skeleton of a container end-to-end test for a CCU addon package (MIT,
#   condensed from ccu-addon-mosquitto's test/e2e-inner.sh). Run inside
#   debian:bookworm-slim with the built x86_64 package mounted at /dist:
#
#     docker run --rm --platform linux/amd64 -v "$PWD/dist:/dist:ro" \
#         -v "$PWD/test/e2e-replay.sh:/e2e.sh:ro" debian:bookworm-slim bash /e2e.sh
#
#   It prepares what the CCU has, replays OpenCCU's /bin/install_addon for a
#   fresh install and an update, and leaves the addon-specific checks to you.
#

ADDON=mosquitto
ADDON_DIR=/usr/local/addons/$ADDON
CONF_DIR=/usr/local/etc/config
RC=$CONF_DIR/rc.d/$ADDON
PKG=$(ls /dist/*x86_64*.tar.gz | head -1)
FAILED=0

log() { echo ""; echo "### $*"; }
ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*"; FAILED=1; }
die() { echo "FAIL: $*"; tail -40 /var/log/messages 2>/dev/null; exit 1; }

# --- what the CCU has ---------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null || die "apt-get update"
# tcl: update_addon and the CGI helpers are tclsh scripts like on the CCU
apt-get install -y -qq --no-install-recommends curl ca-certificates iproute2 procps busybox openssl tcl >/dev/null || die "apt-get install"
busybox syslogd -O /var/log/messages || die "syslogd"
mkdir -p /usr/local/tmp $CONF_DIR/rc.d $CONF_DIR/addons/www /etc/config
# the CCU runs the addon scripts with busybox ash, not dash
ln -sf /bin/busybox /bin/sh
# a CCU-style server.pem: certificate and key in one file
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 30 -subj "/CN=e2e-ccu" \
    -keyout /tmp/ccu.key -out /tmp/ccu.crt 2>/dev/null || die "openssl"
cat /tmp/ccu.crt /tmp/ccu.key > /etc/config/server.pem

# what OpenCCU's /bin/install_addon does: extract into a temp dir below
# /usr/local/tmp, run update_script from inside it, delete the temp dir
install_addon() {
    local dir rc
    dir=$(mktemp -d -p /usr/local/tmp)
    tar -C "$dir" --no-same-owner --no-same-permissions -xf "$PKG" || die "extract"
    (cd "$dir" && ./update_script HM-RASPBERRYMATIC >/tmp/update_script.log 2>&1)
    rc=$?
    rm -rf "$dir"
    return $rc
}

# --- fresh install ------------------------------------------------------------
log "fresh install (update_script must exit 10)"
install_addon; rc=$?
[ $rc -eq 10 ] || { cat /tmp/update_script.log; die "update_script exit code $rc, expected 10"; }
[ -x $RC ] || die "rc.d link missing"
[ -L $CONF_DIR/addons/www/$ADDON ] || die "www link missing"
grep -q "^$ADDON " $CONF_DIR/hm_addons.cfg || fail "hm_addons.cfg has no entry"
$RC info | grep -q "^Name: " || fail "info has no Name line"
ok "installed"

log "start"
$RC start || die "start"
sleep 2
$RC status | grep -q '"running":true' || die "not running after start"
ok "running"
# >>> your functional checks here (ports, round trips, CGI behaviour that needs no session)

# --- update -------------------------------------------------------------------
log "update with the same package (exit 0, service restarted, user data kept)"
install_addon; rc=$?
[ $rc -eq 0 ] || { cat /tmp/update_script.log; die "update_script exit code $rc, expected 0"; }
sleep 2
$RC status | grep -q '"running":true' || die "not running after the update"
ok "updated"
# >>> migration checks: prepare an old layout in $ADDON_DIR/etc, install again, assert the result

# --- stop, uninstall ------------------------------------------------------------
log "stop and uninstall"
$RC stop; sleep 1
$RC status | grep -q '"running":false' || fail "still running after stop"
$RC uninstall >/dev/null
[ -d $ADDON_DIR ] && fail "addon dir still there"
[ -e $RC ] && fail "rc.d link still there"
[ -e $CONF_DIR/addons/www/$ADDON ] && fail "www link still there"
grep -q "^$ADDON " $CONF_DIR/hm_addons.cfg 2>/dev/null && fail "hm_addons.cfg entry still there"
ok "uninstalled"

echo ""
[ $FAILED -eq 0 ] && { echo "### e2e: PASSED"; exit 0; }
echo "### e2e: FAILED"; exit 1
