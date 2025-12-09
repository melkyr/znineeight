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
 * @brief Scans and returns the next token from the source code.
 *
 * TODO: Implement the full logic for lexical analysis.
 * This function should scan the source code character by character and
 * construct the next valid token. It needs to handle whitespace, comments,
 * identifiers, keywords, literals, and operators.
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

    switch (c) {
        case '\0':
            token.type = TOKEN_EOF;
            break;
        case '+':
            token.type = TOKEN_PLUS;
            break;
        case '-':
            token.type = TOKEN_MINUS;
            break;
        case '*':
            token.type = TOKEN_STAR;
            break;
        case '/':
            token.type = TOKEN_SLASH;
            break;
        case ';':
            token.type = TOKEN_SEMICOLON;
            break;
        case '(':
            token.type = TOKEN_LPAREN;
            break;
        case ')':
            token.type = TOKEN_RPAREN;
            break;
        case '{':
            token.type = TOKEN_LBRACE;
            break;
        case '}':
            token.type = TOKEN_RBRACE;
            break;
        case '[':
            token.type = TOKEN_LBRACKET;
            break;
        case ']':
            token.type = TOKEN_RBRACKET;
            break;
        default:
            token.type = TOKEN_ERROR;
            break;
    }

    this->current++;
    this->column++;

    return token;
}
