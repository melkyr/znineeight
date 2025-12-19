#include "lexer.hpp"
#include "source_manager.hpp"
#include "memory.hpp"
#include <cctype>
#include <cstdlib> // For strtol, strtod
#include <cmath>   // For ldexp
#include <cstring> // For strcmp

// Keyword lookup table.
// IMPORTANT: This array must be kept sorted alphabetically for the binary search to work.
const Keyword keywords[] = {
    {"addrspace", TOKEN_ADDRSPACE},
    {"align", TOKEN_ALIGN},
    {"allowzero", TOKEN_ALLOWZERO},
    {"and", TOKEN_AND},
    {"anyframe", TOKEN_ANYFRAME},
    {"anytype", TOKEN_ANYTYPE},
    {"asm", TOKEN_ASM},
    {"break", TOKEN_BREAK},
    {"callconv", TOKEN_CALLCONV},
    {"catch", TOKEN_CATCH},
    {"comptime", TOKEN_COMPTIME},
    {"const", TOKEN_CONST},
    {"continue", TOKEN_CONTINUE},
    {"defer", TOKEN_DEFER},
    {"else", TOKEN_ELSE},
    {"enum", TOKEN_ENUM},
    {"errdefer", TOKEN_ERRDEFER},
    {"error", TOKEN_ERROR_SET},
    {"export", TOKEN_EXPORT},
    {"extern", TOKEN_EXTERN},
    {"fn", TOKEN_FN},
    {"for", TOKEN_FOR},
    {"if", TOKEN_IF},
    {"inline", TOKEN_INLINE},
    {"linksection", TOKEN_LINKSECTION},
    {"noalias", TOKEN_NOALIAS},
    {"noinline", TOKEN_NOINLINE},
    {"nosuspend", TOKEN_NOSUSPEND},
    {"opaque", TOKEN_OPAQUE},
    {"or", TOKEN_OR},
    {"orelse", TOKEN_ORELSE},
    {"packed", TOKEN_PACKED},
    {"pub", TOKEN_PUB},
    {"resume", TOKEN_RESUME},
    {"return", TOKEN_RETURN},
    {"struct", TOKEN_STRUCT},
    {"suspend", TOKEN_SUSPEND},
    {"switch", TOKEN_SWITCH},
    {"test", TOKEN_TEST},
    {"threadlocal", TOKEN_THREADLOCAL},
    {"try", TOKEN_TRY},
    {"union", TOKEN_UNION},
    {"unreachable", TOKEN_UNREACHABLE},
    {"usingnamespace", TOKEN_USINGNAMESPACE},
    {"var", TOKEN_VAR},
    {"volatile", TOKEN_VOLATILE},
    {"while", TOKEN_WHILE},
};
const int num_keywords = sizeof(keywords) / sizeof(Keyword);

static TokenType lookupIdentifier(const char* name) {
    int left = 0;
    int right = num_keywords - 1;

    while (left <= right) {
        int mid = left + (right - left) / 2;
        int cmp = strcmp(name, keywords[mid].name);
        if (cmp == 0) {
            return keywords[mid].type;
        } else if (cmp < 0) {
            right = mid - 1;
        } else {
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
    Token token;
    token.location.file_id = this->file_id;
    token.location.line = this->line;
    token.location.column = this->column;

    if (*this->current == '\'') {
        this->current++; // Consume the closing '
        this->column++;
        token.type = TOKEN_ERROR; // Empty character literal
        return token;
    }

    long value;
    if (*this->current == '\\') {
        this->current++;
        this->column++;
        switch (*this->current) {
            case 'n': value = '\n'; break;
            case 'r': value = '\r'; break;
            case 't': value = '\t'; break;
            case '\\': value = '\\'; break;
            case '\'': value = '\''; break;
            case 'x': {
                char hex_val = 0;
                for (int i = 0; i < 2; ++i) {
                    this->current++;
                    this->column++;
                    char c = *this->current;
                    if (c >= '0' && c <= '9') {
                        hex_val = (hex_val * 16) + (c - '0');
                    } else if (c >= 'a' && c <= 'f') {
                        hex_val = (hex_val * 16) + (c - 'a' + 10);
                    } else if (c >= 'A' && c <= 'F') {
                        hex_val = (hex_val * 16) + (c - 'A' + 10);
                    } else {
                        token.type = TOKEN_ERROR; // Invalid hex escape
                        return token;
                    }
                }
                value = hex_val;
                break;
            }
            case 'u': {
                if (*(++this->current) != '{') {
                    token.type = TOKEN_ERROR; // Invalid unicode escape
                    return token;
                }
                this->current++; // Skip '{'
                long unicode_val = 0;
                while(*this->current != '}') {
                    char c = *this->current;
                     if (c >= '0' && c <= '9') {
                        unicode_val = (unicode_val * 16) + (c - '0');
                    } else if (c >= 'a' && c <= 'f') {
                        unicode_val = (unicode_val * 16) + (c - 'a' + 10);
                    } else if (c >= 'A' && c <= 'F') {
                        unicode_val = (unicode_val * 16) + (c - 'A' + 10);
                    } else {
                        token.type = TOKEN_ERROR; // Invalid unicode escape
                        return token;
                    }
                    this->current++;
                }
                value = unicode_val;
                break;
            }
            default:
                token.type = TOKEN_ERROR; // Unsupported escape sequence
                return token;
        }
    } else {
        value = *this->current;
    }

    this->current++;
    this->column++;

    if (*this->current != '\'') {
        token.type = TOKEN_ERROR; // Unterminated or multi-character literal
        return token;
    }
    this->current++; // Consume the closing '
    this->column++;

    token.type = TOKEN_CHAR_LITERAL;
    token.value.character = (char)value;
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
    Token token;
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
 * This function determines whether a numeric literal is a hexadecimal float,
 * a decimal float, or an integer, and then calls the appropriate parsing
 * function. It uses `strtol` for integers and `strtod` for decimal floats.
 *
 * @return A `Token` of the appropriate numeric type (`TOKEN_INTEGER_LITERAL` or
 *         `TOKEN_FLOAT_LITERAL`) or `TOKEN_ERROR` if the format is invalid.
 */
Token Lexer::lexNumericLiteral() {
    Token token;
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


    // Temporarily advance to find the end of the number
    const char* end_ptr = start;
    if (is_hex) {
        end_ptr += 2;
    }
    while (isdigit(*end_ptr)) end_ptr++;
    bool is_float = false;
    if (*end_ptr == '.') {
        // Lookahead to distinguish between float literal and range operator
        if (end_ptr[1] == '.') {
            // This is an integer followed by a '..' operator.
            // Do not consume the dot.
        } else if (!isdigit(end_ptr[1])) {
             token.type = TOKEN_ERROR;
             this->current = end_ptr + 1;
             this->column += (this->current - start);
             return token;
        } else {
            end_ptr++;
            is_float = true;
        }
    }
    while (isdigit(*end_ptr)) end_ptr++;
    if (*end_ptr == 'e' || *end_ptr == 'E') {
        const char* exp_ptr = end_ptr + 1;
        if (*exp_ptr == '+' || *exp_ptr == '-') {
            exp_ptr++;
        }
        if (!isdigit(*exp_ptr)) {
            token.type = TOKEN_ERROR;
            return token;
        }
        is_float = true;
    }


    if (is_float) {
        char* end;
        token.value.floating_point = strtod(start, &end);
        this->column += (end - start);
        this->current = end;
        token.type = TOKEN_FLOAT_LITERAL;
    } else {
        char* end;
        token.value.integer = strtol(start, &end, 0); // Base 0 auto-detects hex
        this->column += (end - start);
        this->current = end;
        token.type = TOKEN_INTEGER_LITERAL;
    }

    return token;
}


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
            case '\t':
            case '\r':
                this->current++;
                this->column++;
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

    Token token;
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
            if (isalpha(c) || c == '_') {
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
    Token token;
    token.location.file_id = this->file_id;
    token.location.line = this->line;
    token.location.column = this->column;

    const char* start = this->current;
    DynamicArray<char> buffer(this->arena);

    while (*this->current != '"' && *this->current != '\0') {
        if (*this->current == '\\') {
            this->current++; // Consume the backslash
            switch (*this->current) {
                case 'n': buffer.append('\n'); break;
                case 'r': buffer.append('\r'); break;
                case 't': buffer.append('\t'); break;
                case '\\': buffer.append('\\'); break;
                case '"': buffer.append('"'); break;
                case 'x': {
                    this->current++; // Consume 'x'
                    char hex_val = 0;
                    for (int i = 0; i < 2; ++i) {
                        char c = *this->current;
                        if (c >= '0' && c <= '9') {
                            hex_val = (hex_val * 16) + (c - '0');
                        } else if (c >= 'a' && c <= 'f') {
                            hex_val = (hex_val * 16) + (c - 'a' + 10);
                        } else if (c >= 'A' && c <= 'F') {
                            hex_val = (hex_val * 16) + (c - 'A' + 10);
                        } else {
                            token.type = TOKEN_ERROR; // Invalid hex escape
                            return token;
                        }
                        this->current++;
                    }
                    this->current--; // Backtrack one char
                    buffer.append(hex_val);
                    break;
                }
                default:
                    token.type = TOKEN_ERROR; // Unsupported escape sequence
                    return token;
            }
        } else {
            buffer.append(*this->current);
        }
        this->current++;
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
    Token token;
    token.location.file_id = this->file_id;
    token.location.line = this->line;
    token.location.column = this->column;

    const char* start = this->current;
    while (isalnum(*this->current) || *this->current == '_') {
        this->current++;
    }

    int length = this->current - start;
    char buffer[256];
    if (length >= 256) {
        token.type = TOKEN_ERROR;
        this->column += length;
        return token;
    }

    strncpy(buffer, start, length);
    buffer[length] = '\0';

    token.type = lookupIdentifier(buffer);

    if (token.type == TOKEN_IDENTIFIER) {
        token.value.identifier = this->interner.intern(buffer);
    }

    this->column += length;
    return token;
}
