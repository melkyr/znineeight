#include "../include/lexer.hpp"
#include "../include/source_manager.hpp"

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

/**
 * @brief Scans and returns the next token from the source code.
 *
 * This function scans the source code character by character to construct the
 * next valid token. It handles whitespace, single-character and multi-character
 * operators using a lookahead mechanism.
 *
 * @return The next token in the source stream.
 */
Token Lexer::nextToken() {
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

    this->current++;
    this->column++;

    switch (c) {
        case '+': token.type = TOKEN_PLUS; break;
        case '-': token.type = TOKEN_MINUS; break;
        case '*': token.type = TOKEN_STAR; break;
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
        case '<': token.type = match('=') ? TOKEN_LESS_EQUAL : TOKEN_LESS; break;
        case '>': token.type = match('=') ? TOKEN_GREATER_EQUAL : TOKEN_GREATER; break;
        default: token.type = TOKEN_ERROR; break;
    }

    return token;
}
