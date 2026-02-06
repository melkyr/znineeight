#include "compilation_unit.hpp"
#include "parser.hpp" // For Parser class definition
#include "name_collision_detector.hpp"
#include "signature_analyzer.hpp"
#include "type_checker.hpp"
#include "c89_feature_validator.hpp"
#include "lifetime_analyzer.hpp"
#include "null_pointer_analyzer.hpp"
#include "double_free_analyzer.hpp"
#include "type_system.hpp"
#include "c89_pattern_generator.hpp"
#include "utils.hpp"
#include "platform.hpp"
#include <new>       // For placement new
#include <cstdlib>   // For abort()

// Private helper to handle fatal errors
static void fatalError(const char* message) {
    plat_print_debug(message);
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
      errdefer_catalogue_(arena),
      options_(),
      pattern_generator_(NULL),
      test_patterns_(NULL),
      current_module_(NULL),
      is_test_mode_(false),
      validation_completed_(false),
      c89_validation_passed_(false) {

    current_module_ = interner_.intern("main");

    void* gen_mem = arena_.alloc(sizeof(C89PatternGenerator));
    pattern_generator_ = new (gen_mem) C89PatternGenerator(arena_);

    void* patterns_mem = arena_.alloc(sizeof(DynamicArray<const char*>));
    test_patterns_ = new (patterns_mem) DynamicArray<const char*>(arena_);
}

u32 CompilationUnit::addSource(const char* filename, const char* source) {
    u32 file_id = source_manager_.addFile(filename, source, plat_strlen(source));

    // Derive module name: "foo.zig" -> "foo"
    const char* slash = plat_strrchr(filename, '/');
    const char* backslash = plat_strrchr(filename, '\\');
    const char* last_sep = (slash > backslash) ? slash : backslash;
    const char* basename = last_sep ? last_sep + 1 : filename;

    // Remove extension
    char module_name_buf[256];
    size_t basename_len = plat_strlen(basename);
    if (basename_len >= sizeof(module_name_buf)) {
        basename_len = sizeof(module_name_buf) - 1;
    }
    plat_strncpy(module_name_buf, basename, basename_len);
    module_name_buf[basename_len] = '\0';

    char* dot = plat_strrchr(module_name_buf, '.');
    if (dot) *dot = '\0';

    if (module_name_buf[0] == '\0') {
        setCurrentModule("main");
    } else {
        setCurrentModule(module_name_buf);
    }

    return file_id;
}

Parser* CompilationUnit::createParser(u32 file_id) {
    TokenStream token_stream = token_supplier_.getTokensForFile(file_id);
    if (!token_stream.tokens) {
        fatalError("CompilationUnit::createParser: Failed to retrieve tokens for file_id.");
        return NULL; // Will not be reached
    }

    void* mem = arena_.alloc(sizeof(Parser));
    return new (mem) Parser(token_stream.tokens, token_stream.count, &arena_, &symbol_table_, &error_set_catalogue_, &generic_catalogue_, current_module_);
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

ErrDeferCatalogue& CompilationUnit::getErrDeferCatalogue() {
    return errdefer_catalogue_;
}

ArenaAllocator& CompilationUnit::getArena() {
    return arena_;
}

const char* CompilationUnit::getCurrentModule() const {
    return current_module_;
}

void CompilationUnit::setCurrentModule(const char* module_name) {
    current_module_ = interner_.intern(module_name);
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

void CompilationUnit::validateErrorHandlingRules() {
    char buffer[512];
    char* cur = buffer;
    size_t rem = sizeof(buffer);

    safe_append(cur, rem, "Found ");
    char num_buf[21];

    simple_itoa(try_expression_catalogue_.count(), num_buf, sizeof(num_buf));
    safe_append(cur, rem, num_buf);
    safe_append(cur, rem, " try expressions, ");

    simple_itoa(catch_expression_catalogue_.count(), num_buf, sizeof(num_buf));
    safe_append(cur, rem, num_buf);
    safe_append(cur, rem, " catch expressions, ");

    simple_itoa(orelse_expression_catalogue_.count(), num_buf, sizeof(num_buf));
    safe_append(cur, rem, num_buf);
    safe_append(cur, rem, " orelse expressions, ");

    simple_itoa(errdefer_catalogue_.count(), num_buf, sizeof(num_buf));
    safe_append(cur, rem, num_buf);
    safe_append(cur, rem, " errdefer statements");

    error_handler_.reportInfo(INFO_ERROR_HANDLING_VALIDATION, SourceLocation(), buffer, arena_);
}

void CompilationUnit::setTestMode(bool test_mode) {
    is_test_mode_ = test_mode;
}

bool CompilationUnit::performFullPipeline(u32 file_id) {
    Parser* parser = createParser(file_id);
    ASTNode* ast = parser->parse();
    if (!ast) return false;

    // Name Collision Detection
    NameCollisionDetector name_detector(*this);
    name_detector.check(ast);
    if (name_detector.hasCollisions()) {
        return false;
    }

    // Pass 0: Type Checking
    TypeChecker checker(*this);
    checker.check(ast);

    // Pass 0.5: Signature Analysis
    SignatureAnalyzer sig_analyzer(*this);
    sig_analyzer.analyze(ast);

    // Pass 1: C89 feature validation
    C89FeatureValidator validator(*this);
    bool success = validator.validate(ast);

    validation_completed_ = true;
    c89_validation_passed_ = success && !sig_analyzer.hasInvalidSignatures();

    if (!c89_validation_passed_) {
        return false;
    }

    // Pass 2+: Static Analyzers (if enabled)
    if (options_.enable_lifetime_analysis) {
        LifetimeAnalyzer analyzer(*this);
        analyzer.analyze(ast);
    }

    if (options_.enable_null_pointer_analysis) {
        NullPointerAnalyzer analyzer(*this);
        analyzer.analyze(ast);
    }

    if (options_.enable_double_free_analysis) {
        DoubleFreeAnalyzer analyzer(*this);
        analyzer.analyze(ast);
    }

    return true;
}

bool CompilationUnit::areErrorTypesEliminated() const {
    if (!validation_completed_) return false;

    // Conceptual elimination: they are eliminated from final C89 output via rejection.
    // If validation passed (c89_validation_passed_ is true), then NO error types should be present.
    // If validation failed, it means error types were detected and rejected.
    if (c89_validation_passed_) {
        return (error_function_catalogue_.count() == 0 &&
                error_set_catalogue_.count() == 0 &&
                try_expression_catalogue_.count() == 0 &&
                catch_expression_catalogue_.count() == 0 &&
                orelse_expression_catalogue_.count() == 0);
    }

    // Validation failed, which means the non-C89 error types were successfully rejected.
    return true;
}
