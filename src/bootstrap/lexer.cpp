#include "lexer.hpp"
#include "source_manager.hpp"
#include "memory.hpp"
#include <cctype>
#include <math.h>

double Lexer::parseDecimalFloat(const char* start, const char** end) {
    double value = 0.0;
    const char* p = start;

    // 1. Integer Part
    while (isdigit(*p) || *p == '_') {
        if (*p == '_') { p++; continue; }
        value = value * 10.0 + (*p - '0');
        p++;
    }

    // 2. Fractional Part
    if (*p == '.') {
        p++;
        double divisor = 10.0;
        while (isdigit(*p) || *p == '_') {
            if (*p == '_') { p++; continue; }
            value += (*p - '0') / divisor;
            divisor *= 10.0;
            p++;
        }
    }

    // 3. Exponent Part
    if (*p == 'e' || *p == 'E') {
        const char* exponent_start = p;
        p++; // Consume 'e' or 'E'
        int sign = 1;
        if (*p == '-') {
            sign = -1;
            p++;
        } else if (*p == '+') {
            p++;
        }

        // Check if there is at least one digit after the exponent marker
        if (!isdigit(*p)) {
            // Not a valid exponent, so we backtrack and treat the 'e' as a separate token.
            p = exponent_start;
        } else {
            int exponent = 0;
            while (isdigit(*p) || *p == '_') {
                if (*p == '_') {
                    p++;
                    continue;
                }
                exponent = exponent * 10 + (*p - '0');
                p++;
            }
            value *= pow(10.0, sign * exponent);
        }
    }
    *end = p;
    return value;
}
#include <cstdlib> // For strtol, strtod
#include <cmath>   // For ldexp
#include <cstring> // For memcmp, strncmp

/**
 * @brief Parses an integer from a string slice into a u64, with overflow detection.
 *
 * This function manually parses a string of digits into a 64-bit unsigned
 * integer. It supports decimal (base 10) and hexadecimal (base 16) literals.
 * It includes an overflow check to ensure that the parsed value does not
 * exceed the maximum value for a u64.
 *
 * @param start A pointer to the beginning of the string slice to parse.
 * @param end A pointer to the end of the string slice to parse.
 * @param out_value A pointer to a u64 that will be populated with the parsed value.
 * @return `true` if the integer was parsed successfully, `false` if an overflow occurred.
 */
static bool parseInteger(const char* start, const char* end, u64* out_value) {
    u64 result = 0;
    int base = 10;
    const char* p = start;
    const u64 u64_max = 0xFFFFFFFFFFFFFFFFULL;

    if (*p == '0' && (p[1] == 'x' || p[1] == 'X')) {
        base = 16;
        p += 2;
    }

    for (; p < end; ++p) {
        if (*p == '_') continue;
        int digit;
        if (*p >= '0' && *p <= '9') {
            digit = *p - '0';
        } else if (base == 16 && *p >= 'a' && *p <= 'f') {
            digit = *p - 'a' + 10;
        } else if (base == 16 && *p >= 'A' && *p <= 'F') {
            digit = *p - 'A' + 10;
        } else {
            break;
        }

        if (result > (u64_max - digit) / base) {
            return false; // Overflow detected
        }
        result = result * base + digit;
    }

    *out_value = result;
    return true;
}


// Keyword lookup table.
// IMPORTANT: This array is sorted ALPHABETICALLY by name.
const Keyword keywords[] = {
    {"addrspace", 9, TOKEN_ADDRSPACE},
    {"align", 5, TOKEN_ALIGN},
    {"allowzero", 9, TOKEN_ALLOWZERO},
    {"and", 3, TOKEN_AND},
    {"anyframe", 8, TOKEN_ANYFRAME},
    {"anytype", 7, TOKEN_ANYTYPE},
    {"asm", 3, TOKEN_ASM},
    {"break", 5, TOKEN_BREAK},
    {"callconv", 8, TOKEN_CALLCONV},
    {"catch", 5, TOKEN_CATCH},
    {"comptime", 8, TOKEN_COMPTIME},
    {"const", 5, TOKEN_CONST},
    {"continue", 8, TOKEN_CONTINUE},
    {"defer", 5, TOKEN_DEFER},
    {"else", 4, TOKEN_ELSE},
    {"enum", 4, TOKEN_ENUM},
    {"errdefer", 8, TOKEN_ERRDEFER},
    {"error", 5, TOKEN_ERROR_SET},
    {"export", 6, TOKEN_EXPORT},
    {"extern", 6, TOKEN_EXTERN},
    {"false", 5, TOKEN_FALSE},
    {"fn", 2, TOKEN_FN},
    {"for", 3, TOKEN_FOR},
    {"if", 2, TOKEN_IF},
    {"inline", 6, TOKEN_INLINE},
    {"linksection", 11, TOKEN_LINKSECTION},
    {"noalias", 7, TOKEN_NOALIAS},
    {"noinline", 8, TOKEN_NOINLINE},
    {"nosuspend", 9, TOKEN_NOSUSPEND},
    {"null", 4, TOKEN_NULL},
    {"opaque", 6, TOKEN_OPAQUE},
    {"or", 2, TOKEN_OR},
    {"orelse", 6, TOKEN_ORELSE},
    {"packed", 6, TOKEN_PACKED},
    {"pub", 3, TOKEN_PUB},
    {"resume", 6, TOKEN_RESUME},
    {"return", 6, TOKEN_RETURN},
    {"struct", 6, TOKEN_STRUCT},
    {"suspend", 7, TOKEN_SUSPEND},
    {"switch", 6, TOKEN_SWITCH},
    {"test", 4, TOKEN_TEST},
    {"threadlocal", 11, TOKEN_THREADLOCAL},
    {"true", 4, TOKEN_TRUE},
    {"try", 3, TOKEN_TRY},
    {"union", 5, TOKEN_UNION},
    {"unreachable", 11, TOKEN_UNREACHABLE},
    {"usingnamespace", 14, TOKEN_USINGNAMESPACE},
    {"var", 3, TOKEN_VAR},
    {"volatile", 8, TOKEN_VOLATILE},
    {"while", 5, TOKEN_WHILE},
};
const int num_keywords = sizeof(keywords) / sizeof(Keyword);

static void encode_utf8(DynamicArray<char>& buffer, u32 codepoint) {
    if (codepoint <= 0x7F) {
        buffer.append(static_cast<char>(codepoint));
    } else if (codepoint <= 0x7FF) {
        buffer.append(static_cast<char>(0xC0 | (codepoint >> 6)));
        buffer.append(static_cast<char>(0x80 | (codepoint & 0x3F)));
    } else if (codepoint <= 0xFFFF) {
        buffer.append(static_cast<char>(0xE0 | (codepoint >> 12)));
        buffer.append(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
        buffer.append(static_cast<char>(0x80 | (codepoint & 0x3F)));
    } else if (codepoint <= 0x10FFFF) {
        buffer.append(static_cast<char>(0xF0 | (codepoint >> 18)));
        buffer.append(static_cast<char>(0x80 | ((codepoint >> 12) & 0x3F)));
        buffer.append(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
        buffer.append(static_cast<char>(0x80 | (codepoint & 0x3F)));
    }
}
char Lexer::peek(int n) const {
    const char* p = this->current;
    for (int i = 0; i < n; i++) {
        if (*p == '\0') return '\0'; // Return null char if out of bounds
        p++;
    }
    return *p;
}

void Lexer::advance(int n) {
    for (int i = 0; i < n; i++) {
        if (*this->current == '\0') {
            return;
        }
        if (*this->current == '\n') {
            this->line++;
            this->column = 1;
        } else {
            this->column++;
        }
        this->current++;
    }
}

static TokenType lookupIdentifier(const char* name, size_t len) {
    int left = 0;
    int right = num_keywords - 1;

    while (left <= right) {
        int mid = left + (right - left) / 2;
        const Keyword& k = keywords[mid];

        // Determine the length to compare (the shorter of the two)
        size_t common_len = (len < k.len) ? len : k.len;

        // Compare the shared prefix bytes
        int cmp = memcmp(name, k.name, common_len);

        if (cmp == 0) {
            // The prefixes match. Now distinguishing based on length.
            if (len < k.len) {
                right = mid - 1;
            } else if (len > k.len) {
                left = mid + 1;
            } else {
                // Exact match in content and length.
                return k.type;
            }
        } else if (cmp < 0) {
            // Name is alphabetically smaller
            right = mid - 1;
        } else {
            // Name is alphabetically larger
            left = mid + 1;
        }
    }
    return TOKEN_IDENTIFIER;
}

/**
 * @brief Constructs a new Lexer instance.
 *
 * Initializes the lexer with the source code to be processed.
 *
 * @param src A reference to the SourceManager containing the source file.
 * @param interner A reference to the StringInterner.
 * @param arena A reference to the ArenaAllocator.
 * @param file_id The identifier of the file to be lexed.
 */
Lexer::Lexer(SourceManager& src, StringInterner& interner, ArenaAllocator& arena, u32 file_id) : source(src), interner(interner), arena(arena), file_id(file_id) {
    // Retrieve the source content from the manager and set the current pointer.
    const SourceFile* file = src.getFile(file_id);
    this->current = file->content;
    this->line = 1;
    this->column = 1;
}

/**
 * @brief Consumes the current character if it matches the expected character.
 *
 * If the current character matches `expected`, the lexer advances its position
 * and returns true. Otherwise, it stays at the current position and returns false.
 *
 * @param expected The character to match against the current character.
 * @return `true` if the character was matched and consumed, `false` otherwise.
 */
bool Lexer::match(char expected) {
    if (*this->current == '\0') return false;
    if (*this->current != expected) return false;
    this->current++;
    this->column++;
    return true;
}

Token Lexer::lexCharLiteral() {
    Token token = Token();
    token.location.file_id = this->file_id;
    token.location.line = this->line;
    token.location.column = this->column;

    if (*this->current == '\'') {
        this->current++; // Consume the closing '
        this->column++;
        token.type = TOKEN_ERROR; // Empty character literal
        return token;
    }

    u32 value;
    if (*this->current == '\\') {
        bool success;
        value = parseEscapeSequence(success);
        if (!success) {
            token.type = TOKEN_ERROR;
            return token;
        }
    } else {
        value = *this->current;
        this->current++;
        this->column++;
    }

    if (*this->current != '\'') {
        token.type = TOKEN_ERROR; // Unterminated or multi-character literal
        return token;
    }
    this->current++; // Consume the closing '
    this->column++;

    token.type = TOKEN_CHAR_LITERAL;
    token.value.character = value;
    return token;
}

/**
 * @brief Parses a hexadecimal floating-point literal.
 *
 * This function manually parses a hexadecimal float (e.g., `0x1.Ap2`) into a
 * `double`. It handles the integer part, the fractional part, and the binary
 * exponent. This is necessary because `strtod` in C++98 does not support hex floats.
 *
 * @return A `Token` of type `TOKEN_FLOAT_LITERAL` or `TOKEN_ERROR`.
 */
Token Lexer::parseHexFloat() {
    Token token = Token();
    token.location.file_id = this->file_id;
    token.location.line = this->line;
    token.location.column = this->column;
    const char* start = this->current;

    this->current += 2; // Skip "0x"

    double value = 0.0;
    while (isxdigit(*this->current)) {
        value = value * 16.0 + (*this->current <= '9' ? *this->current - '0' : tolower(*this->current) - 'a' + 10);
        this->current++;
    }

    if (*this->current == '.') {
        this->current++;
        double fraction = 0.0;
        double divisor = 16.0;
        while (isxdigit(*this->current)) {
            fraction += (*this->current <= '9' ? *this->current - '0' : tolower(*this->current) - 'a' + 10) / divisor;
            divisor *= 16.0;
            this->current++;
        }
        value += fraction;
    }

    if (*this->current != 'p' && *this->current != 'P') {
        token.type = TOKEN_ERROR;
        return token;
    }
    this->current++;

    int sign = 1;
    if (*this->current == '-') {
        sign = -1;
        this->current++;
    } else if (*this->current == '+') {
        this->current++;
    }

    if (!isdigit(*this->current)) {
        token.type = TOKEN_ERROR;
        return token;
    }

    int exponent = 0;
    while (isdigit(*this->current)) {
        exponent = exponent * 10 + (*this->current - '0');
        this->current++;
    }

    token.value.floating_point = ldexp(value, sign * exponent);
    token.type = TOKEN_FLOAT_LITERAL;
    this->column += (this->current - start);
    return token;
}

/**
 * @brief Parses a numeric literal, which can be an integer or a float.
 *
 * This function handles decimal and hexadecimal integer literals, as well as
 * decimal and hexadecimal floating-point literals.
 *
 * It includes a special lookahead mechanism to disambiguate between a
 * floating-point number and an integer followed by a range operator (`..`).
 * When a `.` is encountered, the lexer checks the next character. If it is
 * also a `.`, the number is treated as an integer, and the `..` is left
 * for the next tokenization step.
 *
 * @return A `Token` of the appropriate numeric type (`TOKEN_INTEGER_LITERAL` or
 *         `TOKEN_FLOAT_LITERAL`) or `TOKEN_ERROR` if the format is invalid.
 */
Token Lexer::lexNumericLiteral() {
    Token token = Token();
    token.location.file_id = this->file_id;
    token.location.line = this->line;
    token.location.column = this->column;
    const char* start = this->current;

    if (*start == '.') {
        this->current++;
        this->column++;
        token.type = TOKEN_ERROR; // Invalid: cannot start with a dot
        return token;
    }

    bool is_hex = false;
    if (this->current[0] == '0' && (this->current[1] == 'x' || this->current[1] == 'X')) {
        is_hex = true;
    }

    if (is_hex) {
        const char* p = start + 2;
        while (isxdigit(*p)) p++;
        if (*p == '.' || *p == 'p' || *p == 'P') {
            return parseHexFloat();
        }
    }

    // Temporarily advance to find the end of the integer part
    const char* end_ptr = start;
    if (is_hex) {
        end_ptr += 2;
        while (isxdigit(*end_ptr) || *end_ptr == '_') end_ptr++;
    } else {
        while (isdigit(*end_ptr) || *end_ptr == '_') end_ptr++;
    }

    bool is_float = false;
    if (*end_ptr == '.') {
        if (peek(end_ptr - this->current + 1) == '.') {
            // Range operator, not a float
        } else {
            is_float = true;
        }
    } else if (*end_ptr == 'e' || *end_ptr == 'E') {
        is_float = true;
    }

    if (is_float) {
        const char* end;
        token.value.floating_point = parseDecimalFloat(start, &end);

        if (end > start) {
            this->column += (end - start);
            this->current = (char*)end;
            token.type = TOKEN_FLOAT_LITERAL;
        } else {
            token.type = TOKEN_ERROR;
        }

    } else {
        u64 value;
        if (parseInteger(start, end_ptr, &value)) {
            token.value.integer_literal.value = value;
            token.type = TOKEN_INTEGER_LITERAL;
        } else {
            token.type = TOKEN_ERROR;
        }
        this->column += (end_ptr - start);
        this->current = (char*)end_ptr;

        // Check for suffixes
        bool has_u = false;
        bool has_l = false;
        if (tolower(*this->current) == 'u') {
            has_u = true;
            this->current++;
            this->column++;
            if (tolower(*this->current) == 'l') {
                has_l = true;
                this->current++;
                this->column++;
            }
        } else if (tolower(*this->current) == 'l') {
            has_l = true;
            this->current++;
            this->column++;
            if (tolower(*this->current) == 'u') {
                has_u = true;
                this->current++;
                this->column++;
            }
        }
        token.value.integer_literal.is_unsigned = has_u;
        token.value.integer_literal.is_long = has_l;
    }

    return token;
}

/**
 * @brief Parses an integer from a string slice into a u64.
 *
 * This function manually parses a string of digits into a 64-bit unsigned
 * integer. It supports decimal (base 10) and hexadecimal (base 16) literals.
 * It is designed to be a direct replacement for `strtol` to ensure that
 * 64-bit integer literals are handled correctly, especially in 32-bit
 * environments where `long` is only 32 bits.
 *
 * @param start A pointer to the beginning of the string slice to parse.
 * @param end A pointer to the end of the string slice to parse.
 * @return The parsed `u64` integer value.
 */

/**
 * @brief Scans and returns the next token from the source code.
 *
 * This is the main entry point for the lexer. It consumes whitespace, identifies
 * the start of a new token, and dispatches to helper functions for complex tokens
 * like numbers and character literals. It handles single-character and multi-character
 * operators using a lookahead mechanism (`match` function). The function is designed
 * to be called repeatedly to generate a stream of tokens.
 *
 * @return The next `Token` found in the source stream. When the end of the
 *         file is reached, it will consistently return a token of type `TOKEN_EOF`.
 *         If an unrecognized character is found, it returns `TOKEN_ERROR`.
 */
Token Lexer::nextToken() {
    // Skip whitespace and handle newlines first.
    while (true) {
        char c = *this->current;
        switch (c) {
            case ' ':
            case '\r':
                this->current++;
                this->column++;
                continue;
            case '\t':
                this->current++;
                this->column = (((this->column - 1) / TAB_WIDTH) + 1) * TAB_WIDTH + 1;
                continue;
            case '\n':
                this->line++;
                this->column = 1;
                this->current++;
                continue;
            default:
                break;
        }
        break;
    }

    Token token = Token();
    token.location.file_id = this->file_id;
    token.location.line = this->line;
    token.location.column = this->column;

    char c = *this->current;

    if (c == '\0') {
        token.type = TOKEN_EOF;
        return token;
    }

    if (isdigit(c) || (c == '.' && isdigit(this->current[1]))) {
        return lexNumericLiteral();
    }


    this->current++;
    this->column++;

    switch (c) {
        case '+':
            if (match('=')) {
                token.type = TOKEN_PLUS_EQUAL;
            } else if (match('+')) {
                token.type = TOKEN_PLUS2;
            } else if (match('%')) {
                token.type = TOKEN_PLUSPERCENT;
            } else {
                token.type = TOKEN_PLUS;
            }
            break;
        case '-': // Handles '-', '->', '-=', '-%'
            if (match('>')) {
                token.type = TOKEN_ARROW;
            } else if (match('=')) {
                token.type = TOKEN_MINUS_EQUAL;
            } else if (match('%')) {
                token.type = TOKEN_MINUSPERCENT;
            } else {
                token.type = TOKEN_MINUS;
            }
            break;
        case '*':
            if (match('=')) {
                token.type = TOKEN_STAR_EQUAL;
            } else if (match('*')) {
                token.type = TOKEN_STAR2;
            } else if (match('%')) {
                token.type = TOKEN_STARPERCENT;
            } else {
                token.type = TOKEN_STAR;
            }
            break;
        case '/':
            if (match('/')) {
                // Single-line comment
                while (*this->current != '\n' && *this->current != '\0') {
                    this->current++;
                    this->column++;
                }
                return nextToken();
            } else if (match('*')) {
                // Block comment with nesting support
                int nesting = 1;
                while (nesting > 0) {
                    if (*this->current == '\0') { // End of file
                        token.type = TOKEN_EOF;
                        return token;
                    }
                    if (*this->current == '/' && *(this->current + 1) == '*') {
                        nesting++;
                        this->current += 2;
                        this->column += 2;
                    } else if (*this->current == '*' && *(this->current + 1) == '/') {
                        nesting--;
                        this->current += 2;
                        this->column += 2;
                    } else if (*this->current == '\n') {
                        this->line++;
                        this->column = 1;
                        this->current++;
                    } else {
                        this->current++;
                        this->column++;
                    }
                }
                return nextToken();
            } else {
                // Division or compound assignment
                token.type = match('=') ? TOKEN_SLASH_EQUAL : TOKEN_SLASH;
            }
            break;
        case ';': token.type = TOKEN_SEMICOLON; break;
        case '(': token.type = TOKEN_LPAREN; break;
        case ')': token.type = TOKEN_RPAREN; break;
        case '{': token.type = TOKEN_LBRACE; break;
        case '}': token.type = TOKEN_RBRACE; break;
        case '[': token.type = TOKEN_LBRACKET; break;
        case ']': token.type = TOKEN_RBRACKET; break;
        case ':': token.type = TOKEN_COLON; break;
        case ',': token.type = TOKEN_COMMA; break;
        case '=': // Handles '=', '==', '=>'
            if (match('=')) {
                token.type = TOKEN_EQUAL_EQUAL;
            } else if (match('>')) {
                token.type = TOKEN_FAT_ARROW;
            } else {
                token.type = TOKEN_EQUAL;
            }
            break;
        case '!': token.type = match('=') ? TOKEN_BANG_EQUAL : TOKEN_BANG; break;
        case '<':
            if (match('<')) {
                token.type = match('=') ? TOKEN_LARROW2_EQUAL : TOKEN_LARROW2;
            } else {
                token.type = match('=') ? TOKEN_LESS_EQUAL : TOKEN_LESS;
            }
            break;
        case '>':
            if (match('>')) {
                token.type = match('=') ? TOKEN_RARROW2_EQUAL : TOKEN_RARROW2;
            } else {
                token.type = match('=') ? TOKEN_GREATER_EQUAL : TOKEN_GREATER;
            }
            break;
        case '%': token.type = match('=') ? TOKEN_PERCENT_EQUAL : TOKEN_PERCENT; break;
        case '~': token.type = TOKEN_TILDE; break;
        case '&':
            token.type = match('=') ? TOKEN_AMPERSAND_EQUAL : TOKEN_AMPERSAND;
            break;
        case '|':
            token.type = match('=') ? TOKEN_PIPE_EQUAL : TOKEN_PIPE;
            break;
        case '^': token.type = match('=') ? TOKEN_CARET_EQUAL : TOKEN_CARET; break;
        case '.': // Handles '.', '..', '...', '.*', '.?'
            if (match('.')) {
                if (match('.')) {
                    token.type = TOKEN_ELLIPSIS;
                } else {
                    token.type = TOKEN_RANGE;
                }
            } else if (match('*')) {
                token.type = TOKEN_DOT_ASTERISK;
            } else if (match('?')) {
                token.type = TOKEN_DOT_QUESTION;
            } else {
                token.type = TOKEN_DOT;
            }
            break;
        case '?': token.type = TOKEN_QUESTION; break;
        case '\'':
            token = lexCharLiteral();
            break;
        case '"':
            token = lexStringLiteral();
            break;
        default:
            if (isIdentifierStart(c)) {
                this->current--;
                this->column--;
                return lexIdentifierOrKeyword();
            }
            token.type = TOKEN_ERROR;
            break;
    }

    return token;
}

/**
 * @brief Parses a string literal, handling escape sequences.
 *
 * This function scans a string literal, delimited by double quotes. It processes
 * standard escape sequences (`\n`, `\t`, etc.), and hexadecimal escapes (`\xNN`).
 * The parsed string content is stored in a temporary buffer allocated from the
 * arena, and the final string is interned.
 *
 * @return A `Token` of type `TOKEN_STRING_LITERAL` or `TOKEN_ERROR` if the
 *         string is unterminated or contains an invalid escape sequence.
 */
Token Lexer::lexStringLiteral() {
    Token token = Token();
    token.location.file_id = this->file_id;
    token.location.line = this->line;
    token.location.column = this->column;

    const char* start = this->current;
    DynamicArray<char> buffer(this->arena);

    while (*this->current != '"' && *this->current != '\0') {
        if (*this->current == '\\' && this->current[1] == '\n') {
            this->current += 2;
            this->line++;
            this->column = 1;
        } else if (*this->current == '\\') {
            bool success;
            u32 value = parseEscapeSequence(success);
            if (!success) {
                token.type = TOKEN_ERROR;
                return token;
            }
            encode_utf8(buffer, value);
        } else {
            buffer.append(*this->current);
            this->current++;
        }
    }

    if (*this->current == '\0') {
        token.type = TOKEN_ERROR; // Unterminated string literal
        return token;
    }

    this->current++; // Consume the closing "
    this->column += (this->current - start);

    buffer.append('\0');
    token.type = TOKEN_STRING_LITERAL;
    token.value.identifier = this->interner.intern(buffer.getData());
    return token;
}

Token Lexer::lexIdentifierOrKeyword() {
    Token token = Token();
    token.location.file_id = this->file_id;
    token.location.line = this->line;
    token.location.column = this->column;

    const char* start = this->current;
    while (isIdentifierChar(*this->current)) {
        this->current++;
    }

    size_t length = this->current - start;
    token.type = lookupIdentifier(start, length);

    if (token.type == TOKEN_IDENTIFIER) {
        token.value.identifier = this->interner.intern(start, length);
    }

    this->column += length;
    return token;
}

/**
 * @brief Parses an escape sequence and returns the resulting character value.
 *
 * This function is a centralized handler for all escape sequences in both
 * character and string literals. It consumes the characters for the escape
 * sequence from the input stream and returns the corresponding value.
 *
 * The function handles standard escapes (`\\n`, `\\t`, etc.), hexadecimal
 * escapes (`\\xHH`), and Unicode escapes (`\\u{...}`). It performs bounds
 * checking to ensure it does not read past the end of the input buffer.
 *
 * @param success [out] A boolean reference that is set to `true` if the parse
 *                is successful, and `false` otherwise.
 * @return The `u32` value of the parsed character. If parsing fails, the
 *         return value is undefined, and `success` will be `false`.
 */
u32 Lexer::parseEscapeSequence(bool& success) {
    this->current++; // Consume the '\\'
    this->column++;
    success = true;
    char c = *this->current;

    switch (c) {
        case 'n': this->current++; this->column++; return '\n';
        case 'r': this->current++; this->column++; return '\r';
        case 't': this->current++; this->column++; return '\t';
        case '\\': this->current++; this->column++; return '\\';
        case '\'': this->current++; this->column++; return '\'';
        case '"': this->current++; this->column++; return '"';
        case 'x': {
            this->current++; // Consume the 'x'
            this->column++;
            u32 hex_val = 0;
            for (int i = 0; i < 2; ++i) {
                if (*this->current == '\0') {
                    success = false;
                    return 0;
                }
                char digit = *this->current;
                if (digit >= '0' && digit <= '9') {
                    hex_val = (hex_val * 16) + (digit - '0');
                } else if (digit >= 'a' && digit <= 'f') {
                    hex_val = (hex_val * 16) + (digit - 'a' + 10);
                } else if (digit >= 'A' && digit <= 'F') {
                    hex_val = (hex_val * 16) + (digit - 'A' + 10);
                } else {
                    success = false;
                    return 0;
                }
                this->current++;
                this->column++;
            }
            return hex_val;
        }
        case 'u': {
            this->current++; // Consume the 'u'
            this->column++;
            if (*this->current != '{') {
                success = false;
                return 0;
            }
            this->current++; // Consume the '{'
            this->column++;
            u32 unicode_val = 0;
            int digit_count = 0;
            const int MAX_UNICODE_DIGITS = 6;

            while (*this->current != '}' && *this->current != '\0' && digit_count < MAX_UNICODE_DIGITS) {
                char digit = *this->current;
                u32 digit_value;
                if (digit >= '0' && digit <= '9') {
                    digit_value = digit - '0';
                } else if (digit >= 'a' && digit <= 'f') {
                    digit_value = digit - 'a' + 10;
                } else if (digit >= 'A' && digit <= 'F') {
                    digit_value = digit - 'A' + 10;
                } else {
                    success = false; // Invalid hex digit
                    return 0;
                }
                unicode_val = (unicode_val * 16) + digit_value;
                this->current++;
                this->column++;
                digit_count++;
            }

            if (*this->current != '}' || digit_count == 0) {
                success = false;
                return 0;
            }

            if (unicode_val > 0x10FFFF || (unicode_val >= 0xD800 && unicode_val <= 0xDFFF)) {
                 success = false;
                 return 0;
            }

            this->current++; // Consume the '}'
            this->column++;
            return unicode_val;
        }
        default:
            success = false;
            return 0;
    }
}
