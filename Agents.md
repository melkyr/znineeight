# RetroZig Compiler - AI Agent Guidelines

## Overview

This document outlines the development methodology, constraints, and communication protocols for AI agents working on the RetroZig compiler project.

## Current Status: Milestone 4 (Task 166)

We are implementing the bootstrap type system and semantic analysis with strict C89 compatibility constraints.

### Key Architectural Components

1. **Multi-Phase Compilation Pipeline** (`CompilationUnit::performFullPipeline`)
2. **Feature Detection & Rejection** (`C89FeatureValidator`)
3. **Comprehensive Cataloguing** (9 specialized catalogues)
4. **Pass-Based Semantic Analysis** (Type checking → Validation → Lifetime → Null pointer → Double free)

### Memory Constraints

- **Target**: < 16MB peak usage for compiling zig1 (self-hosted compiler)
- **Current estimate**: ~2.3MB data + overhead
- **Critical path**: Must handle 10,000 lines of zig1 source code

## Memory Management Protocol (Updated)

### Persistent Instrumentation
The codebase now contains persistent memory instrumentation guarded by `#ifdef MEASURE_MEMORY`. This instrumentation MUST remain in the codebase to facilitate ongoing memory analysis and regression testing.

### Phase-Aware Analysis Required

All memory-related work must track usage across compilation phases:

1. **Lexing & Parsing**: AST node creation, string interning
2. **Type Checking**: Type objects, symbol table expansion
3. **C89 Validation**: Catalogue population
4. **Semantic Analysis**: Analysis state tracking
5. **Code Generation**: Output buffers

### Catalogue Memory Overhead

The compiler maintains 9 catalogues for feature tracking. Memory impact:
- ErrorSetCatalogue: Error set definitions and merges
- GenericCatalogue: Generic function instantiations
- ErrorFunctionCatalogue: Error-returning functions
- Try/Catch/Orelse catalogues: Error handling patterns
- ExtractionAnalysisCatalogue: C89 translation strategies
- ErrDeferCatalogue: Errdefer statements
- IndirectCallCatalogue: Function pointer calls

**Guideline**: When implementing catalogue features, estimate memory per entry (≈ 32-64 bytes).

### Measurement Commands

```bash
# Build with memory instrumentation
g++ -std=c++98 -DMEASURE_MEMORY -I./src/include src/bootstrap/*.cpp -o build/zig0_instrumented

# Run phase-aware analysis
./scripts/memory/analyze_compiler_memory.sh

# Quick memory check
valgrind --tool=massif --stacks=yes ./build/zig0_instrumented full_pipeline test/compiler_subset.zig

# Catalogue-specific analysis
# (Future work) DEBUG_CATALOGUES=1 ./zig0 full_pipeline input.zig
```

### Optimization Priority List

When memory exceeds thresholds, optimize in this order:

1. **Catalogue entries** (largest potential savings)
2. **AST node allocations** (biggest baseline consumer)
3. **Type object sharing** (reduce duplication)
4. **String interning** (hash table optimization)
5. **Phase memory reuse** (arena reset between phases)

### Memory Budget Per Phase

| Phase | Budget | Current | Status |
|-------|--------|---------|--------|
| Lexing | 512KB | ~300KB | ✅ |
| Parsing | 1MB | ~700KB | ✅ |
| Type Checking | 2MB | ~1.2MB | ✅ |
| Catalogues | 1MB | ~800KB | ⚠️ |
| Analysis | 1MB | ~600KB | ✅ |
| **Total** | **5.5MB** | **~3.6MB** | **✅** |

*Note: 5.5MB target leaves 10.5MB headroom for zig1 compilation*

## Implementation Guidelines

### For New Features

1. **Memory Estimate First**: Calculate expected memory impact before coding
2. **Phase Placement**: Place features in appropriate compilation phase
3. **Catalogue Strategy**: Decide if feature needs cataloguing or can be rejected immediately
4. **Testing**: Include memory assertions in unit tests

### For Memory Optimization

1. **Profile Before Optimizing**: Use `MEASURE_MEMORY` to identify hotspots
2. **Focus on Catalogue Growth**: Largest potential for savings
3. **Consider Lazy Allocation**: Only allocate when feature is actually used
4. **Shared Structures**: Reuse common objects (types, error sets)

### Critical Files for Memory Analysis

- `src/include/compilation_unit.hpp` - Pipeline orchestration
- `src/include/type_checker.hpp` - Type system memory
- `src/include/c89_feature_validator.hpp` - Rejection framework
- `src/include/memory.hpp` - Arena allocator
- All catalogue header files

## Communication Protocol

### When Reporting Memory Issues

Include:
1. Phase where issue occurs
2. Catalogue growth patterns
3. Arena fragmentation percentage
4. Comparison to budget thresholds

### When Implementing Memory Optimizations

Document:
1. Before/after memory measurements
2. Impact on compilation speed
3. Any functional trade-offs
4. Test coverage for edge cases

## Testing Requirements

All memory-related changes require:

1. **Unit tests** with memory assertions
2. **Integration test** with compiler subset
3. **Valgrind clean** (no leaks)
4. **Performance regression check** (< 10% slowdown)

## Emergency Procedures

If memory usage exceeds 8MB (50% of budget):

1. Immediately pause feature development
2. Run comprehensive memory analysis
3. Identify top 3 memory consumers
4. Implement targeted optimizations
5. Verify back under 6MB before resuming

## Phase-Specific Guidelines

### Parsing Phase
- AST nodes: 28 bytes each, aim for < 5 nodes per line of code
- String interning: Track duplication ratio (target < 30%)

### Type Checking Phase
- Type objects: Share common primitives (i32, i64, etc.)
- Symbol table: Use efficient hash table resizing

### Validation Phase
- Catalogues: Lazy allocation, prune rejected entries
- Error messages: Reuse string buffers

### Analysis Phase
- State tracking: Use bit flags over boolean arrays
- Control flow: Conservative merging to avoid state explosion

## Tools and Scripts

Available in `scripts/memory/`:
- `analyze_compiler_memory.sh` - Comprehensive analysis
- `phase_tracker.py` - Phase-by-phase breakdown  (Planned)
- `catalogue_analyzer.py` - Catalogue memory impact (Planned)
- `budget_calculator.py` - Theoretical maximums (Planned)

## Success Criteria for Milestone 4

1. Compile 1000-line test program in < 4MB
2. Catalogue memory < 1MB for typical programs
3. No memory leaks in full pipeline
4. Ready for zig1 compilation (estimated 10K lines)

---

*Last updated: Task 166 - Bootstrap Type System & Semantic Analysis*
