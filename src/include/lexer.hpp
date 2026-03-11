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
enum Zig0TokenType {
    // Control Tokens
    ZIG_TOKEN_EOF,              ///< End of the source file.
    ZIG_TOKEN_ERROR,            ///< Represents a lexical error.

    // Literals
    ZIG_TOKEN_IDENTIFIER,       ///< An identifier (e.g., variable name, function name).
    ZIG_TOKEN_INTEGER_LITERAL,  ///< An integer literal (e.g., 123, 0xFF).
    ZIG_TOKEN_STRING_LITERAL,   ///< A string literal (e.g., "hello").
    ZIG_TOKEN_CHAR_LITERAL,     ///< A character literal (e.g., 'a').
    ZIG_TOKEN_FLOAT_LITERAL,    ///< A float literal (e.g., 3.14).

    // Keywords
    ZIG_TOKEN_FN,               ///< 'fn' keyword for function definitions.
    ZIG_TOKEN_VAR,              ///< 'var' keyword for mutable variable declarations.
    ZIG_TOKEN_CONST,            ///< 'const' keyword for immutable variable declarations.
    ZIG_TOKEN_IF,               ///< 'if' keyword for conditional statements.
    ZIG_TOKEN_ELSE,             ///< 'else' keyword for conditional statements.
    ZIG_TOKEN_WHILE,            ///< 'while' keyword for loops.
    ZIG_TOKEN_RETURN,           ///< 'return' keyword for function returns.
    ZIG_TOKEN_DEFER,            ///< 'defer' keyword for scope-exit actions.
    ZIG_TOKEN_TRUE,             ///< 'true' keyword.
    ZIG_TOKEN_FALSE,            ///< 'false' keyword.
    ZIG_TOKEN_NULL,             ///< 'null' keyword.
    ZIG_TOKEN_UNDEFINED,        ///< 'undefined' keyword.
    ZIG_TOKEN_BREAK,            ///< 'break' keyword.
    ZIG_TOKEN_CATCH,            ///< 'catch' keyword.
    ZIG_TOKEN_CONTINUE,         ///< 'continue' keyword.
    ZIG_TOKEN_FOR,              ///< 'for' keyword.
    ZIG_TOKEN_ORELSE,           ///< 'orelse' keyword.
    ZIG_TOKEN_RESUME,           ///< 'resume' keyword.
    ZIG_TOKEN_SUSPEND,          ///< 'suspend' keyword.
    ZIG_TOKEN_SWITCH,           ///< 'switch' keyword.
    ZIG_TOKEN_TRY,              ///< 'try' keyword.

    // Type Declaration Keywords
    ZIG_TOKEN_ENUM,             ///< 'enum' keyword.
    ZIG_TOKEN_ERROR_SET,        ///< 'error' keyword.
    ZIG_TOKEN_STRUCT,           ///< 'struct' keyword.
    ZIG_TOKEN_UNION,            ///< 'union' keyword.
    ZIG_TOKEN_OPAQUE,           ///< 'opaque' keyword.

    // Visibility and Linkage Keywords
    ZIG_TOKEN_EXPORT,           ///< 'export' keyword.
    ZIG_TOKEN_EXTERN,           ///< 'extern' keyword.
    ZIG_TOKEN_PUB,              ///< 'pub' keyword.
    ZIG_TOKEN_LINKSECTION,      ///< 'linksection' keyword.
    ZIG_TOKEN_USINGNAMESPACE,   ///< 'usingnamespace' keyword.

    // Compile-time and Special Function Keywords
    ZIG_TOKEN_ASM,              ///< 'asm' keyword.
    ZIG_TOKEN_COMPTIME,         ///< 'comptime' keyword.
    ZIG_TOKEN_ERRDEFER,         ///< 'errdefer' keyword.
    ZIG_TOKEN_INLINE,           ///< 'inline' keyword.
    ZIG_TOKEN_NOINLINE,         ///< 'noinline' keyword.
    ZIG_TOKEN_TEST,             ///< 'test' keyword.
    ZIG_TOKEN_UNREACHABLE,      ///< 'unreachable' keyword.

    // Miscellaneous Keywords
    ZIG_TOKEN_ADDRSPACE,        ///< 'addrspace' keyword.
    ZIG_TOKEN_ALIGN,            ///< 'align' keyword.
    ZIG_TOKEN_ALLOWZERO,        ///< 'allowzero' keyword.
    ZIG_TOKEN_AND,              ///< 'and' keyword.
    ZIG_TOKEN_ANYFRAME,         ///< 'anyframe' keyword.
    ZIG_TOKEN_ANYTYPE,          ///< 'anytype' keyword.
    ZIG_TOKEN_C_CHAR,           ///< 'c_char' keyword.
    ZIG_TOKEN_TYPE,             ///< 'type' keyword.
    ZIG_TOKEN_CALLCONV,         ///< 'callconv' keyword.
    ZIG_TOKEN_NOALIAS,          ///< 'noalias' keyword.
    ZIG_TOKEN_NORETURN,         ///< 'noreturn' keyword.
    ZIG_TOKEN_NOSUSPEND,        ///< 'nosuspend' keyword.
    ZIG_TOKEN_OR,               ///< 'or' keyword.
    ZIG_TOKEN_PACKED,           ///< 'packed' keyword.
    ZIG_TOKEN_THREADLOCAL,      ///< 'threadlocal' keyword.
    ZIG_TOKEN_VOLATILE,         ///< 'volatile' keyword.

    // Operators
    ZIG_TOKEN_PLUS,             ///< '+' operator.
    ZIG_TOKEN_MINUS,            ///< '-' operator.
    ZIG_TOKEN_STAR,             ///< '*' operator.
    ZIG_TOKEN_SLASH,            ///< '/' operator.
    ZIG_TOKEN_PERCENT,          ///< '%' operator.
    ZIG_TOKEN_TILDE,            ///< '~' operator.
    ZIG_TOKEN_AMPERSAND,        ///< '&' operator.
    ZIG_TOKEN_PIPE,             ///< '|' operator.
    ZIG_TOKEN_CARET,            ///< '^' operator.
    ZIG_TOKEN_LARROW2,          ///< '<<' operator.
    ZIG_TOKEN_RARROW2,          ///< '>>' operator.

    // Comparison and Equality Operators
    ZIG_TOKEN_EQUAL,            ///< '=' operator (assignment).
    ZIG_TOKEN_EQUAL_EQUAL,      ///< '==' operator (equality).
    ZIG_TOKEN_BANG,             ///< '!' operator (logical not).
    ZIG_TOKEN_BANG_EQUAL,       ///< '!=' operator (inequality).
    ZIG_TOKEN_LESS,             ///< '<' operator.
    ZIG_TOKEN_LESS_EQUAL,       ///< '<=' operator.
    ZIG_TOKEN_GREATER,          ///< '>' operator.
    ZIG_TOKEN_GREATER_EQUAL,    ///< '>=' operator.

    // Compound Assignment Operators
    ZIG_TOKEN_PLUS_EQUAL,       ///< '+=' operator.
    ZIG_TOKEN_MINUS_EQUAL,      ///< '-=' operator.
    ZIG_TOKEN_STAR_EQUAL,       ///< '*=' operator.
    ZIG_TOKEN_SLASH_EQUAL,      ///< '/=' operator.
    ZIG_TOKEN_PERCENT_EQUAL,    ///< '%=' operator.
    ZIG_TOKEN_AMPERSAND_EQUAL,  ///< '&=' operator.
    ZIG_TOKEN_PIPE_EQUAL,       ///< '|=' operator.
    ZIG_TOKEN_CARET_EQUAL,      ///< '^=' operator.
    ZIG_TOKEN_LARROW2_EQUAL,    ///< '<<=' operator.
    ZIG_TOKEN_RARROW2_EQUAL,    ///< '>>=' operator.
    ZIG_TOKEN_PIPE_PIPE,        ///< '||' operator.
    ZIG_TOKEN_AT_IMPORT,        ///< '@import' keyword-like.
    ZIG_TOKEN_AT_SIZEOF,        ///< '@sizeOf'
    ZIG_TOKEN_AT_ALIGNOF,       ///< '@alignOf'
    ZIG_TOKEN_AT_PTRCAST,       ///< '@ptrCast'
    ZIG_TOKEN_AT_INTCAST,       ///< '@intCast'
    ZIG_TOKEN_AT_FLOATCAST,     ///< '@floatCast'
    ZIG_TOKEN_AT_OFFSETOF,      ///< '@offsetOf'
    ZIG_TOKEN_AT_ENUM_TO_INT,   ///< '@enumToInt'
    ZIG_TOKEN_AT_PTR_TO_INT,    ///< '@ptrToInt'
    ZIG_TOKEN_AT_INT_TO_ENUM,   ///< '@intToEnum'

    // Delimiters
    ZIG_TOKEN_LPAREN,           ///< '(' - Left parenthesis.
    ZIG_TOKEN_RPAREN,           ///< ')' - Right parenthesis.
    ZIG_TOKEN_LBRACE,           ///< '{' - Left brace.
    ZIG_TOKEN_RBRACE,           ///< '}' - Right brace.
    ZIG_TOKEN_LBRACKET,         ///< '[' - Left bracket.
    ZIG_TOKEN_RBRACKET,         ///< ']' - Right bracket.
    ZIG_TOKEN_SEMICOLON,        ///< ';' - Semicolon.
    ZIG_TOKEN_COLON,            ///< ':' - Colon.
    ZIG_TOKEN_COMMA,            ///< ',' - Comma.
    ZIG_TOKEN_ARROW,            ///< '->' - Arrow.
    ZIG_TOKEN_FAT_ARROW,        ///< '=>' - Fat arrow.
    ZIG_TOKEN_ELLIPSIS,         ///< '...' - Ellipsis.
    ZIG_TOKEN_RANGE,            ///< '..' - Range operator.

    // Special and Wrapping Operators
    ZIG_TOKEN_DOT,              ///< '.' operator.
    ZIG_TOKEN_DOT_ASTERISK,     ///< '.*' operator.
    ZIG_TOKEN_DOT_QUESTION,     ///< '.?' operator.
    ZIG_TOKEN_QUESTION,         ///< '?' operator.
    ZIG_TOKEN_STAR2,            ///< '**' operator.
    ZIG_TOKEN_PLUSPERCENT,      ///< '+%' operator.
    ZIG_TOKEN_MINUSPERCENT,     ///< '-%' operator.
    ZIG_TOKEN_STARPERCENT       ///< '*%' operator.
};

/**
 * @struct Keyword
 * @brief Represents a language keyword and its corresponding token type.
 */
struct Keyword {
    const char* name;
    size_t len;      // Optimized length field
    Zig0TokenType type;
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
    /** @brief The type of the token, as defined by the Zig0TokenType enum. */
    Zig0TokenType type;

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

    Token() : type(ZIG_TOKEN_ERROR), location() {
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
