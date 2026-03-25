# RetroZig Test Suite Status Report

## Summary

| Metric | Value |
|--------|-------|
| Total Test Batches | 77 |
| Passed Batches | 68 |
| Failed Batches | 9 |
| Total Pass Rate | 88.3% |

---

## Detailed Breakdown

### Batch 11: Name Mangling (Milestone 4)
- **Failing Test:** `test_NameMangler_Milestone4Types`
- **Reason:** Mismatch between expected and actual mangled names for Special Types. The test expects prefixes `err_` and `opt_`, but the compiler now emits the new mangling scheme `z<Kind>_[<Hash>_]<Name>`.
- **Advice:** Update `tests/test_milestone4_name_mangling.cpp` to use the new mangling strings.

### Batch 31: CBackend Multi-File
- **Failing Test:** `test_CBackend_MultiFile`
- **Reason:** The test expects a "Single Translation Unit" (STU) model where `main.c` includes all other modules. The compiler has migrated to a separate compilation model where modules are compiled individually and linked. The test fails because it cannot find the expected inclusion patterns and internal file naming (e.g., `main_module.c`).
- **Advice:** Refactor the test in `tests/integration/cbackend_multi_file_tests.cpp` to verify the presence of individual module files and a valid build script instead of searching for internal STU-style includes.

### Batch 32: End-to-End Integration
- **Failing Tests:** `test_EndToEnd_HelloWorld`, `test_EndToEnd_PrimeNumbers`
- **Reason:** Compilation/Linkage failure of the generated C code. The test manually invokes `gcc` but only includes `main.c` and `zig_runtime.c`, missing the object files for imported modules (like `greetings` or `std_debug`). This results in "undefined reference" errors.
- **Advice:** Update `tests/integration/end_to_end_hello.cpp` to either use the generated `build_target.sh` script or dynamically discover and link all generated `.c` files in the output directory.

### Batch 52: Implicit Returns
- **Failing Test:** `test_Task9_8_ImplicitReturnErrorVoid`
- **Reason:** Similar to Batch 11, this is a mangling mismatch in a string-based emission check. The test expects `err_void` but the compiler emits the new mangled names.
- **Advice:** Update the expected emission string in `tests/integration/task_9_8_verification_tests.cpp` to match the current compiler output.

### Batch 61, 65, 67, 72: Emission Verification Tests
- **Failing Tests:** Various tests performing string matching on generated C code.
- **Reason:** The new name mangling scheme adds `zF_`, `zV_`, `zS_`, `zE_` prefixes and potential hashes to all global symbols. Many tests use hardcoded expectation strings that do not include these prefixes.
- **Advice:** Update the expectation strings in the respective test files (e.g., `tests/integration/phase1_tagged_union_verification.cpp`, `tests/integration/task_9_8_verification_tests.cpp`) to include the mandatory Kind prefixes.

### Batch 66, 69: Header/Struct Verification Tests
- **Failing Tests:** `test_HeaderEmission_RecursiveStruct`, `test_TaggedUnionVerification_Layout`
- **Reason:** These tests look for specific struct names like `struct Node` or `struct U` in the generated header. These are now mangled as `struct zS_Node` or `struct zS_<Hash>_Node`.
- **Advice:** Update the tests to use `unit.getNameMangler().mangleType(type)` to determine the expected C name instead of using hardcoded strings.

### Batch 71: Symbol Table Mapping
- **Failing Tests:** Tests verifying symbol names in the C emitter.
- **Reason:** The introduction of `getC89GlobalName` using the new mangling scheme changed the output of all global symbol references.
- **Advice:** Update expectation strings to match the new `z<Kind>_` format.

---

## Examples Status

All functional examples were verified to compile and run successfully (without `-m32` in the local environment).

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
