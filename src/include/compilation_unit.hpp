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
#include "error_function_catalogue.hpp"
#include "generic_catalogue.hpp"

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

// Forward-declare Parser to avoid including parser.hpp in this header.
class Parser;

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
    ErrorFunctionCatalogue& getErrorFunctionCatalogue();
    GenericCatalogue& getGenericCatalogue();
    ArenaAllocator& getArena();

    CompilationOptions& getOptions();
    const CompilationOptions& getOptions() const;
    void setOptions(const CompilationOptions& options);

    /**
     * @brief Injects mandatory runtime symbols (like arena_alloc, arena_free) into the global scope.
     */
    void injectRuntimeSymbols();

private:
    ArenaAllocator& arena_;
    StringInterner& interner_;
    SourceManager source_manager_;
    SymbolTable symbol_table_;
    ErrorHandler error_handler_;
    TokenSupplier token_supplier_;
    ErrorSetCatalogue error_set_catalogue_;
    ErrorFunctionCatalogue error_function_catalogue_;
    GenericCatalogue generic_catalogue_;
    CompilationOptions options_;
};

#endif // COMPILATION_UNIT_HPP
