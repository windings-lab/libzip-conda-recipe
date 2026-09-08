/*
 * Smoke test for the libzip conda package.
 *
 * This is deliberately more than a "does it link" check.  libzip's CMake turns
 * an optional backend off whenever it fails to find the corresponding library,
 * and the resulting package still builds, still links and still opens plain
 * deflate archives -- the breakage only shows up much later, in whatever
 * downstream package tries to read a zstd-compressed or AES-encrypted entry.
 *
 * So the test asks libzip at runtime which methods it actually supports, and
 * then round-trips one archive entry through each of them.
 */

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <zip.h>

#define ARCHIVE "test_libzip.zip"
#define PASSWORD "conda-build"

static int failures = 0;

static void check(int ok, const char *fmt, ...) {
    va_list ap;
    printf("%s  ", ok ? "PASS" : "FAIL");
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    putchar('\n');
    if (!ok) {
        failures++;
    }
}

/* A payload that is long and repetitive enough for every codec to do work. */
static char payload[8192];

struct entry {
    const char *name;
    zip_int32_t method;
    zip_uint16_t encryption;
};

static const struct entry entries[] = {
    {"store.txt",     ZIP_CM_STORE,   ZIP_EM_NONE},
    {"deflate.txt",   ZIP_CM_DEFLATE, ZIP_EM_NONE},
    {"bzip2.txt",     ZIP_CM_BZIP2,   ZIP_EM_NONE},
    {"xz.txt",        ZIP_CM_XZ,      ZIP_EM_NONE},
    {"zstd.txt",      ZIP_CM_ZSTD,    ZIP_EM_NONE},
    {"aes256.txt",    ZIP_CM_DEFLATE, ZIP_EM_AES_256},
};

static const size_t n_entries = sizeof(entries) / sizeof(entries[0]);

static int write_archive(void) {
    zip_t *za;
    int err = 0;
    size_t i;

    if ((za = zip_open(ARCHIVE, ZIP_CREATE | ZIP_TRUNCATE, &err)) == NULL) {
        zip_error_t error;
        zip_error_init_with_code(&error, err);
        fprintf(stderr, "cannot create %s: %s\n", ARCHIVE, zip_error_strerror(&error));
        zip_error_fini(&error);
        return -1;
    }

    for (i = 0; i < n_entries; i++) {
        zip_source_t *src;
        zip_int64_t idx;

        /* The buffer must stay valid until zip_close(), which it does: it is
           a file-scope array. */
        if ((src = zip_source_buffer(za, payload, sizeof(payload), 0)) == NULL) {
            fprintf(stderr, "zip_source_buffer: %s\n", zip_strerror(za));
            zip_discard(za);
            return -1;
        }

        if ((idx = zip_file_add(za, entries[i].name, src, ZIP_FL_ENC_UTF_8)) < 0) {
            fprintf(stderr, "zip_file_add(%s): %s\n", entries[i].name, zip_strerror(za));
            zip_source_free(src);
            zip_discard(za);
            return -1;
        }

        if (zip_set_file_compression(za, (zip_uint64_t)idx, entries[i].method, 0) < 0) {
            fprintf(stderr, "zip_set_file_compression(%s): %s\n",
                    entries[i].name, zip_strerror(za));
            zip_discard(za);
            return -1;
        }

        if (entries[i].encryption != ZIP_EM_NONE &&
            zip_file_set_encryption(za, (zip_uint64_t)idx, entries[i].encryption,
                                    PASSWORD) < 0) {
            fprintf(stderr, "zip_file_set_encryption(%s): %s\n",
                    entries[i].name, zip_strerror(za));
            zip_discard(za);
            return -1;
        }
    }

    if (zip_close(za) < 0) {
        fprintf(stderr, "zip_close: %s\n", zip_strerror(za));
        zip_discard(za);
        return -1;
    }

    return 0;
}

static void read_archive(void) {
    zip_t *za;
    int err = 0;
    size_t i;

    if ((za = zip_open(ARCHIVE, ZIP_RDONLY, &err)) == NULL) {
        zip_error_t error;
        zip_error_init_with_code(&error, err);
        fprintf(stderr, "cannot open %s: %s\n", ARCHIVE, zip_error_strerror(&error));
        zip_error_fini(&error);
        failures++;
        return;
    }

    zip_set_default_password(za, PASSWORD);

    check(zip_get_num_entries(za, 0) == (zip_int64_t)n_entries,
          "archive holds %zu entries", n_entries);

    for (i = 0; i < n_entries; i++) {
        static char buf[sizeof(payload)];
        zip_file_t *zf;
        zip_int64_t got;

        if ((zf = zip_fopen(za, entries[i].name, 0)) == NULL) {
            check(0, "read back %s: %s", entries[i].name, zip_strerror(za));
            continue;
        }

        got = zip_fread(zf, buf, sizeof(buf));
        zip_fclose(zf);

        check(got == (zip_int64_t)sizeof(payload) &&
                  memcmp(buf, payload, sizeof(payload)) == 0,
              "read back %s unchanged", entries[i].name);
    }

    zip_close(za);
}

int main(void) {
    size_t i;

    memset(payload, 0, sizeof(payload));
    for (i = 0; i + 1 < sizeof(payload); i++) {
        payload[i] = (char)('a' + (i % 26));
    }

    printf("libzip %s (compiled against %s)\n",
           zip_libzip_version(), LIBZIP_VERSION);

    /* Each of these maps onto one host dependency of the recipe.  If any is
       missing, the package was built without a library it claims to use. */
    check(zip_compression_method_supported(ZIP_CM_DEFLATE, 1), "deflate (zlib) supported");
    check(zip_compression_method_supported(ZIP_CM_BZIP2, 1), "bzip2 supported");
    check(zip_compression_method_supported(ZIP_CM_XZ, 1), "xz (liblzma) supported");
    check(zip_compression_method_supported(ZIP_CM_ZSTD, 1), "zstd supported");
    check(zip_encryption_method_supported(ZIP_EM_AES_256, 1), "AES-256 (openssl) supported");

    if (failures == 0) {
        if (write_archive() == 0) {
            read_archive();
        } else {
            failures++;
        }
    } else {
        fprintf(stderr, "skipping the round-trip: required features are missing\n");
    }

    remove(ARCHIVE);

    if (failures != 0) {
        fprintf(stderr, "\n%d check(s) failed\n", failures);
        return EXIT_FAILURE;
    }

    printf("\nall checks passed\n");
    return EXIT_SUCCESS;
}
