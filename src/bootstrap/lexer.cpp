#include "lexer.hpp"
#include "source_manager.hpp"
#include <cctype>
#include <cstdlib> // For strtol, strtod
#include <cmath>   // For ldexp

/**
 * @brief Constructs a new Lexer instance.
 *
 * Initializes the lexer with the source code to be processed.
 *
 * @param src A reference to the SourceManager containing the source file.
 * @param file_id The identifier of the file to be lexed.
 */
Lexer::Lexer(SourceManager& src, u32 file_id) : source(src), file_id(file_id) {
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
    token.value.integer = value;
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
        if (!isdigit(end_ptr[1])) {
             token.type = TOKEN_ERROR;
             return token;
        }
        end_ptr++;
        is_float = true;
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
        case '+': token.type = TOKEN_PLUS; break;
        case '-': token.type = TOKEN_MINUS; break;
        case '*': token.type = TOKEN_STAR; break;
        case '.': token.type = TOKEN_DOT; break;
        case '/':
            if (match('/')) {
                while (*this->current != '\n' && *this->current != '\0') {
                    this->current++;
                    this->column++;
                }
                return nextToken();
            } else if (match('*')) {
                int nesting = 1;
                while (nesting > 0) {
                    if (*this->current == '\0') {
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
                token.type = TOKEN_SLASH;
            }
            break;
        case ';': token.type = TOKEN_SEMICOLON; break;
        case '(': token.type = TOKEN_LPAREN; break;
        case ')': token.type = TOKEN_RPAREN; break;
        case '{': token.type = TOKEN_LBRACE; break;
        case '}': token.type = TOKEN_RBRACE; break;
        case '[': token.type = TOKEN_LBRACKET; break;
        case ']': token.type = TOKEN_RBRACKET; break;
        case '=': token.type = match('=') ? TOKEN_EQUAL_EQUAL : TOKEN_EQUAL; break;
        case '!': token.type = match('=') ? TOKEN_BANG_EQUAL : TOKEN_BANG; break;
        case '<':
            if (match('<')) {
                token.type = TOKEN_LARROW2;
            } else {
                token.type = match('=') ? TOKEN_LESS_EQUAL : TOKEN_LESS;
            }
            break;
        case '>':
            if (match('>')) {
                token.type = TOKEN_RARROW2;
            } else {
                token.type = match('=') ? TOKEN_GREATER_EQUAL : TOKEN_GREATER;
            }
            break;
        case '%': token.type = TOKEN_PERCENT; break;
        case '~': token.type = TOKEN_TILDE; break;
        case '&': token.type = TOKEN_AMPERSAND; break;
        case '|': token.type = TOKEN_PIPE; break;
        case '^': token.type = TOKEN_CARET; break;
        case '\'':
            token = lexCharLiteral();
            break;
        default: token.type = TOKEN_ERROR; break;
    }

    return token;
}
