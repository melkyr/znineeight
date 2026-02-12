#ifndef CODEGEN_HPP
#define CODEGEN_HPP

#include "common.hpp"
#include "platform.hpp"
#include "c_variable_allocator.hpp"
#include "ast.hpp"
#include "type_system.hpp"
#include <cstddef>

/**
 * @class C89Emitter
 * @brief Handles buffered emission of C89 code to a file.
 *
 * This class provides a 4KB stack buffer for efficient writing and supports
 * indentation and C89-style comments.
 */
class C89Emitter {
public:
    /**
     * @brief Constructs an uninitialized emitter. Call open() before use.
     * @param arena The ArenaAllocator for CVariableAllocator.
     */
    C89Emitter(ArenaAllocator& arena);

    /**
     * @brief Constructs an emitter that writes to the specified file.
     * @param arena The ArenaAllocator for CVariableAllocator.
     * @param path The path to the output file.
     */
    C89Emitter(ArenaAllocator& arena, const char* path);

    /**
     * @brief Constructs an emitter that writes to an already open file.
     * @param arena The ArenaAllocator for CVariableAllocator.
     * @param file The open file handle.
     */
    C89Emitter(ArenaAllocator& arena, PlatFile file);

    /**
     * @brief Destructor. Flushes and closes the file if it was opened by the constructor.
     */
    ~C89Emitter();

    /**
     * @brief Increases the current indentation level.
     */
    void indent();

    /**
     * @brief Decreases the current indentation level.
     */
    void dedent();

    /**
     * @brief Writes the current indentation (4 spaces per level) to the buffer.
     */
    void writeIndent();

    /**
     * @brief Writes raw data to the buffer, flushing to file if necessary.
     * @param data The data to write.
     * @param len The length of the data.
     */
    void write(const char* data, size_t len);

    /**
     * @brief Writes a null-terminated string to the buffer.
     * @param str The string to write.
     */
    void writeString(const char* str);

    /**
     * @brief Writes a C89-style comment to the buffer.
     * @param text The comment text.
     */
    void emitComment(const char* text);

    /**
     * @brief Flushes the internal buffer to the file.
     */
    void flush();

    /**
     * @brief Opens a file for writing.
     * @param path The path to the file.
     * @return True if the file was successfully opened.
     */
    bool open(const char* path);

    /**
     * @brief Closes the output file.
     */
    void close();

    /**
     * @brief Prepares the emitter for a new function.
     */
    void beginFunction();

    /**
     * @brief Returns the variable allocator.
     */
    CVariableAllocator& getVarAlloc() { return var_alloc_; }

    /**
     * @brief Emits a general expression.
     * @param node The expression node.
     */
    void emitExpression(const ASTNode* node);

    /**
     * @brief Emits an integer literal expression.
     * @param node The integer literal node.
     */
    void emitIntegerLiteral(const ASTIntegerLiteralNode* node);

    /**
     * @brief Emits a float literal expression.
     * @param node The float literal node.
     */
    void emitFloatLiteral(const ASTFloatLiteralNode* node);

    /**
     * @brief Emits a string literal expression.
     * @param node The string literal node.
     */
    void emitStringLiteral(const ASTStringLiteralNode* node);

    /**
     * @brief Emits a character literal expression.
     * @param node The character literal node.
     */
    void emitCharLiteral(const ASTCharLiteralNode* node);

    /**
     * @brief Returns true if the emitter is in a valid state (file open).
     */
    bool isValid() const { return output_file_ != PLAT_INVALID_FILE; }

private:
    /**
     * @brief Emits a byte with proper C89 escaping.
     * @param c The byte to emit.
     * @param is_char_literal True if emitting inside a character literal.
     */
    void emitEscapedByte(unsigned char c, bool is_char_literal);

    char buffer_[4096];
    size_t buffer_pos_;
    PlatFile output_file_;
    int indent_level_;
    bool owns_file_;
    CVariableAllocator var_alloc_;

    // Prevent copying
    C89Emitter(const C89Emitter&);
    C89Emitter& operator=(const C89Emitter&);
};

#endif // CODEGEN_HPP
