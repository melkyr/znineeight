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
    this->current = src.getFileContent(file_id);
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
    // Dummy implementation: returns EOF for now.
    Token token;
    token.type = TOKEN_EOF;
    token.location.file_id = this->file_id;
    // TODO: The line and column will need to be properly tracked.
    token.location.line = 0;
    token.location.column = 0;
    return token;
}
