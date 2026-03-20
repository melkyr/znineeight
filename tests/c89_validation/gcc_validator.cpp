#include "c89_validator.hpp"
#include "platform.hpp"
#include <cstdio>
#include <cstring>

/**
 * @class GCCValidator
 * @brief Implementation of C89Validator using GCC.
 */
class GCCValidator : public C89Validator {
public:
    ValidationResult validate(const std::string& source) {
        ValidationResult result;

        // Pre-process source to handle MSVC suffixes for GCC validation
        std::string processed_source = source;
        size_t pos = 0;
        while ((pos = processed_source.find("ui64", pos)) != std::string::npos) {
            processed_source.replace(pos, 4, "ULL");
            pos += 3;
        }
        pos = 0;
        while ((pos = processed_source.find("i64", pos)) != std::string::npos) {
            // Avoid matching 'ui64' which was already handled or 'int64' etc.
            // Check if preceding character is a digit
            if (pos > 0 && isdigit(processed_source[pos-1])) {
                processed_source.replace(pos, 3, "LL");
                pos += 2;
            } else {
                pos += 3;
            }
        }

        std::string full_source = wrapInTranslationUnit(processed_source);

        char* temp_path = plat_create_temp_file("c89test", ".c");
        if (!temp_path) {
            result.isValid = false;
            result.errors.push_back("Failed to create temporary file");
            return result;
        }

        // Write source to temp file
        FILE* f = fopen(temp_path, "w");
        if (!f) {
            result.isValid = false;
            result.errors.push_back("Failed to open temporary file for writing");
            plat_free(temp_path);
            return result;
        }
        fputs(full_source.c_str(), f);
        fclose(f);

        // Invoke GCC
        // -std=c89 -pedantic -Wall -Wextra -c
        // We use -Wno-long-long if we want to support __int64 simulation
        std::string cmd = "gcc -std=c89 -pedantic -Wall -Wextra -Wno-long-long -Isrc/include -c ";
        cmd += temp_path;
        cmd += " -o /dev/null 2>&1";

        char* output = NULL;
        size_t output_size = 0;
        int exit_code = plat_run_command(cmd.c_str(), &output, &output_size);

        if (exit_code != 0) {
            result.isValid = false;
            if (output) {
                // Split output into lines
                const char* p = output;
                const char* start = p;
                while (*p) {
                    if (*p == '\n') {
                        result.errors.push_back(std::string(start, p - start));
                        start = p + 1;
                    }
                    p++;
                }
                if (start < p) {
                    result.errors.push_back(std::string(start, p - start));
                }
            } else {
                result.errors.push_back("GCC failed with no output");
            }
        }

        if (output) plat_free(output);
        plat_delete_file(temp_path);
        plat_free(temp_path);

        return result;
    }

protected:
    virtual std::string bootstrapRuntimeHeader() {
        // C89Emitter already includes "zig_runtime.h" in emitPrologue().
        // We just need to make sure we don't duplicate definitions.
        return "/* Using zig_runtime.h from include path */\n";
    }
};

/**
 * @class MSVC6CompatibleGCCValidator
 * @brief GCC validator with MSVC 6.0 compatible headers.
 */
class MSVC6CompatibleGCCValidator : public GCCValidator {
    // Currently shares same header as base since base already includes MSVC types
};

// Factory functions
C89Validator* createGCCValidator() {
    return new GCCValidator();
}

C89Validator* createMSVC6CompatibleGCCValidator() {
    return new MSVC6CompatibleGCCValidator();
}
