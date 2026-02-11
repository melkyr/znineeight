#include "test_framework.hpp"
#include "c89_validator.hpp"
#include "platform.hpp"
#include <string>
#include <vector>
#include <cstdio>

static std::string read_file_content(const char* path) {
    char* buffer = NULL;
    size_t size = 0;
    if (plat_file_read(path, &buffer, &size)) {
        std::string result(buffer, size);
        plat_free(buffer);
        return result;
    }
    return "";
}

static bool contains_substring(const std::vector<std::string>& vec, const char* sub) {
    for (size_t i = 0; i < vec.size(); ++i) {
        if (vec[i].find(sub) != std::string::npos) return true;
    }
    return false;
}

static bool is_gcc_available() {
    char* output = NULL;
    size_t size = 0;
    int exit_code = plat_run_command("gcc --version", &output, &size);
    if (output) plat_free(output);
    return exit_code == 0;
}

// --- GCC Validator Tests ---

TEST_FUNC(C89Validator_GCC_KnownGood) {
    if (!is_gcc_available()) {
        printf("Skipping GCC test (gcc not found)\n");
        return true;
    }
    C89Validator* validator = createGCCValidator();
    std::string code = read_file_content("tests/c89_validation/known_good_samples/basic_arithmetic.c");
    ValidationResult result = validator->validate(code);
    bool ok = result.isValid;
    if (!ok) {
        printf("GCC validation failed for known good sample:\n");
        for (size_t i = 0; i < result.errors.size(); ++i) {
            printf("  %s\n", result.errors[i].c_str());
        }
    }
    delete validator;
    return ok;
}

TEST_FUNC(C89Validator_GCC_KnownBad) {
    if (!is_gcc_available()) {
        printf("Skipping GCC test (gcc not found)\n");
        return true;
    }
    C89Validator* validator = createGCCValidator();
    std::string code = read_file_content("tests/c89_validation/known_bad_samples/cpp_comment.c");
    ValidationResult result = validator->validate(code);
    delete validator;
    // GCC -std=c89 -pedantic should reject // comments
    return !result.isValid;
}

// --- MSVC6 Static Analyzer Tests ---

TEST_FUNC(C89Validator_MSVC6_LongIdentifier) {
    C89Validator* validator = createMSVC6StaticAnalyzer();
    std::string code = read_file_content("tests/c89_validation/known_bad_samples/long_identifier.c");
    ValidationResult result = validator->validate(code);
    delete validator;
    return !result.isValid && contains_substring(result.errors, "exceeds 31 characters");
}

TEST_FUNC(C89Validator_MSVC6_CppComment) {
    C89Validator* validator = createMSVC6StaticAnalyzer();
    std::string code = read_file_content("tests/c89_validation/known_bad_samples/cpp_comment.c");
    ValidationResult result = validator->validate(code);
    delete validator;
    return !result.isValid && contains_substring(result.errors, "comments not allowed");
}

TEST_FUNC(C89Validator_MSVC6_LongLong) {
    C89Validator* validator = createMSVC6StaticAnalyzer();
    std::string code = read_file_content("tests/c89_validation/known_bad_samples/long_long.c");
    ValidationResult result = validator->validate(code);
    delete validator;
    return !result.isValid && contains_substring(result.errors, "long long");
}

TEST_FUNC(C89Validator_MSVC6_KnownGood) {
    C89Validator* validator = createMSVC6StaticAnalyzer();
    std::string code = read_file_content("tests/c89_validation/known_good_samples/structs.c");
    ValidationResult result = validator->validate(code);
    delete validator;
    return result.isValid;
}
