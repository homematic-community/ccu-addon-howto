# 07 Updates and releases

## Version schemes and tags

- Plain semver (`9.2.0`) for an addon with its own release cycle (RedMatic).
- `<upstream version>+<addon build>` (`2.1.2+0`, `2.1.2+1`) when the addon wraps one upstream
  program and wants a release per upstream release (ccu-addon-mosquitto). The old
  `1.5.8+4` releases proved that GitHub accepts a literal `+` in tag names and asset names; in
  URLs it is `%2B` (`releases/download/2.1.2%2B0/mosquitto-2.1.2%2B0.tar.gz`). A `-` suffix would
  read as a prerelease to semver-aware tools, so stay with `+`.
- The WebUI's update check compares strings only ([04](04-webui.md)); your own page should compare
  numerically, treat a prerelease as older than its release, and never offer a downgrade.
- Put the version into a `versions` (RedMatic) or `VERSION` file in the addon and let `info` read
  it; the build writes it from `package.json` or the repository's single source of truth.

## Assets

- One tarball per architecture, named consistently: RedMatic and the Mosquitto addon use no
  infix for armv7l (the historical CCU3 package name) and `-x86_64-` / `-aarch64-` for the others.
- A `.sha256` sibling per tarball with the **bare file name** in it (`sha256sum file > file.sha256`
  from inside `dist/`), so `sha256sum -c` works anywhere and a self-updater can verify.
- `releases/latest` of the GitHub API excludes drafts and prereleases, so automatic draft
  releases stay invisible to users until published.

## Self-update from the settings page

Both addons implement one-click updates (RedMatic task 11, Mosquitto task 5). The pattern:

1. `update.cgi?cmd=start&sid=...` starts a worker detached from lighttpd:
   `exec /usr/bin/setsid /bin/sh -c "$WORKER >/dev/null 2>&1 </dev/null" &`, otherwise the CGI
   would wait for it.
2. The worker copies itself to `/tmp/<name>-update/` first, because the install replaces the
   addon tree it lives in, and writes a small JSON state file (`phase`, `message`, `version`,
   `error`, `ts`) the page polls through `update.cgi?cmd=status` (no session needed for that,
   it exposes nothing). A pid file prevents two runs.
3. Resolve the newest version (`releases/latest`, `tag_name`), refuse when not newer unless forced.
4. Preflight: no other installer running (`ps | grep install_addon`), stale
   `/usr/local/tmp/tmp.*` directories from earlier CCU3 installs (release their mounts, remove),
   free space and **inodes** on `/usr/local` (the CCU3's chroot copy needs about 230 MB and 17k
   inodes on top of the package).
5. Download with `curl` to `/usr/local/tmp/new_addon.tar.gz.part` (the CCU3 firmware's curl 7.61
   and wget 1.19 reach GitHub over TLS), verify the `.sha256`, rename.
6. Install with `/bin/install_addon` when it exists (both firmwares; on the CCU3 this is a live
   chroot install without reboot, which works fine), otherwise unpack and run `update_script`
   by hand (debmatic, containers). Exit code 0 = done, 10 = reboot required.
7. Clean up the CCU3's leftover temp dir, check the installed version, start the service if the
   firmware did not (`update_script` cannot tell a live run from the chroot on the CCU3, so it
   never starts there), report `done` or `error` with the log.
8. The page shows phases and the log on error; because lighttpd serves the page, it survives the
   addon's own restart. Measured: 1 s on OpenCCU x86_64 for a 3 MB package, 6.5 minutes on the
   CCU3 for RedMatic's 60 MB package (the chroot copy dominates).

RedMatic's worker adds a progress model (download bytes, disk writes from `/proc/diskstats`
against measured per-platform durations); the Mosquitto worker just shows the phase. Sources:
[bin/redmatic-update](https://github.com/rdmtc/RedMatic/blob/master/addon_files/redmatic/bin/redmatic-update),
[bin/mosquitto-update](https://github.com/homematic-community/ccu-addon-mosquitto/blob/master/addon_files/mosquitto/bin/mosquitto-update).

## Automatic releases

A scheduled GitHub Actions workflow can keep an addon current without a maintainer in the loop:
check the upstream version (Node.js `index.json`, npm registry, Mosquitto's git tags), bump the
addon version, build all architectures, run the container e2e test, commit the bump, create the
release (draft unless a repository variable says publish), open an issue on failure. Keep major
upgrades manual: they usually change configuration semantics. Note that GitHub disables scheduled
workflows after 60 days without commits. Examples:
[RedMatic auto-release.yml](https://github.com/rdmtc/RedMatic/blob/master/.github/workflows/auto-release.yml),
[ccu-addon-mosquitto auto-release.yml](https://github.com/homematic-community/ccu-addon-mosquitto/blob/master/.github/workflows/auto-release.yml).

## Release notes

Generate the body: download links per architecture with badges, a hand-written notes file for
breaking changes, the commits since the last tag, the bundled component versions. Users read the
GitHub release page from the WebUI's download button, so the first lines must say which file is
for which platform. Both repositories have a `build_release_body.sh` to copy.
