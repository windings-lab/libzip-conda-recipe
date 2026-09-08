# libzip conda recipe

A conda recipe for [libzip](https://libzip.org/) 1.11.4 — a C library for reading,
creating and modifying zip archives.

libzip was chosen because it exercises the parts of package building that
actually tend to break: it is compiled from C sources with CMake, it links
against five external libraries (zlib, bzip2, xz, Zstandard, OpenSSL), each of
which is *optional* from CMake's point of view, and it installs a shared
library, public headers, CMake package config files, pkg-config metadata and
three command line tools.

| | |
|---|---|
| Package | `libzip 1.11.4` |
| Published at | https://anaconda.org/gasterlab/libzip |
| Built and tested on | `linux-64` (see [Verified build](#verified-build)) |
| Recipe also covers | `win-64`, `osx-64`, `osx-arm64` |
| Source | https://github.com/nih-at/libzip/releases/tag/v1.11.4 |

```bash
conda install -c gasterlab libzip
```

## Layout

Everything lives in the repository root, so the repository *is* the recipe
directory and `conda build .` works from a fresh clone.

| File | Purpose |
|---|---|
| `meta.yaml` | Package metadata, dependencies, and the test section |
| `build.sh` | Build script for Linux and macOS |
| `bld.bat` | Build script for Windows |
| `conda_build_config.yaml` | Toolchain selection and the OpenSSL pin |
| `test_libzip.c` | Smoke test compiled and run against the installed package |
| `CMakeLists.txt` | Consumer project for the smoke test — does **not** build libzip |
| `.github/workflows/conda-build.yml` | Builds on Linux and Windows; uploads on tags |

## Building

```bash
# Miniforge or any conda install with conda-build available
conda install -n base conda-build anaconda-client

git clone https://github.com/windings-lab/libzip-conda-recipe.git
cd libzip-conda-recipe

conda build . -c conda-forge --override-channels
```

Install the result and try it:

```bash
conda create -n libzip-test -c local -c conda-forge libzip
conda activate libzip-test
ziptool -h
```

Or install the published build straight from anaconda.org:

```bash
conda create -n libzip-test -c gasterlab -c conda-forge libzip
```

## What the recipe does

`build.sh` / `bld.bat` configure an out-of-source CMake build with every
optional backend explicitly turned on:

* `ENABLE_BZIP2`, `ENABLE_LZMA`, `ENABLE_ZSTD` — the bzip2, XZ and Zstandard
  compression methods
* `ENABLE_OPENSSL` — AES-128/192/256 encryption
* `BUILD_TOOLS` — `zipcmp`, `zipmerge` and `ziptool`

Turning an option *on* is not enough, though. libzip's CMake silently drops a
backend when it cannot find the corresponding library, and the package still
builds, still links and still handles plain deflate archives — the damage only
surfaces later, in whatever downstream package tries to read a
zstd-compressed or encrypted entry. Both build scripts therefore grep the
generated `config.h` for `HAVE_LIBBZ2`, `HAVE_LIBLZMA`, `HAVE_LIBZSTD` and
`HAVE_CRYPTO` and fail the build if any of them is missing.

The upstream regression suite (`BUILD_REGRESS`) is disabled because it is
driven by `nihtest`, which is not packaged for conda. The `test:` section
compensates: it builds `test_libzip.c` against the *installed* package through
the exported CMake targets, and the resulting binary asks libzip at runtime
which methods it supports before round-tripping one archive entry through each
of them.

## Problems hit while writing this recipe

Three issues came up that are worth recording, because none of them produces an
obvious error message.

**1. `liblzma` alone is not enough.** conda-forge splits the xz project into
`liblzma` (runtime) and `liblzma-devel` (headers plus the linker symlink).
With only `liblzma` in `host:`, `find_package(LibLZMA)` fails, CMake reports
`Could NOT find LibLZMA` in the middle of several hundred lines of output, and
the build happily continues without XZ support. Fixed by depending on
`liblzma-devel`; the `config.h` check described above now catches any
recurrence.

**2. An unpinned `cmake` in `test: requires` resolved to cmake 3.5.** The build
environment got cmake 4.4.3 while the test environment was solved separately
and satisfied with a decade-old build that has neither `-S`/`-B` (CMake 3.13)
nor `ctest --test-dir` (3.20). The test failed with
`The source directory ".../build-test" does not exist`, which points nowhere
near the real cause. Fixed with `cmake >=3.20`.

**3. OpenSSL 4.0.1 makes the package uninstallable.** conda-forge already
publishes openssl 4.0.1, so an unpinned `openssl` in `host:` builds against it
and `run_exports` then pins `openssl >=4.0.1,<5.0a0` into the finished package.
But `libcurl` — and therefore `cmake`, `git` and much of the rest of the
toolchain — is still built against openssl 3, so nothing that needs cmake can
be co-installed with the result. This was in fact the reason the solver
reached for cmake 3.5 in the first place: it was the only cmake old enough to
carry no libcurl dependency. `conda_build_config.yaml` pins `openssl: '3'`
until that migration lands upstream.

## Verified build

Built on Arch Linux (glibc 2.42, kernel 7.1.9) with conda-build 26.7.1 against
conda-forge, targeting the glibc 2.17 sysroot:

```
libzip-1.11.4-hffcc938_0.conda   (linux-64, 119 KiB)

depends:
  __glibc >=2.17,<3.0.a0     libgcc >=16
  bzip2 >=1.0.8,<2.0a0       liblzma >=5.8.3,<6.0a0
  libzlib >=1.3.2,<2.0a0     openssl >=3.6.4,<4.0a0
  zstd >=1.5.7,<1.6.0a0
```

The runtime bounds above are not written by hand — every host dependency ships
`run_exports`, so conda-build derives them from what was actually linked. The
package itself exports `pin_subpackage('libzip', max_pin='x.x')`, matching
upstream's `libzip.so.5` soname.

Smoke test output from a clean environment:

```
libzip 1.11.4 (compiled against 1.11.4)
PASS  deflate (zlib) supported
PASS  bzip2 supported
PASS  xz (liblzma) supported
PASS  zstd supported
PASS  AES-256 (openssl) supported
PASS  archive holds 6 entries
PASS  read back store.txt unchanged
PASS  read back deflate.txt unchanged
PASS  read back bzip2.txt unchanged
PASS  read back xz.txt unchanged
PASS  read back zstd.txt unchanged
PASS  read back aes256.txt unchanged

all checks passed
```

And the linkage it asserts:

```
$ ldd $CONDA_PREFIX/lib/libzip.so.5
libbz2.so.1.0   => $CONDA_PREFIX/lib/./libbz2.so.1.0
liblzma.so.5    => $CONDA_PREFIX/lib/./liblzma.so.5
libzstd.so.1    => $CONDA_PREFIX/lib/./libzstd.so.1
libcrypto.so.3  => $CONDA_PREFIX/lib/./libcrypto.so.3
libz.so.1       => $CONDA_PREFIX/lib/./libz.so.1
```
