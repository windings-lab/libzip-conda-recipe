:: Build script for the libzip conda package (Windows).
setlocal EnableDelayedExpansion

mkdir build
cd build
if errorlevel 1 exit /b 1

:: %CMAKE_ARGS% is exported by the conda compiler activation scripts; it must
:: come first so the options below can still override it.
:: %LIBRARY_PREFIX% is %PREFIX%\Library, the place conda expects native
:: headers/libraries/binaries to land on Windows.
cmake %CMAKE_ARGS% ^
    -G "Ninja" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DCMAKE_INSTALL_LIBDIR=lib ^
    -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
    -DBUILD_SHARED_LIBS=ON ^
    -DENABLE_BZIP2=ON ^
    -DENABLE_LZMA=ON ^
    -DENABLE_ZSTD=ON ^
    -DENABLE_OPENSSL=ON ^
    -DENABLE_GNUTLS=OFF ^
    -DENABLE_MBEDTLS=OFF ^
    -DENABLE_COMMONCRYPTO=OFF ^
    -DENABLE_WINDOWS_CRYPTO=OFF ^
    -DBUILD_TOOLS=ON ^
    -DBUILD_EXAMPLES=OFF ^
    -DBUILD_DOC=OFF ^
    -DBUILD_OSSFUZZ=OFF ^
    -DBUILD_REGRESS=OFF ^
    ..
if errorlevel 1 exit /b 1

:: ENABLE_WINDOWS_CRYPTO is off on purpose: OpenSSL is already a host
:: dependency for every platform, so using it here keeps the AES implementation
:: identical across Linux, macOS and Windows instead of silently switching to
:: the Windows CNG backend only on this one platform.

:: libzip's CMake silently disables an optional backend when it cannot find the
:: library.  config.h records what was really enabled, so refuse to ship a
:: package that is missing the features this recipe advertises.
for %%M in (HAVE_LIBBZ2 HAVE_LIBLZMA HAVE_LIBZSTD HAVE_CRYPTO) do (
    findstr /b /c:"#define %%M" config.h >nul
    if errorlevel 1 (
        echo ERROR: %%M is not set; an optional dependency was not found
        type config.h
        exit /b 1
    )
)

cmake --build . --parallel %CPU_COUNT%
if errorlevel 1 exit /b 1

cmake --install .
if errorlevel 1 exit /b 1
