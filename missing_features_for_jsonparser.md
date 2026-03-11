# Missing Features and Limitations for JSON Parser

During the "baptism of fire" compilation and execution of the JSON parser example, the following features and limitations were identified in the RetroZig bootstrap compiler (Z98):

## 1. Hardcoded 32-bit Architecture (Bootstrap Limitation)
- **Status**: Critical Limitation.
- **Observation**: The bootstrap compiler (`zig0`) hardcodes sizes and alignments for a 32-bit target (e.g., `usize` = 4, `[*]T` = 4, `[]T` = 8).
- **Impact**: When the generated C code is compiled with a 64-bit C compiler, memory layout mismatches occur. This leads to data corruption because the C compiler assumes 64-bit pointers and different struct padding while `@sizeOf` constants were folded as 32-bit values.
- **Workaround**: The generated code MUST be compiled with a 32-bit C compiler (e.g., `gcc -m32`) for correct execution.

## 2. Cross-Module Call Resolution Warnings
- **Status**: Diagnostic Defect.
- **Observation**: The compiler issues `Unresolved call` warnings for functions imported from other modules (e.g., `file.readFile`).
- **Impact**: While code generation (`CBackend`) correctly handles these calls, the `TypeChecker`'s internal side-table resolution is incomplete for cross-module calls, leading to noise in the compiler output.

## 3. Native Zig Feature Support Verification
- **union(enum)**: **Supported.** The bootstrap compiler correctly handles tagged unions and generates appropriate C structs and enums.
- **Switch Payload Capture**: **Supported.** The `|payload|` syntax in switch prongs is correctly parsed and lowered into C blocks with local variable assignments.
- **Braceless Control Flow**: **Supported.** `if`, `while`, and `defer` without braces are normalized into blocks by the `ControlFlowLifter`.

## 4. C String Literal Signedness
- **Status**: Interop Sensitivity.
- **Observation**: Zig `u8` maps to C `unsigned char`, but C string literals are `char*`.
- **Impact**: Compiling generated C code with `-pedantic` results in "pointer targets differ in signedness" warnings.
- **Recommendation**: Use `c_char` for C interop where possible.

## 5. Memory Performance
- **Peak Arena Usage**: ~510 KB during JSON parser compilation.
- **Compliance**: Well within the 16MB peak usage constraint.
