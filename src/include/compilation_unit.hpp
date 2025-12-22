#ifndef COMPILATION_UNIT_HPP
#define COMPILATION_UNIT_HPP

#include "common.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"
#include "lexer.hpp"
#include "parser.hpp"
#include <cstring> // For strlen

/**
 * @class CompilationUnit
 * @brief Manages the lifetime of all objects related to a single compilation.
 *
 * This class ties together the ArenaAllocator, StringInterner, and SourceManager
 * to provide a clean interface for compiling a source file. It ensures that
 * all allocated memory and resources are self-contained, preventing memory
 * corruption and simplifying resource management.
 */
class CompilationUnit {
public:
    /**
     * @brief Constructs a new CompilationUnit.
     * @param arena The ArenaAllocator to be used for all allocations.
     * @param interner The StringInterner for deduplicating strings.
     */
    CompilationUnit(ArenaAllocator& arena, StringInterner& interner)
        : arena_(arena), interner_(interner), source_manager_(arena) {}

    /**
     * @brief Adds a source file to the compilation.
     * @param filename The name of the file.
     * @param source A pointer to the source code.
     * @return The file ID for the newly added source file.
     */
    u32 addSource(const char* filename, const char* source) {
        return source_manager_.addFile(filename, source, strlen(source));
    }

    /**
     * @brief Creates a Parser for a given source file.
     *
     * This method tokenizes the entire source file and then constructs a Parser
     * instance ready to begin parsing.
     *
     * @param file_id The ID of the file to parse.
     * @return A Parser instance for the specified file.
     */
    Parser createParser(u32 file_id) {
        Lexer lexer(source_manager_, interner_, arena_, file_id);
        DynamicArray<Token> tokens(arena_);
        while (true) {
            Token token = lexer.nextToken();
            tokens.append(token);
            if (token.type == TOKEN_EOF) {
                break;
            }
        }
        return Parser(tokens.getData(), tokens.length(), &arena_);
    }

private:
    ArenaAllocator& arena_;
    StringInterner& interner_;
    SourceManager source_manager_;
    // Other state: AST root, diagnostics, etc. could be added here.
};

#endif // COMPILATION_UNIT_HPP
