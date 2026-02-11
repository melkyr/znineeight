#ifndef C89_VALIDATOR_HPP
#define C89_VALIDATOR_HPP

#include <string>
#include <vector>
#include <sstream>

/**
 * @struct ValidationResult
 * @brief Holds the outcome of a C89 validation attempt.
 */
struct ValidationResult {
    bool isValid;
    std::vector<std::string> errors;
    std::vector<std::string> warnings;

    ValidationResult() : isValid(true) {}
};

/**
 * @class C89Validator
 * @brief Abstract base class for C89 code validators.
 */
class C89Validator {
public:
    virtual ~C89Validator() {}

    /**
     * @brief Validates a piece of C code.
     * @param source The C source code to validate.
     * @return A ValidationResult object.
     */
    virtual ValidationResult validate(const std::string& source) = 0;

    /**
     * @brief Wraps a code snippet in a complete translation unit.
     */
    std::string wrapInTranslationUnit(const std::string& code) {
        std::stringstream ss;
        ss << bootstrapRuntimeHeader();
        ss << code;
        if (code.find("main") == std::string::npos) {
            ss << "\nint main(void) { return 0; }\n";
        }
        return ss.str();
    }

protected:
    /**
     * @brief Returns a compatibility header for the bootstrap runtime.
     */
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
            "/* Basic types used by RetroZig */\n"
            "typedef signed char i8;\n"
            "typedef short i16;\n"
            "typedef int i32;\n"
            "typedef unsigned char u8;\n"
            "typedef unsigned short u16;\n"
            "typedef unsigned int u32;\n"
            "#endif\n";
    }
};

// Factory functions
C89Validator* createGCCValidator();
C89Validator* createMSVC6CompatibleGCCValidator();
C89Validator* createMSVC6StaticAnalyzer();

#endif // C89_VALIDATOR_HPP
