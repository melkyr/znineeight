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

        std::string full_source = wrapInTranslationUnit(source);

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
        std::string cmd = "gcc -std=c89 -pedantic -Wall -Wextra -Wno-long-long -c ";
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
        return
            "#ifndef __BOOTSTRAP_RUNTIME_H\n"
            "#define __BOOTSTRAP_RUNTIME_H\n"
            "typedef unsigned char bool_t;\n"
            "#define true 1\n"
            "#define false 0\n"
            "#ifndef NULL\n"
            "#define NULL ((void*)0)\n"
            "#endif\n"
            "/* Basic types used by RetroZig, simulated for GCC C89 */\n"
            "typedef signed char i8;\n"
            "typedef short i16;\n"
            "typedef int i32;\n"
            "typedef long long __int64;\n"
            "typedef unsigned char u8;\n"
            "typedef unsigned short u16;\n"
            "typedef unsigned int u32;\n"
            "typedef unsigned long long unsigned_int64_t;\n"
            "typedef unsigned_int64_t unsigned__int64;\n"
            "#endif\n";
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
