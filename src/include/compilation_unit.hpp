#ifndef COMPILATION_UNIT_HPP
#define COMPILATION_UNIT_HPP

#include "common.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"
#include "symbol_table.hpp"
#include "error_handler.hpp"
#include "token_supplier.hpp"
#include "error_set_catalogue.hpp"
#include "generic_catalogue.hpp"
#include "error_function_catalogue.hpp"
#include "try_expression_catalogue.hpp"
#include "catch_expression_catalogue.hpp"
#include "orelse_expression_catalogue.hpp"
#include "extraction_analysis_catalogue.hpp"
#include "errdefer_catalogue.hpp"
#include "indirect_call_catalogue.hpp"
#include "name_mangler.hpp"
#include "call_site_lookup_table.hpp"

/**
 * @struct CompilationOptions
 * @brief Controls the behavior of the compilation pipeline.
 */
struct CompilationOptions {
    bool enable_double_free_analysis;
    bool enable_null_pointer_analysis;
    bool enable_lifetime_analysis;

    CompilationOptions()
        : enable_double_free_analysis(false),
          enable_null_pointer_analysis(false),
          enable_lifetime_analysis(false) {}
};

// Forward-declare to avoid circular dependencies.
class Parser;
class C89PatternGenerator;

class CompilationUnit {
public:
    CompilationUnit(ArenaAllocator& arena, StringInterner& interner);

    u32 addSource(const char* filename, const char* source);

    Parser* createParser(u32 file_id);

    SymbolTable& getSymbolTable();
    ErrorHandler& getErrorHandler();
    const ErrorHandler& getErrorHandler() const;
    SourceManager& getSourceManager();
    ErrorSetCatalogue& getErrorSetCatalogue();
    GenericCatalogue& getGenericCatalogue();
    ErrorFunctionCatalogue& getErrorFunctionCatalogue();
    TryExpressionCatalogue& getTryExpressionCatalogue();
    CatchExpressionCatalogue& getCatchExpressionCatalogue();
    OrelseExpressionCatalogue& getOrelseExpressionCatalogue();
    ExtractionAnalysisCatalogue& getExtractionAnalysisCatalogue();
    ErrDeferCatalogue& getErrDeferCatalogue();
    IndirectCallCatalogue& getIndirectCallCatalogue();
    NameMangler& getNameMangler();
    CallSiteLookupTable& getCallSiteLookupTable();
    TypeInterner& getTypeInterner();
    ArenaAllocator& getArena();
    ArenaAllocator& getTokenArena();

    const char* getCurrentModule() const;
    void setCurrentModule(const char* module_name);

    CompilationOptions& getOptions();
    const CompilationOptions& getOptions() const;
    void setOptions(const CompilationOptions& options);

    /**
     * @brief Injects mandatory runtime symbols (like arena_alloc, arena_free) into the global scope.
     */
    void injectRuntimeSymbols();

    /**
     * @brief Generates C89 return patterns for all error-returning functions in the catalogue.
     *        Only used for Task 148 validation.
     */
    void testErrorPatternGeneration();

    /**
     * @brief Returns the number of generated test patterns.
     */
    int getGeneratedPatternCount() const;

    /**
     * @brief Returns a specific generated test pattern by index.
     */
    const char* getGeneratedPattern(int index) const;

    /**
     * @brief Executes the full compilation pipeline for a single file.
     * @param file_id The ID of the source file to compile.
     * @return True if the pipeline finished successfully (though it may have found errors).
     */
    bool performFullPipeline(u32 file_id);

    /**
     * @brief Generates C89 code from the AST and writes it to the specified file.
     * @param output_path The path to the output .c file.
     * @return True if code generation was successful.
     */
    bool generateCode(const char* output_path);

    /**
     * @brief Checks if error types have been effectively eliminated from the final output
     *        (by ensuring they were all rejected by the validator).
     */
    bool areErrorTypesEliminated() const;

    /**
     * @brief Performs validation of error handling patterns and reports summary info.
     */
    void validateErrorHandlingRules();

    /**
     * @brief Sets whether the unit is in test mode (enabling pattern generation).
     */
    void setTestMode(bool test_mode);

    // Memory tracking helpers
    size_t getASTNodeCount() const;
    size_t getTypeCount() const;
    size_t getTotalCatalogueEntries() const;

private:
    ArenaAllocator& arena_;
    ArenaAllocator token_arena_;
    TypeInterner type_interner_;
    StringInterner& interner_;
    SourceManager source_manager_;
    SymbolTable symbol_table_;
    ErrorHandler error_handler_;
    TokenSupplier token_supplier_;
    ErrorSetCatalogue error_set_catalogue_;
    GenericCatalogue generic_catalogue_;
    ErrorFunctionCatalogue error_function_catalogue_;
    TryExpressionCatalogue try_expression_catalogue_;
    CatchExpressionCatalogue catch_expression_catalogue_;
    OrelseExpressionCatalogue orelse_expression_catalogue_;
    ExtractionAnalysisCatalogue extraction_analysis_catalogue_;
    ErrDeferCatalogue errdefer_catalogue_;
    IndirectCallCatalogue indirect_call_catalogue_;
    NameMangler name_mangler_;
    CallSiteLookupTable call_site_table_;
    CompilationOptions options_;
    const char* current_module_;

    C89PatternGenerator* pattern_generator_;
    DynamicArray<const char*>* test_patterns_;
    ASTNode* last_ast_;
    bool is_test_mode_;
    bool validation_completed_;
    bool c89_validation_passed_;
};

#endif // COMPILATION_UNIT_HPP
