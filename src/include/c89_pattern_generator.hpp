#ifndef C89_PATTERN_GENERATOR_HPP
#define C89_PATTERN_GENERATOR_HPP

#include "common.hpp"
#include "memory.hpp"
#include "error_function_catalogue.hpp"
#include "type_system.hpp"

/**
 * @class C89PatternGenerator
 * @brief Generates C89-compatible error return patterns for functions.
 */
class C89PatternGenerator {
public:
    /**
     * @brief Constructs a new C89PatternGenerator.
     * @param arena The ArenaAllocator to use for memory allocations.
     */
    C89PatternGenerator(ArenaAllocator& arena);

    /**
     * @brief Generates a C89 pattern for a given error-returning function.
     * @param info Metadata about the error-returning function.
     * @return A C string containing the generated C89 code snippet.
     */
    const char* generatePattern(const ErrorFunctionInfo& info);

private:
    /**
     * @brief Generates a struct-return pattern (Strategy: EXTRACTION_STACK).
     */
    const char* generateStructReturn(const ErrorFunctionInfo& info);

    /**
     * @brief Generates an out-parameter pattern (Strategy: EXTRACTION_OUT_PARAM).
     */
    const char* generateOutParameter(const ErrorFunctionInfo& info);

    /**
     * @brief Generates an arena-allocation pattern (Strategy: EXTRACTION_ARENA).
     */
    const char* generateArenaAllocation(const ErrorFunctionInfo& info);

    /**
     * @brief Converts a Zig Type to its C89 name.
     */
    void typeToC89(Type* type, char* buffer, size_t buffer_size);

    /**
     * @brief Gets a unique suffix for an errorable type based on the payload.
     */
    void getTypeSuffix(Type* type, char* buffer, size_t buffer_size);

    ArenaAllocator& arena_;
};

#endif // C89_PATTERN_GENERATOR_HPP
