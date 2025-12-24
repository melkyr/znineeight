#include "lexer.hpp"
#include "source_manager.hpp"
#include "memory.hpp"
#include <cstdlib> // For strtod
#include <cmath>   // For ldexp, pow
#include <cstring> // For memcmp, strncmp

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
    {"fn", 2, TOKEN_FN},
    {"for", 3, TOKEN_FOR},
    {"if", 2, TOKEN_IF},
    {"inline", 6, TOKEN_INLINE},
    {"linksection", 11, TOKEN_LINKSECTION},
    {"noalias", 7, TOKEN_NOALIAS},
    {"noinline", 8, TOKEN_NOINLINE},
    {"nosuspend", 9, TOKEN_NOSUSPEND},
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
    return this->current[n];
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

Lexer::Lexer(SourceManager& src, StringInterner& interner, ArenaAllocator& arena, u32 file_id) : source(src), interner(interner), arena(arena), file_id(file_id) {
    // Retrieve the source content from the manager and set the current pointer.
    const SourceFile* file = src.getFile(file_id);
    this->current = file->content;
    this->line = 1;
    this->column = 1;
}

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

Token Lexer::parseHexFloat() {
    Token token = Token();
    token.location.file_id = this->file_id;
    token.location.line = this->line;
    token.location.column = this->column;
    const char* start = this->current;

    this->current += 2; // Skip "0x"

    double value = 0.0;
    while (isHexDigit(*this->current)) {
        value = value * 16.0 + (*this->current <= '9' ? *this->current - '0' : toLower(*this->current) - 'a' + 10);
        this->current++;
    }

    if (*this->current == '.') {
        this->current++;
        double fraction = 0.0;
        double divisor = 16.0;
        while (isHexDigit(*this->current)) {
            fraction += (*this->current <= '9' ? *this->current - '0' : toLower(*this->current) - 'a' + 10) / divisor;
            divisor *= 16.0;
            this->current++;
        }
        value += fraction;
    }

    if (*this->current != 'p' && *this->current != 'P') {
        this->current = (char*)start;
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

    if (!isDigit(*this->current)) {
        this->current = (char*)start;
        token.type = TOKEN_ERROR;
        return token;
    }

    int exponent = 0;
    while (isDigit(*this->current)) {
        exponent = exponent * 10 + (*this->current - '0');
        this->current++;
    }

    token.value.floating_point = ldexp(value, sign * exponent);
    token.type = TOKEN_FLOAT_LITERAL;
    this->column += (this->current - start);
    return token;
}

Token Lexer::lexNumericLiteral() {
    Token token = Token();
    token.location.file_id = this->file_id;
    token.location.line = this->line;
    token.location.column = this->column;
    const char* start = this->current;

    if (*start == '_') {
        token.type = TOKEN_ERROR;
        this->advance();
        return token;
    }

    bool is_hex = false;
    if (this->current[0] == '0' && (this->current[1] == 'x' || this->current[1] == 'X')) {
        is_hex = true;
    }

    if (is_hex) {
        const char* p = start + 2;
        while (isHexDigit(*p) || *p == '_') p++;
        if (*p == '.' || *p == 'p' || *p == 'P') {
            return parseHexFloat();
        }
    }


    // Temporarily advance to find the end of the number
    const char* end_ptr = start;
    if (is_hex) {
        end_ptr += 2;
        while (isHexDigit(*end_ptr) || *end_ptr == '_') end_ptr++;
    } else {
        while (isDigit(*end_ptr) || *end_ptr == '_') end_ptr++;
    }


    if (end_ptr > start && *(end_ptr - 1) == '_') {
        this->current = end_ptr;
        this->column += (end_ptr - start);
        token.type = TOKEN_ERROR;
        return token;
    }

    bool is_float = false;
    if (*end_ptr == '.') {
        // Lookahead to distinguish between float literal and range operator
        if (end_ptr[1] == '.') {
            // This is an integer followed by a '..' operator.
            // Do not consume the dot; treat the preceding number as an integer.
        } else {
            is_float = true;
            end_ptr++;
            if (*(end_ptr) == '_') {
                 token.type = TOKEN_ERROR;
                 this->current = end_ptr;
                 this->column += (this->current - start);
                 return token;
            }
            while (isDigit(*end_ptr) || *end_ptr == '_') end_ptr++;
        }
    }

    if (end_ptr > start && *(end_ptr - 1) == '_') {
        token.type = TOKEN_ERROR;
        this->current = end_ptr;
        this->column += (end_ptr - start);
        return token;
    }
    if (*end_ptr == 'e' || *end_ptr == 'E') {
        is_float = true;
        end_ptr++;
        if (*end_ptr == '+' || *end_ptr == '-') {
            end_ptr++;
        }
        if (!isDigit(*end_ptr)) {
            token.type = TOKEN_ERROR;
            this->current = end_ptr;
            this->column += (end_ptr - start);
            return token;
        }
        while (isDigit(*end_ptr) || *end_ptr == '_') end_ptr++;
    }


    if (is_float) {
        char* final_end;
        token.value.floating_point = strtod(start, &final_end);
        this->column += (end_ptr - start);
        this->current = const_cast<char*>(end_ptr);
        token.type = TOKEN_FLOAT_LITERAL;
    } else {
        u64 value = parseInteger(start, end_ptr);
        if (value == (u64)-1) {
            token.type = TOKEN_ERROR;
        } else {
            token.value.integer = static_cast<i64>(value);
            token.type = TOKEN_INTEGER_LITERAL;
        }
        this->column += (end_ptr - start);
        this->current = const_cast<char*>(end_ptr);
    }

    return token;
}

u64 Lexer::parseInteger(const char* start, const char* end) {
    u64 result = 0;
    int base = 10;
    const char* p = start;
    bool overflow = false;

    if (*p == '0' && (p[1] == 'x' || p[1] == 'X')) {
        base = 16;
        p += 2;
    }

    for (; p < end; ++p) {
        if (*p == '_') {
             if (p + 1 < end && p[1] == '_') { // Double underscore
                return -1; // sentinel for error
            }
            continue; // Skip underscores
        }

        int digit;
        if (isDigit(*p)) {
            digit = *p - '0';
        } else if (base == 16 && isHexDigit(*p)) {
            digit = toLower(*p) - 'a' + 10;
        } else {
            // This can happen if a float is passed in, e.g., "1.2"
            break;
        }

        u64 max_val = 18446744073709551615U; // ULLONG_MAX
        if (result > (max_val - digit) / base) {
            overflow = true;
            break;
        }
        result = result * base + digit;
    }

    return overflow ? (u64)-1 : result;
}

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

    if (isDigit(c) || (c == '.' && isDigit(this->current[1]))) {
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
            if (match('&')) {
                token.type = TOKEN_AND;
            } else if (match('=')) {
                token.type = TOKEN_AMPERSAND_EQUAL;
            } else {
                token.type = TOKEN_AMPERSAND;
            }
            break;
        case '|':
            if (match('|')) {
                token.type = TOKEN_OR;
            } else if (match('=')) {
                token.type = TOKEN_PIPE_EQUAL;
            } else {
                token.type = TOKEN_PIPE;
            }
            break;
        case '^': token.type = match('=') ? TOKEN_CARET_EQUAL : TOKEN_CARET; break;
        case '.': // Handles '.', '..', '...', '.*', '.?'
            if (isDigit(this->peek(1))) {
                return lexNumericLiteral();
            }
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
            if (c == 'c' && this->current[0] == '"') {
                this->current++; // Consume the "
                this->column++;
                return lexStringLiteral();
            }
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
                if (isDigit(digit)) {
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
                if (isDigit(digit)) {
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
