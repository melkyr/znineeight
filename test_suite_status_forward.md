# Z98 Test Suite Status Report

## Summary

| Metric | 32-bit Value | 64-bit Value |
|--------|--------------|--------------|
| Total Test Batches | 77 | 77 |
| Passed Batches | 49 | 50 |
| Failed Batches | 28 | 27 |
| Total Pass Rate | 63.6% | 64.9% |

---

## Detailed Breakdown of Failures

### Batch 3: Type Checker
- **Failing Test:** `TEST_FUNC(TypeCheckerIntegerLiteralType)`
- **Reason:** Integer literal kind mismatch on 32-bit. The test expects `2147483648` to be treated as `i64`, but it may be getting truncated or misclassified in the 32-bit environment compared to 64-bit where it passed.

### Batch 10: Name Mangling
- **Status:** **PARTIALLY PASSED** (Deterministic naming implemented)
- **Reason:** Legacy tests updated to expect `zF_0_foo` etc. in Test Mode. Some hash-based tests still need adjustment or removal.

### Batch 11: Name Mangling (Milestone 4)
- **Status:** **PASSED** (Test Mode enabled)
- **Reason:** Successfully updated `test_NameMangler_Milestone4Types` and `test_recursive_calls` to align with the counter-based deterministic naming.

### Batch 12: Emission Verification
- **Status:** **PASSED** (Test Mode enabled)
- **Reason:** Systematic update of emission strings in `function_decl_tests.cpp`, `variable_decl_tests.cpp`, and `function_call_tests.cpp` to use the `z<Kind>_0_` prefix and counters.

### Batch 13 & 14: Function Emission
- **Failing Tests:** `test_FunctionEmission_...`
- **Reason:** Mismatch in function names due to `zF_` prefixing.

### Batch 15 & 16: Variable Emission
- **Failing Tests:** `test_VariableEmission_...`
- **Reason:** Mismatch in variable names due to `zV_` prefixing.

### Batch 18: Function/Variable Refactoring
- **Failing Tests:** Various emission checks in `tests/integration/emission_verification_tests.cpp`
- **Reason:** Hardcoded expectation strings lack the new name mangling prefixes.

### Batch 26 & 27: Codegen Verification
- **Failing Tests:** Many small snippet verification tests.
- **Reason:** Expectation strings are outdated and do not account for the new symbol mangling and `z`-prefixed type names.

### Batch 30: Multi-Module Codegen
- **Failing Tests:** `test_MultiModule_Codegen`
- **Reason:** Mismatch in module-level symbol emission.

### Batch 31: CBackend Multi-File
- **Failing Test:** `test_CBackend_MultiFile`
- **Reason:** The compiler migrated to separate compilation. The test looks for internal STU-style includes (`main_module.c`) which no longer exist. Also reports "Missing generated files".

### Batch 32: End-to-End Integration
- **Failing Tests:** `test_EndToEnd_HelloWorld`, `test_EndToEnd_PrimeNumbers`
- **Reason:** Compilation/Linkage failure of generated C code. Undefined reference to mangled symbols (e.g., `zF_44e31f_sayHello`) because the test doesn't link all generated module object files.

### Batch 36: Variable Mangling
- **Failing Test:** `test_VariableEmission_PointerToPointer`
- **Reason:** Mismatch in `pp` variable name due to `zV_` prefix.

### Batch 39, 41, 52: Real Emission Verification
- **Failing Tests:** `test_Task9_8_ImplicitReturnErrorVoid`, etc.
- **Reason:** Prefix mismatch in function signatures (`zF_`) and return structure initialization strings.

### Batch 45: Error Handling
- **Failing Tests:** Tests checking for `fallible()` call emission.
- **Reason:** Mismatch in how the call is emitted compared to the expected string (mangled names).

### Batch 47: Optional Types
- **Failing Tests:** `Test OptionalFunction`, `Test OptionalStruct`
- **Reason:** Logic or emission mismatches in how optional payload types are handled or wrapped.

### Batch 48: Tuple Support
- **Failing Tests:** Mismatches in tuple type emission or layout.

### Batch 58, 61: Control Flow Emission
- **Failing Tests:** Various tests for `if`, `while`, and `switch` emission.
- **Reason:** Mismatch in function names (`zF_`) and runtime function calls (`zF_d071e5_cleanup`).

### Batch 65: Tagged Union Emission
- **Failing Tests:** `test_TaggedUnionEmission_Return`, `test_TaggedUnionEmission_Param`
- **Reason:** Mismatch in signature emission strings (missing `zF_` prefix).

### Batch 66: Header Verification
- **Failing Test:** `test_HeaderEmission_RecursiveStruct`
- **Reason:** Looking for `struct Node` instead of mangled `struct zS_d071e5_Node`.

### Batch 67: Tagged Union Variables
- **Failing Tests:** `test_TaggedUnionEmission_Global`, `test_TaggedUnionEmission_Local`
- **Reason:** Mismatch in variable names (`zV_`) and tag enum names.

### Batch 69: Tagged Union Layout
- **Failing Test:** `test_TaggedUnionVerification_Layout`
- **Reason:** Mismatch in internal tag field name/type in the generated header.

### Batch 71: Symbol Table Mapping
- **Failing Test:** `test_SymbolMapping`
- **Reason:** Global symbol names in the emitter output now includeKind prefixes.

### Batch 72: Switch Emission
- **Failing Tests:** `test_SwitchEmission_Simple`, `test_SwitchEmission_Expression`
- **Reason:** Mismatch in function names (`zF_`).

---

## Progress Report (Implementing Test Mode)

To resolve the widespread emission mismatches caused by the new name mangling scheme and the transition to separate compilation, a **Test Mode** architecture has been implemented.

### Test Mode Implementation
- **Flag**: `--test-mode` (Sets `CompilationUnit::is_test_mode_`).
- **Naming Scheme**: `z<Kind>_<Counter>_<Name>`.
    - `F`: Function
    - `V`: Variable
    - `S`: Struct / Tagged Union
    - `E`: Enum
    - `U`: Union (bare)
- **Determinism**: A global counter in `CompilationUnit` ensures names are predictable and independent of file hashes or environment paths.
- **Internal Identifiers**: `Arena`, `__bootstrap_*`, etc., continue to bypass mangling for runtime compatibility.

### Systematic Update Process
The remaining failing batches (13–18, 26–27, 39, 41, 52, 45, 47, 48, 58, 61, 65, 66, 67, 69, 71, 72) will be updated using the following protocol:
1. Compile the test batch runner with `-DZ98_TEST`.
2. Run the runner to identify specific mismatches.
3. Update the `.cpp` source files to reflect the counter-based deterministic output (e.g., changing `zF_d071e5_foo` to `zF_0_foo`).
4. Re-verify the batch.

---

## Examples Status

All functional examples were verified to compile and run successfully in both 32-bit and 64-bit environments.

| Example | Status | Notes |
|---------|--------|-------|
| hello | **PASS** | |
| prime | **PASS** | |
| days_in_month | **PASS** | |
| fibonacci | **PASS** | |
| heapsort | **PASS** | |
| quicksort | **PASS** | |
| sort_strings | **PASS** | |
| func_ptr_return | **PASS** | |
| lisp_interpreter | **EXCLUDED** | Per task requirements |
| lisp_interpreter_adv | **EXCLUDED** | Per task requirements |
