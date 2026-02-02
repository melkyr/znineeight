#include "compilation_unit.hpp"
#include "parser.hpp" // For Parser class definition
#include "type_system.hpp"
#include "c89_pattern_generator.hpp"
#include <cstring>   // For strlen
#include <new>       // For placement new
#include <cstdlib>   // For abort()

#if defined(_WIN32)
#include <windows.h> // For OutputDebugStringA
#endif

// Private helper to handle fatal errors
static void fatalError(const char* message) {
#if defined(_WIN32)
    OutputDebugStringA(message);
#else
    // On other platforms, no output, just abort.
#endif
    abort();
}

CompilationUnit::CompilationUnit(ArenaAllocator& arena, StringInterner& interner)
    : arena_(arena),
      interner_(interner),
      source_manager_(arena),
      symbol_table_(arena),
      error_handler_(source_manager_, arena),
      token_supplier_(source_manager_, interner_, arena),
      error_set_catalogue_(arena),
      generic_catalogue_(arena),
      error_function_catalogue_(arena),
      try_expression_catalogue_(arena),
      catch_expression_catalogue_(arena),
      orelse_expression_catalogue_(arena),
      extraction_analysis_catalogue_(arena),
      is_test_mode_(false) {

    void* gen_mem = arena_.alloc(sizeof(C89PatternGenerator));
    pattern_generator_ = new (gen_mem) C89PatternGenerator(arena_);

    void* patterns_mem = arena_.alloc(sizeof(DynamicArray<const char*>));
    test_patterns_ = new (patterns_mem) DynamicArray<const char*>(arena_);
}

u32 CompilationUnit::addSource(const char* filename, const char* source) {
    return source_manager_.addFile(filename, source, strlen(source));
}

Parser* CompilationUnit::createParser(u32 file_id) {
    TokenStream token_stream = token_supplier_.getTokensForFile(file_id);
    if (!token_stream.tokens) {
        fatalError("CompilationUnit::createParser: Failed to retrieve tokens for file_id.");
        return NULL; // Will not be reached
    }

    void* mem = arena_.alloc(sizeof(Parser));
    return new (mem) Parser(token_stream.tokens, token_stream.count, &arena_, &symbol_table_, &error_set_catalogue_);
}

/**
 * @brief Returns the symbol table for this compilation unit.
 * @return A reference to the SymbolTable.
 */
SymbolTable& CompilationUnit::getSymbolTable() {
    return symbol_table_;
}

ErrorHandler& CompilationUnit::getErrorHandler() {
    return error_handler_;
}

const ErrorHandler& CompilationUnit::getErrorHandler() const {
    return error_handler_;
}

SourceManager& CompilationUnit::getSourceManager() {
    return source_manager_;
}

ErrorSetCatalogue& CompilationUnit::getErrorSetCatalogue() {
    return error_set_catalogue_;
}

GenericCatalogue& CompilationUnit::getGenericCatalogue() {
    return generic_catalogue_;
}

ErrorFunctionCatalogue& CompilationUnit::getErrorFunctionCatalogue() {
    return error_function_catalogue_;
}

TryExpressionCatalogue& CompilationUnit::getTryExpressionCatalogue() {
    return try_expression_catalogue_;
}

CatchExpressionCatalogue& CompilationUnit::getCatchExpressionCatalogue() {
    return catch_expression_catalogue_;
}

OrelseExpressionCatalogue& CompilationUnit::getOrelseExpressionCatalogue() {
    return orelse_expression_catalogue_;
}

ExtractionAnalysisCatalogue& CompilationUnit::getExtractionAnalysisCatalogue() {
    return extraction_analysis_catalogue_;
}

ArenaAllocator& CompilationUnit::getArena() {
    return arena_;
}

CompilationOptions& CompilationUnit::getOptions() {
    return options_;
}

const CompilationOptions& CompilationUnit::getOptions() const {
    return options_;
}

void CompilationUnit::setOptions(const CompilationOptions& options) {
    options_ = options;
}

void CompilationUnit::injectRuntimeSymbols() {
    // Inject primitive types as SYMBOL_TYPE
    const char* primitives[] = {
        "void", "bool", "i8", "i16", "i32", "i64",
        "u8", "u16", "u32", "u64", "isize", "usize",
        "f32", "f64"
    };
    for (size_t i = 0; i < sizeof(primitives) / sizeof(primitives[0]); ++i) {
        Type* t = resolvePrimitiveTypeName(primitives[i]);
        if (t) {
            Symbol sym = SymbolBuilder(arena_)
                .withName(interner_.intern(primitives[i]))
                .ofType(SYMBOL_TYPE)
                .withType(t)
                .build();
            symbol_table_.insert(sym);
        }
    }

    // arena_alloc(size: u32) -> *u8
    void* params_mem = arena_.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params = new (params_mem) DynamicArray<Type*>(arena_);
    params->append(get_g_type_u32());
    Type* ret_type = createPointerType(arena_, get_g_type_u8(), false);
    Type* fn_type = createFunctionType(arena_, params, ret_type);

    Symbol sym_alloc = SymbolBuilder(arena_)
        .withName(interner_.intern("arena_alloc"))
        .ofType(SYMBOL_FUNCTION)
        .withType(fn_type)
        .build();
    symbol_table_.insert(sym_alloc);

    // arena_free(ptr: *u8) -> void
    void* params_mem2 = arena_.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params2 = new (params_mem2) DynamicArray<Type*>(arena_);
    params2->append(createPointerType(arena_, get_g_type_u8(), false));
    Type* ret_type2 = get_g_type_void();
    Type* fn_type2 = createFunctionType(arena_, params2, ret_type2);

    Symbol sym_free = SymbolBuilder(arena_)
        .withName(interner_.intern("arena_free"))
        .ofType(SYMBOL_FUNCTION)
        .withType(fn_type2)
        .build();
    symbol_table_.insert(sym_free);
}

void CompilationUnit::testErrorPatternGeneration() {
    if (!is_test_mode_) return;

    for (size_t i = 0; i < error_function_catalogue_.getFunctions()->length(); ++i) {
        const ErrorFunctionInfo& info = (*error_function_catalogue_.getFunctions())[i];
        const char* pattern = pattern_generator_->generatePattern(info);
        test_patterns_->append(pattern);
    }
}

int CompilationUnit::getGeneratedPatternCount() const {
    return (int)test_patterns_->length();
}

const char* CompilationUnit::getGeneratedPattern(int index) const {
    if (index < 0 || (size_t)index >= test_patterns_->length()) return NULL;
    return (*test_patterns_)[index];
}

void CompilationUnit::setTestMode(bool test_mode) {
    is_test_mode_ = test_mode;
}
