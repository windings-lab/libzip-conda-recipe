#include <zip.h>

#include <array>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <format>
#include <iostream>
#include <ostream>
#include <span>
#include <stdexcept>
#include <string>

namespace {

constexpr const char* kArchive = "test_libzip.zip";
constexpr const char* kPassword = "conda-build";
constexpr std::size_t kPayloadSize = 8192;

struct Spec {
    const char* name;
    zip_int32_t method;
    zip_uint16_t encryption;
    const char* backend;
};

constexpr std::array<Spec, 6> kSpecs{{
    {"store.txt", ZIP_CM_STORE, ZIP_EM_NONE, "store"},
    {"deflate.txt", ZIP_CM_DEFLATE, ZIP_EM_NONE, "deflate (zlib)"},
    {"bzip2.txt", ZIP_CM_BZIP2, ZIP_EM_NONE, "bzip2"},
    {"xz.txt", ZIP_CM_XZ, ZIP_EM_NONE, "xz (liblzma)"},
    {"zstd.txt", ZIP_CM_ZSTD, ZIP_EM_NONE, "zstd"},
    {"aes256.txt", ZIP_CM_DEFLATE, ZIP_EM_AES_256, "AES-256 (openssl)"},
}};

class Report {
public:
    explicit Report(std::ostream& out) : mOut{out} {}

    void check(bool ok, const std::string& what) {
        mOut << (ok ? "PASS  " : "FAIL  ") << what << '\n';
        if (!ok) {
            ++mFailures;
        }
    }

    bool clean() const noexcept { return mFailures == 0; }
    int failures() const noexcept { return mFailures; }

private:
    std::ostream& mOut;
    int mFailures = 0;
};

zip_t& openArchive(const char* path, int flags) {
    zip_t* handle = zip_open(path, flags, nullptr);
    if (handle == nullptr) {
        throw std::runtime_error(std::format("cannot open {}", path));
    }
    return *handle;
}

class Entry {
public:
    explicit Entry(zip_file_t& handle) : mHandle{&handle} {}

    ~Entry() { zip_fclose(mHandle); }

    Entry(const Entry&) = delete;
    Entry& operator=(const Entry&) = delete;

    std::string readAll(std::size_t expected) {
        std::string buffer(expected, '\0');
        const zip_int64_t got = zip_fread(mHandle, buffer.data(), buffer.size());
        if (got < 0) {
            throw std::runtime_error("zip_fread failed");
        }
        buffer.resize(static_cast<std::size_t>(got));
        return buffer;
    }

private:
    zip_file_t* mHandle;
};

class Archive {
public:
    explicit Archive(zip_t& handle) : mHandle{&handle} {}

    ~Archive() {
        if (mHandle != nullptr) {
            zip_discard(mHandle);
        }
    }

    Archive(const Archive&) = delete;
    Archive& operator=(const Archive&) = delete;

    void setDefaultPassword(const char* password) {
        if (zip_set_default_password(mHandle, password) < 0) {
            fail("zip_set_default_password");
        }
    }

    void add(const Spec& spec, const std::string& payload) {
        zip_source_t* source = zip_source_buffer(mHandle, payload.data(), payload.size(), 0);
        if (source == nullptr) {
            fail("zip_source_buffer");
        }

        const zip_int64_t index = zip_file_add(mHandle, spec.name, source, ZIP_FL_ENC_UTF_8);
        if (index < 0) {
            zip_source_free(source);
            fail(std::format("zip_file_add {}", spec.name));
        }

        const auto at = static_cast<zip_uint64_t>(index);
        if (zip_set_file_compression(mHandle, at, spec.method, 0) < 0) {
            fail(std::format("zip_set_file_compression {}", spec.name));
        }

        if (spec.encryption != ZIP_EM_NONE &&
            zip_file_set_encryption(mHandle, at, spec.encryption, nullptr) < 0) {
            fail(std::format("zip_file_set_encryption {}", spec.name));
        }
    }

    void commit() {
        if (zip_close(mHandle) < 0) {
            fail("zip_close");
        }
        mHandle = nullptr;
    }

    zip_int64_t entryCount() const { return zip_get_num_entries(mHandle, 0); }

    Entry open(const char* name) const {
        zip_file_t* file = zip_fopen(mHandle, name, 0);
        if (file == nullptr) {
            fail(std::format("zip_fopen {}", name));
        }
        return Entry{*file};
    }

private:
    [[noreturn]] void fail(const std::string& what) const {
        throw std::runtime_error(std::format("{}: {}", what, zip_strerror(mHandle)));
    }

    zip_t* mHandle;
};

void checkBackends(Report& report, std::span<const Spec> specs) {
    for (const Spec& spec : specs) {
        report.check(zip_compression_method_supported(spec.method, 1) != 0 &&
                         (spec.encryption == ZIP_EM_NONE ||
                          zip_encryption_method_supported(spec.encryption, 1) != 0),
                     std::format("{} supported", spec.backend));
    }
}

void writeArchive(const char* path, const char* password, std::span<const Spec> specs,
                  const std::string& payload) {
    Archive archive{openArchive(path, ZIP_CREATE | ZIP_TRUNCATE)};
    archive.setDefaultPassword(password);

    for (const Spec& spec : specs) {
        archive.add(spec, payload);
    }

    archive.commit();
}

void verifyArchive(Report& report, const char* path, const char* password,
                   std::span<const Spec> specs, const std::string& payload) {
    Archive archive{openArchive(path, ZIP_RDONLY)};
    archive.setDefaultPassword(password);

    report.check(archive.entryCount() == static_cast<zip_int64_t>(specs.size()),
                 std::format("archive holds {} entries", specs.size()));

    for (const Spec& spec : specs) {
        report.check(archive.open(spec.name).readAll(payload.size()) == payload,
                     std::format("read back {} unchanged", spec.name));
    }
}

}

int main() {
    try {
        Report report{std::cout};

        std::string payload(kPayloadSize, '\0');
        for (std::size_t i = 0; i < payload.size(); ++i) {
            payload[i] = static_cast<char>('a' + i % 26);
        }

        std::cout << std::format("libzip {} (compiled against {})\n", zip_libzip_version(),
                                 LIBZIP_VERSION);

        checkBackends(report, kSpecs);
        if (!report.clean()) {
            std::cerr << std::format("\n{} backend(s) missing\n", report.failures());
            return EXIT_FAILURE;
        }

        writeArchive(kArchive, kPassword, kSpecs, payload);
        verifyArchive(report, kArchive, kPassword, kSpecs, payload);
        std::remove(kArchive);

        if (!report.clean()) {
            std::cerr << std::format("\n{} check(s) failed\n", report.failures());
            return EXIT_FAILURE;
        }

        std::cout << "\nall checks passed\n";
        return EXIT_SUCCESS;
    } catch (const std::exception& error) {
        std::cerr << std::format("\nerror: {}\n", error.what());
        return EXIT_FAILURE;
    }
}
