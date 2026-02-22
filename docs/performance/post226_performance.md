# RetroZig Compiler Performance Report (Post-Task 226)

This report details the CPU and memory usage of the RetroZig Stage 0 compiler (C++98) following the revision of Task 226.

## 1. Summary
The compiler remains highly efficient, with small programs consuming less than 50KB of arena memory and completing in under 10ms. Scaling tests demonstrate that memory usage grows linearly with the number of declarations and statements. The compiler comfortably stays within the 16MB target for files up to approximately 2,000-3,000 functions.

## 2. Memory Usage Breakdown

### 2.1 Representative Workloads
The following measurements were taken using the internal `MEASURE_MEMORY` instrumentation.

| Workload | Tokens | Parsing | Type Checking | Total Arena |
| :--- | :--- | :--- | :--- | :--- |
| hello (3 files) | ~2.6 KB | ~2.0 KB | ~5.8 KB | ~11.0 KB |
| heapsort (1 file) | ~44 KB | ~23 KB | ~7 KB | ~33 KB |
| 1000 functions | ~2.8 MB | ~1.8 MB | ~0.8 MB | ~2.8 MB |

*Note: "Total Arena" reflects the sum of deltas across all phases. Tokens are managed in a separate transient arena.*

### 2.2 Phase-Based Distribution
- **Parsing (60-70% of AST Arena)**: The largest consumer, as it creates the initial AST nodes and symbol table entries.
- **Type Checking (20-30% of AST Arena)**: Resolves types and adds more semantic metadata.
- **Name Collision Detection / C89 Validation (< 5%)**: Minimal overhead.
- **Token Arena (Transient)**: Consumes significant memory during lexing and parsing but is reset immediately after the AST is built, freeing it for subsequent phases.

### 2.3 Object Sizes (32-bit assumptions)
- `ASTNode`: 32 bytes
- `Token`: 32 bytes
- `Type`: 64-128 bytes (depending on kind)

## 3. CPU Performance
CPU usage is negligible for small programs.

| Scale | User Time | System Time | Real Time |
| :--- | :--- | :--- | :--- |
| 1000 functions | 41ms | 9ms | 51ms |
| heapsort | < 10ms | < 10ms | < 10ms |

## 4. Scaling Limits and Bottlenecks

### 4.1 The 16MB Limit
Workloads exceeding ~5,000 functions in a single compilation unit currently hit the 16MB memory cap. The primary bottleneck is the **Token Arena**.

**Cause of Failure at 5k Functions:**
- The `TokenSupplier` currently stores tokens twice during initialization: once in a resizable `DynamicArray` and once in a "stable" block.
- For 500,000 tokens (approximate size of a 5k function file):
  - `DynamicArray` (with 2^19 capacity): ~16 MB (32 bytes * 524288)
  - Stable block: ~16 MB (32 bytes * 500000)
  - Combined peak usage during tokenization exceeds the 16MB cap.

## 5. Performance Recommendations

### 5.1 Memory Optimizations
1. **Optimize Token Storage**:
   - Tokenize directly into a stable buffer if the file size allows for a good estimate of token count.
   - Alternatively, use a "chunked" storage for tokens to avoid the doubling capacity overhead of `DynamicArray`.
2. **AST Node Compactness**:
   - Continue using out-of-line storage for large AST structures to keep the base `ASTNode` size at 32 bytes.
3. **Lazy Catalogue Allocation**:
   - Ensure catalogues are only allocated if the corresponding features (e.g., error unions) are actually used in a module.

### 5.2 CPU Optimizations
- Performance is currently more than sufficient for a bootstrap compiler. No major CPU bottlenecks were identified in the current workload.

## 6. Conclusion
The compiler's architecture is sound and adheres well to the target platform constraints for typical source files. Large-scale modular programs should be compiled in smaller chunks if they approach the 5,000-function threshold, or the token management should be further optimized.
