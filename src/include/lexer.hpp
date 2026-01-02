#ifndef LEXER_HPP
#define LEXER_HPP

#include "common.hpp"
#include "source_manager.hpp"
#include "string_interner.hpp"
#include "memory.hpp"

#define TAB_WIDTH 4

/**
 * @brief Checks if a character is a valid starting character for an identifier.
 * @param c The character to check.
 * @return `true` if the character can start an identifier, `false` otherwise.
 */
static inline bool isIdentifierStart(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

/**
 * @brief Checks if a character is a valid non-starting character for an identifier.
 * @param c The character to check.
 * @return `true` if the character can be part of an identifier, `false` otherwise.
 */
static inline bool isIdentifierChar(char c) {
    return isIdentifierStart(c) || (c >= '0' && c <= '9');
}

/**
 * @file lexer.hpp
 * @brief Defines the token types and structures for the RetroZig lexer.
 *
 * This file contains the core definitions for the lexical analysis phase of
 * the compiler, including the TokenType enum which represents all possible
 * tokens in the Zig subset.
 */

/**
 * @enum TokenType
 * @brief Defines the different types of tokens that the lexer can produce.
 *
 * The enum is organized into logical groups for clarity:
 * - Control tokens
 * - Literals for identifiers and values
 * - Keywords for the language syntax
 * - Operators for expressions
 * - Delimiters for code structure
 */
enum TokenType {
    // Control Tokens
    TOKEN_EOF,              ///< End of the source file.
    TOKEN_ERROR,            ///< Represents a lexical error.

    // Literals
    TOKEN_IDENTIFIER,       ///< An identifier (e.g., variable name, function name).
    TOKEN_INTEGER_LITERAL,  ///< An integer literal (e.g., 123, 0xFF).
    TOKEN_STRING_LITERAL,   ///< A string literal (e.g., "hello").
    TOKEN_CHAR_LITERAL,     ///< A character literal (e.g., 'a').
    TOKEN_FLOAT_LITERAL,    ///< A float literal (e.g., 3.14).

    // Keywords
    TOKEN_FN,               ///< 'fn' keyword for function definitions.
    TOKEN_VAR,              ///< 'var' keyword for mutable variable declarations.
    TOKEN_CONST,            ///< 'const' keyword for immutable variable declarations.
    TOKEN_IF,               ///< 'if' keyword for conditional statements.
    TOKEN_ELSE,             ///< 'else' keyword for conditional statements.
    TOKEN_WHILE,            ///< 'while' keyword for loops.
    TOKEN_RETURN,           ///< 'return' keyword for function returns.
    TOKEN_DEFER,            ///< 'defer' keyword for scope-exit actions.
    TOKEN_TRUE,             ///< 'true' keyword.
    TOKEN_FALSE,            ///< 'false' keyword.
    TOKEN_BREAK,            ///< 'break' keyword.
    TOKEN_CATCH,            ///< 'catch' keyword.
    TOKEN_CONTINUE,         ///< 'continue' keyword.
    TOKEN_FOR,              ///< 'for' keyword.
    TOKEN_ORELSE,           ///< 'orelse' keyword.
    TOKEN_RESUME,           ///< 'resume' keyword.
    TOKEN_SUSPEND,          ///< 'suspend' keyword.
    TOKEN_SWITCH,           ///< 'switch' keyword.
    TOKEN_TRY,              ///< 'try' keyword.

    // Type Declaration Keywords
    TOKEN_ENUM,             ///< 'enum' keyword.
    TOKEN_ERROR_SET,        ///< 'error' keyword.
    TOKEN_STRUCT,           ///< 'struct' keyword.
    TOKEN_UNION,            ///< 'union' keyword.
    TOKEN_OPAQUE,           ///< 'opaque' keyword.

    // Visibility and Linkage Keywords
    TOKEN_EXPORT,           ///< 'export' keyword.
    TOKEN_EXTERN,           ///< 'extern' keyword.
    TOKEN_PUB,              ///< 'pub' keyword.
    TOKEN_LINKSECTION,      ///< 'linksection' keyword.
    TOKEN_USINGNAMESPACE,   ///< 'usingnamespace' keyword.

    // Compile-time and Special Function Keywords
    TOKEN_ASM,              ///< 'asm' keyword.
    TOKEN_COMPTIME,         ///< 'comptime' keyword.
    TOKEN_ERRDEFER,         ///< 'errdefer' keyword.
    TOKEN_INLINE,           ///< 'inline' keyword.
    TOKEN_NOINLINE,         ///< 'noinline' keyword.
    TOKEN_TEST,             ///< 'test' keyword.
    TOKEN_UNREACHABLE,      ///< 'unreachable' keyword.

    // Miscellaneous Keywords
    TOKEN_ADDRSPACE,        ///< 'addrspace' keyword.
    TOKEN_ALIGN,            ///< 'align' keyword.
    TOKEN_ALLOWZERO,        ///< 'allowzero' keyword.
    TOKEN_AND,              ///< 'and' keyword.
    TOKEN_ANYFRAME,         ///< 'anyframe' keyword.
    TOKEN_ANYTYPE,          ///< 'anytype' keyword.
    TOKEN_CALLCONV,         ///< 'callconv' keyword.
    TOKEN_NOALIAS,          ///< 'noalias' keyword.
    TOKEN_NOSUSPEND,        ///< 'nosuspend' keyword.
    TOKEN_OR,               ///< 'or' keyword.
    TOKEN_PACKED,           ///< 'packed' keyword.
    TOKEN_THREADLOCAL,      ///< 'threadlocal' keyword.
    TOKEN_VOLATILE,         ///< 'volatile' keyword.

    // Operators
    TOKEN_PLUS,             ///< '+' operator.
    TOKEN_MINUS,            ///< '-' operator.
    TOKEN_STAR,             ///< '*' operator.
    TOKEN_SLASH,            ///< '/' operator.
    TOKEN_PERCENT,          ///< '%' operator.
    TOKEN_TILDE,            ///< '~' operator.
    TOKEN_AMPERSAND,        ///< '&' operator.
    TOKEN_PIPE,             ///< '|' operator.
    TOKEN_CARET,            ///< '^' operator.
    TOKEN_LARROW2,          ///< '<<' operator.
    TOKEN_RARROW2,          ///< '>>' operator.

    // Comparison and Equality Operators
    TOKEN_EQUAL,            ///< '=' operator (assignment).
    TOKEN_EQUAL_EQUAL,      ///< '==' operator (equality).
    TOKEN_BANG,             ///< '!' operator (logical not).
    TOKEN_BANG_EQUAL,       ///< '!=' operator (inequality).
    TOKEN_LESS,             ///< '<' operator.
    TOKEN_LESS_EQUAL,       ///< '<=' operator.
    TOKEN_GREATER,          ///< '>' operator.
    TOKEN_GREATER_EQUAL,    ///< '>=' operator.

    // Compound Assignment Operators
    TOKEN_PLUS_EQUAL,       ///< '+=' operator.
    TOKEN_MINUS_EQUAL,      ///< '-=' operator.
    TOKEN_STAR_EQUAL,       ///< '*=' operator.
    TOKEN_SLASH_EQUAL,      ///< '/=' operator.
    TOKEN_PERCENT_EQUAL,    ///< '%=' operator.
    TOKEN_AMPERSAND_EQUAL,  ///< '&=' operator.
    TOKEN_PIPE_EQUAL,       ///< '|=' operator.
    TOKEN_CARET_EQUAL,      ///< '^=' operator.
    TOKEN_LARROW2_EQUAL,    ///< '<<=' operator.
    TOKEN_RARROW2_EQUAL,    ///< '>>=' operator.

    // Delimiters
    TOKEN_LPAREN,           ///< '(' - Left parenthesis.
    TOKEN_RPAREN,           ///< ')' - Right parenthesis.
    TOKEN_LBRACE,           ///< '{' - Left brace.
    TOKEN_RBRACE,           ///< '}' - Right brace.
    TOKEN_LBRACKET,         ///< '[' - Left bracket.
    TOKEN_RBRACKET,         ///< ']' - Right bracket.
    TOKEN_SEMICOLON,        ///< ';' - Semicolon.
    TOKEN_COLON,            ///< ':' - Colon.
    TOKEN_COMMA,            ///< ',' - Comma.
    TOKEN_ARROW,            ///< '->' - Arrow.
    TOKEN_FAT_ARROW,        ///< '=>' - Fat arrow.
    TOKEN_ELLIPSIS,         ///< '...' - Ellipsis.
    TOKEN_RANGE,            ///< '..' - Range operator.

    // Special and Wrapping Operators
    TOKEN_DOT,              ///< '.' operator.
    TOKEN_DOT_ASTERISK,     ///< '.*' operator.
    TOKEN_DOT_QUESTION,     ///< '.?' operator.
    TOKEN_QUESTION,         ///< '?' operator.
    TOKEN_PLUS2,            ///< '++' operator.
    TOKEN_MINUS2,           ///< '--' operator.
    TOKEN_STAR2,            ///< '**' operator.
    TOKEN_PIPE2,            ///< '||' operator.
    TOKEN_AMPERSAND2,       ///< '&&' operator.
    TOKEN_PLUSPERCENT,      ///< '+%' operator.
    TOKEN_MINUSPERCENT,     ///< '-%' operator.
    TOKEN_STARPERCENT,      ///< '*%' operator.
};

/**
 * @struct Keyword
 * @brief Represents a language keyword and its corresponding token type.
 */
struct Keyword {
    const char* name;
    size_t len;      // Optimized length field
    TokenType type;
};

/**
 * @brief Extern declaration for the global keyword lookup table.
 * The table is defined in lexer.cpp and sorted alphabetically.
 */
extern const Keyword keywords[];
extern const int num_keywords;


/**
 * @struct Token
 * @brief Represents a single token produced by the lexer.
 *
 * A token is the smallest unit of meaning in the source code. It consists of
 * a type, its location in the source file, and an optional value for literals.
 */
struct Token {
    /** @brief The type of the token, as defined by the TokenType enum. */
    TokenType type;

    /** @brief The location (file, line, column) where the token was found. */
    SourceLocation location;

    /**
     * @union Value
     * @brief Stores the literal value of the token, if applicable.
     *
     * This union provides storage for different kinds of literal values.
     * The active member depends on the token's type:
     * - `identifier`: for TOKEN_IDENTIFIER (pointer to interned string)
     * - `integer`: for TOKEN_INTEGER_LITERAL
     * - `floating_point`: for potential future floating-point tokens
     */
    union {
        /** @brief Pointer to an interned string for identifiers. */
        const char* identifier;
        /** @brief Struct for integer literals. */
        struct {
            u64 value;
            bool is_unsigned;
            bool is_long;
        } integer_literal;
        /** @brief 64-bit floating-point for float literals. */
        double floating_point;
        /** @brief Character for char literals. */
        u32 character;
    } value;

    Token() : type(TOKEN_ERROR), location() {
        value.integer_literal.value = 0;
        value.integer_literal.is_unsigned = false;
        value.integer_literal.is_long = false;
    }
};

/**
 * @class Lexer
 * @brief Processes source code and converts it into a stream of tokens.
 *
 * The Lexer is responsible for the first phase of compilation, turning raw
 * source text into a sequence of tokens that the parser can understand. It
 * handles skipping whitespace, comments, and recognizing keywords, identifiers,
 * literals, and operators.
 */
class Lexer {
private:
    const char* current;      ///< Pointer to the current character in the source buffer.
    SourceManager& source;    ///< Reference to the source manager for location tracking.
    StringInterner& interner; ///< Reference to the string interner for identifiers.
    ArenaAllocator& arena;    ///< Reference to the arena allocator for temporary buffers.
    u32 file_id;              ///< The ID of the file currently being lexed.
    u32 line;                 ///< The current line number.
    u32 column;               ///< The current column number.

    // Helper methods for tokenization
    /**
     * @brief Parses a decimal floating-point literal from the source.
     *
     * This function handles the parsing of decimal floats, including support
     * for underscores as separators in the integer, fractional, and exponent
     * parts. It replaces the dependency on `strtod` to ensure consistent
     * parsing behavior across different locales and to support Zig-specific
     * syntax.
     *
     * @param start A pointer to the beginning of the float literal in the source.
     * @param end A pointer that will be updated to point to the character
     *            immediately following the parsed float literal.
     * @return The parsed `double` value.
     */
    double parseDecimalFloat(const char* start, const char** end);
    bool match(char expected);
    Token lexCharLiteral();
    Token lexNumericLiteral();
    u32 parseEscapeSequence(bool& success);
    Token parseHexFloat();
    Token lexIdentifierOrKeyword();
    Token lexStringLiteral();

public:
    /**
     * @brief Constructs a new Lexer instance.
     * @param src A reference to the SourceManager containing the source files.
     * @param interner A reference to the StringInterner for managing strings.
     * @param arena A reference to the ArenaAllocator for temporary allocations.
     * @param file_id The identifier of the specific file to be lexed from the SourceManager.
     */
    Lexer(SourceManager& src, StringInterner& interner, ArenaAllocator& arena, u32 file_id);

    /**
     * @brief Scans the source code and returns the next token.
     * @return The next token found in the source stream. When the end of the
     *         file is reached, it will consistently return a token of type
     *         TOKEN_EOF.
     */
    Token nextToken();
    /**
     * @brief Safely peeks at a character in the source buffer at a given offset.
     *
     * This method allows looking ahead in the source stream without consuming
     * characters. It is guaranteed to be safe and will not read past the end
     * of the source buffer.
     *
     * @param n The offset from the current position to peek at. A value of 0
     *          (the default) peeks at the current character.
     * @return The character at the specified offset. If the offset is beyond
     *         the end of the source file, it returns the null terminator ('\0').
     */
    char peek(int n = 0) const;
    /**
     * @brief Advances the lexer's position by the given number of characters.
     * @param n The number of characters to advance. Defaults to 1.
     */
    void advance(int n = 1);
};


#endif // LEXER_HPP
