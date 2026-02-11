#include "c89_validator.hpp"
#include <cstdio>
#include <cstring>
#include <cctype>
#include <string>

/**
 * @class MSVC6StaticAnalyzer
 * @brief Lightweight static analyzer for MSVC 6.0 and C89 constraints.
 */
class MSVC6StaticAnalyzer : public C89Validator {
public:
    ValidationResult validate(const std::string& source) {
        ValidationResult result;
        const char* p = source.c_str();
        int line = 1;

        while (*p) {
            if (*p == '\n') {
                line++;
                p++;
                continue;
            }

            if (isspace(*p)) {
                p++;
                continue;
            }

            // C++ style comments: //
            if (*p == '/' && *(p+1) == '/') {
                result.isValid = false;
                result.errors.push_back(formatError("C++ style '//' comments not allowed", line));
                while (*p && *p != '\n') p++;
                continue;
            }

            // Block comments: /* */
            if (*p == '/' && *(p+1) == '*') {
                p += 2;
                while (*p && !(*p == '*' && *(p+1) == '/')) {
                    if (*p == '\n') line++;
                    p++;
                }
                if (*p) p += 2;
                continue;
            }

            // String literals: " "
            if (*p == '"') {
                p++;
                while (*p && *p != '"') {
                    if (*p == '\\' && *(p+1)) p += 2;
                    else {
                        if (*p == '\n') line++;
                        p++;
                    }
                }
                if (*p) p++;
                continue;
            }

            // Character literals: ' '
            if (*p == '\'') {
                p++;
                while (*p && *p != '\'') {
                    if (*p == '\\' && *(p+1)) p += 2;
                    else p++;
                }
                if (*p) p++;
                continue;
            }

            // Identifiers and Keywords
            if (isalpha(*p) || *p == '_') {
                const char* start = p;
                while (isalnum(*p) || *p == '_') p++;

                size_t len = p - start;
                if (len > 31) {
                    result.isValid = false;
                    char ident_buf[36];
                    size_t to_copy = len > 31 ? 31 : len;
                    memcpy(ident_buf, start, to_copy);
                    ident_buf[to_copy] = '\0';

                    std::string msg = "Identifier '";
                    msg += ident_buf;
                    msg += "...' exceeds 31 characters";
                    result.errors.push_back(formatError(msg.c_str(), line));
                }

                std::string ident(start, len);
                if (ident == "inline" || ident == "restrict" || ident == "_Bool") {
                    result.isValid = false;
                    std::string msg = "Keyword '";
                    msg += ident;
                    msg += "' not supported in MSVC6/C89";
                    result.errors.push_back(formatError(msg.c_str(), line));
                }

                if (ident == "long") {
                    const char* next = p;
                    while (*next && isspace(*next)) {
                        next++;
                    }
                    if (strncmp(next, "long", 4) == 0 && !isalnum(next[4]) && next[4] != '_') {
                        result.isValid = false;
                        result.errors.push_back(formatError("Keyword 'long long' not supported in MSVC6/C89", line));
                    }
                }

                continue;
            }

            // Check for long long (two identifiers)
            // This is slightly covered by the single identifier check if it's "long" followed by "long"
            // but we can handle it specifically if needed.

            p++;
        }

        return result;
    }

private:
    std::string formatError(const char* msg, int line) {
        char buf[512];
        sprintf(buf, "MSVC6/C89 error at line %d: %s", line, msg);
        return std::string(buf);
    }
};

C89Validator* createMSVC6StaticAnalyzer() {
    return new MSVC6StaticAnalyzer();
}
