#include "compilation_unit.hpp"
#include "parser.hpp" // For Parser class definition
#include "call_resolution_validator.hpp"
#include "name_collision_detector.hpp"
#include "signature_analyzer.hpp"
#include "type_checker.hpp"
#include "c89_feature_validator.hpp"
#include "codegen.hpp"
#include "lifetime_analyzer.hpp"
#include "null_pointer_analyzer.hpp"
#include "double_free_analyzer.hpp"
#include "type_system.hpp"
#include "c89_pattern_generator.hpp"
#include "utils.hpp"
#include "platform.hpp"

#ifdef MEASURE_MEMORY
class PhaseMemoryTracker {
    struct PhaseStats {
        const char* phase_name;
        size_t arena_before;
        size_t arena_after;
        size_t ast_nodes;
        size_t types;
        size_t symbols;
        size_t catalogue_entries;
    };

    DynamicArray<PhaseStats> phases;
    CompilationUnit& unit;

public:
    PhaseMemoryTracker(CompilationUnit& u) : phases(u.getArena()), unit(u) {}

    void begin_phase(const char* name) {
        PhaseStats stats;
        stats.phase_name = name;
        stats.arena_before = unit.getArena().getOffset();
        // Count current objects
        stats.ast_nodes = 0;
        stats.types = 0;
        stats.symbols = 0;
        stats.catalogue_entries = 0;
        phases.append(stats);
    }

    void end_phase() {
        if (phases.length() > 0) {
            PhaseStats& last = phases[phases.length() - 1];
            last.arena_after = unit.getArena().getOffset();
            last.ast_nodes = MemoryTracker::ast_nodes;
            last.types = MemoryTracker::types;
            last.symbols = MemoryTracker::symbols;
            last.catalogue_entries = unit.getTotalCatalogueEntries();
        }
    }

    void print_report() {
        plat_print_info("\n=== PHASE MEMORY REPORT ===\n");
        char stat_buf[256];
        char num_buf_stat[32];

        simple_itoa((long)unit.getTypeInterner().getDeduplicationCount(), num_buf_stat, sizeof(num_buf_stat));
        plat_print_info("Total Type Deduplications: ");
        plat_print_info(num_buf_stat);
        plat_print_info("\n");

        for (size_t i = 0; i < phases.length(); i++) {
            PhaseStats& s = phases[i];
            size_t delta = s.arena_after - s.arena_before;

            char buffer[512];
            char* cur = buffer;
            size_t rem = sizeof(buffer);
            char num_buf[32];

            safe_append(cur, rem, "Phase: ");
            safe_append(cur, rem, s.phase_name);
            safe_append(cur, rem, "\n");

            safe_append(cur, rem, "  Arena delta: ");
            simple_itoa((long)delta, num_buf, sizeof(num_buf));
            safe_append(cur, rem, num_buf);
            safe_append(cur, rem, " bytes\n");

            safe_append(cur, rem, "  AST nodes: ");
            simple_itoa((long)s.ast_nodes, num_buf, sizeof(num_buf));
            safe_append(cur, rem, num_buf);
            safe_append(cur, rem, "\n");

            safe_append(cur, rem, "  Types: ");
            simple_itoa((long)s.types, num_buf, sizeof(num_buf));
            safe_append(cur, rem, num_buf);
            safe_append(cur, rem, "\n");

            safe_append(cur, rem, "  Symbols: ");
            simple_itoa((long)s.symbols, num_buf, sizeof(num_buf));
            safe_append(cur, rem, num_buf);
            safe_append(cur, rem, "\n");

            safe_append(cur, rem, "  Catalogue entries: ");
            simple_itoa((long)s.catalogue_entries, num_buf, sizeof(num_buf));
            safe_append(cur, rem, num_buf);
            safe_append(cur, rem, "\n");

            plat_print_info(buffer);
        }
        plat_print_info("===========================\n");
    }
};
#endif
#include <new>       // For placement new
#include <cstdlib>   // For abort()

// Private helper to handle fatal errors
static void fatalError(const char* message) {
    plat_print_debug(message);
    abort();
}

CompilationUnit::CompilationUnit(ArenaAllocator& arena, StringInterner& interner)
    : arena_(arena),
      token_arena_(1024 * 1024 * 16), // 16MB cap for tokens
      type_interner_(arena),
      interner_(interner),
      source_manager_(arena),
      symbol_table_(arena),
      error_handler_(source_manager_, arena),
      token_supplier_(source_manager_, interner_, token_arena_),
      error_set_catalogue_(arena),
      generic_catalogue_(arena),
      error_function_catalogue_(arena),
      try_expression_catalogue_(arena),
      catch_expression_catalogue_(arena),
      orelse_expression_catalogue_(arena),
      extraction_analysis_catalogue_(arena),
      errdefer_catalogue_(arena),
      indirect_call_catalogue_(arena),
      name_mangler_(arena, interner),
      call_site_table_(arena),
      options_(),
      current_module_(NULL),
      pattern_generator_(NULL),
      test_patterns_(NULL),
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
    return new (mem) Parser(token_stream.tokens, token_stream.count, &arena_, &symbol_table_, &error_set_catalogue_, &generic_catalogue_, &type_interner_, current_module_);
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

IndirectCallCatalogue& CompilationUnit::getIndirectCallCatalogue() {
    return indirect_call_catalogue_;
}

NameMangler& CompilationUnit::getNameMangler() {
    return name_mangler_;
}

CallSiteLookupTable& CompilationUnit::getCallSiteLookupTable() {
    return call_site_table_;
}

ArenaAllocator& CompilationUnit::getArena() {
    return arena_;
}

ArenaAllocator& CompilationUnit::getTokenArena() {
    return token_arena_;
}

TypeInterner& CompilationUnit::getTypeInterner() {
    return type_interner_;
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
            const char* name = interner_.intern(primitives[i]);
            Symbol sym = SymbolBuilder(arena_)
                .withName(name)
                .withMangledName(name) // Primitives use their own name as mangled name
                .ofType(SYMBOL_TYPE)
                .withType(t)
                .build();
            symbol_table_.insert(sym);
        }
    }

    // arena_alloc(size: usize) -> *void
    void* params_mem = arena_.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params = new (params_mem) DynamicArray<Type*>(arena_);
    params->append(get_g_type_usize());
    Type* ret_type = createPointerType(arena_, get_g_type_void(), false, &type_interner_);
    Type* fn_type = createFunctionType(arena_, params, ret_type);

    const char* alloc_name = interner_.intern("arena_alloc");
    Symbol sym_alloc = SymbolBuilder(arena_)
        .withName(alloc_name)
        .withMangledName(name_mangler_.mangleFunction(alloc_name, NULL, 0, current_module_))
        .ofType(SYMBOL_FUNCTION)
        .withType(fn_type)
        .build();
    symbol_table_.insert(sym_alloc);

    // arena_free(ptr: *void) -> void
    void* params_mem2 = arena_.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params2 = new (params_mem2) DynamicArray<Type*>(arena_);
    params2->append(createPointerType(arena_, get_g_type_void(), false, &type_interner_));
    Type* ret_type2 = get_g_type_void();
    Type* fn_type2 = createFunctionType(arena_, params2, ret_type2);

    const char* free_name = interner_.intern("arena_free");
    Symbol sym_free = SymbolBuilder(arena_)
        .withName(free_name)
        .withMangledName(name_mangler_.mangleFunction(free_name, NULL, 0, current_module_))
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

size_t CompilationUnit::getASTNodeCount() const {
#ifdef MEASURE_MEMORY
    return MemoryTracker::ast_nodes;
#else
    return 0;
#endif
}

size_t CompilationUnit::getTypeCount() const {
#ifdef MEASURE_MEMORY
    return MemoryTracker::types;
#else
    return 0;
#endif
}

size_t CompilationUnit::getTotalCatalogueEntries() const {
    size_t total = 0;
    total += error_set_catalogue_.count();
    total += generic_catalogue_.count();
    total += error_function_catalogue_.count();
    total += try_expression_catalogue_.count();
    total += catch_expression_catalogue_.count();
    total += orelse_expression_catalogue_.count();
    total += extraction_analysis_catalogue_.count();
    total += errdefer_catalogue_.count();
    total += indirect_call_catalogue_.count();
    return total;
}

bool CompilationUnit::generateCode(const char* output_path) {
    C89Emitter emitter(arena_, error_handler_);
    if (!emitter.open(output_path)) {
        error_handler_.report(ERR_INTERNAL_ERROR, SourceLocation(), "Failed to open output file for code generation");
        return false;
    }

    emitter.emitPrologue();

    // TODO: Implement full AST traversal and code generation
    emitter.emitComment("TODO: Implement full AST traversal and code generation");

    emitter.close();
    return true;
}

bool CompilationUnit::performFullPipeline(u32 file_id) {
#ifdef MEASURE_MEMORY
    PhaseMemoryTracker tracker(*this);
#endif

#ifdef MEASURE_MEMORY
    tracker.begin_phase("Parsing");
#endif
    Parser* parser = createParser(file_id);
    ASTNode* ast = parser->parse();
#ifdef MEASURE_MEMORY
    tracker.end_phase();
#endif

    // Reset token arena early to free memory!
    // After parsing, AST doesn't need the tokens anymore.
#ifdef MEASURE_MEMORY
    size_t token_mem = token_arena_.getOffset();
    char num_buf[32];
    simple_itoa((long)token_mem, num_buf, sizeof(num_buf));
    plat_print_info("Token arena before reset: ");
    plat_print_info(num_buf);
    plat_print_info(" bytes\n");
#endif

    token_arena_.reset();
    token_supplier_.reset();

#ifdef MEASURE_MEMORY
    plat_print_info("Token arena after reset: 0 bytes\n");
#endif
    if (!ast) return false;

    // Name Collision Detection
#ifdef MEASURE_MEMORY
    tracker.begin_phase("Name Collision Detection");
#endif
    NameCollisionDetector name_detector(*this);
    name_detector.check(ast);
#ifdef MEASURE_MEMORY
    tracker.end_phase();
#endif
    if (name_detector.hasCollisions()) {
        return false;
    }

    // Pass 0: Type Checking
#ifdef MEASURE_MEMORY
    tracker.begin_phase("Type Checking");
#endif
    TypeChecker checker(*this);
    checker.check(ast);
#ifdef MEASURE_MEMORY
    tracker.end_phase();
#endif

#ifdef DEBUG
    plat_print_debug("CompilationUnit: DEBUG is defined. Calling CallResolutionValidator...\n");
    // Task 168: Run call resolution validation
    if (!CallResolutionValidator::validate(*this, ast)) {
        error_handler_.report(ERR_INTERNAL_ERROR, ast->loc, "Call resolution validation failed");
        return false;
    }
#else
    plat_print_info("CompilationUnit: DEBUG is NOT defined. Skipping CallResolutionValidator.\n");
#endif

    // Pass 0.5: Signature Analysis
#ifdef MEASURE_MEMORY
    tracker.begin_phase("Signature Analysis");
#endif
    SignatureAnalyzer sig_analyzer(*this);
    sig_analyzer.analyze(ast);
#ifdef MEASURE_MEMORY
    tracker.end_phase();
#endif

    // Pass 1: C89 feature validation
#ifdef MEASURE_MEMORY
    tracker.begin_phase("C89 Validation");
#endif
    C89FeatureValidator validator(*this);
    bool success = validator.validate(ast);
#ifdef MEASURE_MEMORY
    tracker.end_phase();
#endif

    validation_completed_ = true;
    c89_validation_passed_ = success && !sig_analyzer.hasInvalidSignatures();

    if (!c89_validation_passed_) {
#ifdef MEASURE_MEMORY
        tracker.print_report();
        MemoryTracker::reset_counts();
#endif
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

    // Task 163: Report unresolved call sites
    if (call_site_table_.getUnresolvedCount() > 0) {
        call_site_table_.printUnresolved();
    }

#ifdef MEASURE_MEMORY
    tracker.print_report();
    MemoryTracker::reset_counts();
#endif
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
