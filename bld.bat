setlocal EnableDelayedExpansion

mkdir build
cd build
if errorlevel 1 exit /b 1

:: CMAKE_ARGS comes first so the options below override it
:: ENABLE_WINDOWS_CRYPTO is off to keep OpenSSL as the AES backend everywhere
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

:: CMake drops an optional backend silently when its library is missing
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
