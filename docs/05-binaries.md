# 05 Binaries

There is no compiler, no package manager and no `apt` on a CCU. Whatever native code your addon
needs must arrive inside the package, built elsewhere, and must run against the firmware's kernel
without depending on the firmware's libraries.

## Why the firmware's libc is a trap

- The original CCU3 firmware has **glibc 2.27** (Buildroot 2018.08). Every Node.js binary since
  Node 18 wants `GLIBC_2.28`, current OpenSSL and most distro builds want newer symbol versions.
  OpenCCU has a current glibc, so a glibc binary built on a recent distro runs on OpenCCU and dies
  on the CCU3 with `version GLIBC_2.xx not found`.
- Firmware updates replace `/lib` and `/usr/lib`; the CCU2/CCU1 practice of copying `.so` files
  into `/lib` at boot is gone for good.
- The CCU3 firmware ships OpenSSL 1.0.2 and 1.1 (`/usr/lib/libssl.so.1.0.0`), OpenCCU 3.x, so
  even "just link against the system OpenSSL" gives two incompatible targets.

## The approach that works: self-contained musl binaries

Both RedMatic 9 (Node.js 24, git) and ccu-addon-mosquitto (Mosquitto 2.1) ship binaries built
against **musl** from Alpine Linux together with the musl loader and every shared library they
need, and make them find each other without touching the environment:

1. Get the binaries: either the Alpine packages (`.apk` files are gzipped tars; RedMatic's
   [`alpine-packages.mjs`](https://github.com/rdmtc/RedMatic/blob/master/alpine-packages.mjs)
   resolves the dependency closure from `APKINDEX.tar.gz` without an `apk` binary), or build
   from source **inside an Alpine container of the target architecture** (`docker run --platform
   linux/arm/v7 alpine:3.22`, ARM via qemu/binfmt: `docker run --privileged --rm tonistiigi/binfmt
   --install arm,arm64`). The source build lets you switch features off; Alpine's Mosquitto package
   pulls in libmicrohttpd, gnutls, nettle, gmp, p11-kit, sqlite, libwebsockets and editline for
   features the addon never uses (17 MB instead of 7.7 MB).
2. Copy the executables plus the transitive `DT_NEEDED` closure (`patchelf --print-needed`,
   follow symlinks, `readlink -f`) and the interpreter (`patchelf --print-interpreter`, e.g.
   `/lib/ld-musl-armhf.so.1`) into `lib/` of the addon.
3. Rewrite every executable: `patchelf --set-interpreter /usr/local/addons/<name>/lib/ld-musl-*.so.1
   --set-rpath '/usr/local/addons/<name>/lib:$ORIGIN/../lib'`. Plugins that are `dlopen`ed get an
   RPATH too. musl resolves a library's own dependencies through the RPATH of the whole
   `needed_by` chain up to the executable, so executables (and dlopen'ed plugins) are enough.
4. Self-check at build time: every needed library present in `lib/`, interpreter inside the
   prefix. Strip the binaries (`strip`; busybox `install` has no `--strip-program`).
5. **Never export `LD_LIBRARY_PATH`** globally or in the rc.d script: the firmware's glibc
   binaries you call from the same environment (`curl`, `openssl`, `tclsh`) would pick up the
   same-named musl `libcrypto.so.3` and crash. The old Mosquitto addon did exactly that; the
   RPATH approach needs no environment at all.
6. Data files a library expects at a compiled-in path (Node's ICU data under `/usr/share/icu`)
   ship inside the addon and are pointed to through an environment variable that only your own
   loader script exports (`ICU_DATA`).

Fully static musl binaries avoid patchelf entirely but cannot `dlopen` plugins; choose static for
single-binary tools, dynamic-with-RPATH for anything with plugins.

## Architecture details

- armv7l packages run on every armv7 board and, through the compat loader, also on aarch64
  OpenCCU; still build a native aarch64 package, it is faster and the compat loader is not
  guaranteed (`/lib/ld-linux-armhf.so.3` exists on OpenCCU aarch64 3.89.8, i386's
  `/lib/ld-linux.so.2` on x86_64).
- Alpine's armv7 packages target ARMv7-A with VFPv3-D16 hard float, which is what the CCU3's
  Cortex-A53 (in 32-bit mode) and OpenCCU rpi2/tinkerboard run.
- Check `uname -m` in `update_script` and refuse a wrong package (exit 13).
- Build time under qemu: Mosquitto compiles in about two minutes per ARM target on GitHub's
  runners; Node.js is not compiled at all, Alpine's binary is taken.

## Sizes

ccu-addon-mosquitto: 7.7 MB unpacked, 2.7 MB (armv7l) to 3.6 MB (aarch64) compressed per
architecture, of which OpenSSL's `libcrypto.so.3` is 4.5 MB. RedMatic 9: about 60 MB compressed
with Node.js, npm, git and Node-RED. The CCU3's `/usr/local` is 2 GB with 96k inodes; count
inodes for anything with `node_modules`.

Sources: [RedMatic build_addon.sh](https://github.com/rdmtc/RedMatic/blob/master/build_addon.sh),
[ccu-addon-mosquitto build_addon.sh](https://github.com/homematic-community/ccu-addon-mosquitto/blob/master/build_addon.sh)
and `build_in_container.sh`, musl's `ldso/dynlink.c` (RPATH search walks `needed_by`).
