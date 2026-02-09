#!/bin/bash
set -e

echo "=== Compiler Memory Analysis ==="
echo "Date: $(date)"
echo ""

# Build with instrumentation
echo "1. Building instrumented compiler..."
mkdir -p build
g++ -std=c++98 -g -DMEASURE_MEMORY -DDEBUG \
    -I./src/include src/bootstrap/*.cpp -o build/zig0_instrumented 2>&1 | tee build.log

if [ $? -ne 0 ]; then
    echo "Build failed"
    exit 1
fi

# Create test directory
mkdir -p test/memory_analysis

# Test 1: Simple program baseline
echo -e "\n2. Testing simple program..."
valgrind --tool=massif --massif-out-file=test/memory_analysis/massif_simple.out \
    --stacks=yes --time-unit=i \
    ./build/zig0_instrumented full_pipeline test/simple.zig > test/memory_analysis/output_simple.log 2>&1
ms_print test/memory_analysis/massif_simple.out > test/memory_analysis/report_simple.txt

# Test 2: Compiler subset (main test)
echo -e "\n3. Testing compiler subset..."
valgrind --tool=massif --massif-out-file=test/memory_analysis/massif_compiler.out \
    --stacks=yes --time-unit=i --detailed-freq=5 \
    ./build/zig0_instrumented full_pipeline test/compiler_subset.zig > test/memory_analysis/output_compiler.log 2>&1
ms_print test/memory_analysis/massif_compiler.out > test/memory_analysis/report_compiler.txt

# Test 3: With rejection framework active
echo -e "\n4. Testing with non-C89 features..."
valgrind --tool=massif --massif-out-file=test/memory_analysis/massif_reject.out \
    --stacks=yes \
    ./build/zig0_instrumented full_pipeline test/with_errors.zig > test/memory_analysis/output_reject.log 2>&1
ms_print test/memory_analysis/massif_reject.out > test/memory_analysis/report_reject.txt

# Extract key metrics
echo -e "\n=== KEY METRICS ==="

echo "Peak heap usage (Compiler Subset):"
grep "mem_heap_B=" test/memory_analysis/massif_compiler.out | tail -1 | cut -d= -f2

echo -e "\nPhase Memory Report (Compiler Subset):"
grep -A 40 "=== PHASE MEMORY REPORT ===" test/memory_analysis/output_compiler.log

echo -e "\n=== ANALYSIS COMPLETE ==="
echo "Reports available in test/memory_analysis/"
