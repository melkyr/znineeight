# Technical Debt: TypeChecker Maintainability

This document tracks maintainability issues, code smells, and potential refactoring targets within `src/bootstrap/type_checker.cpp`.

## Maintainability Review Table

| Issue | Method Affected | Difficulty (1-10) | Impact (1-10) | Complexity Reduction (1-10) | Description |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **Monolithic Member Access** | `visitMemberAccess` | 7 | 9 | 9 | The method handles field access, static type access, built-in properties for slices/arrays/optionals, and tagged union variants in a single deeply nested block. Should be split into specialized handlers. |
| **Bloated Built-in Dispatch** | `visitFunctionCall` | 4 | 7 | 8 | Built-ins (e.g., `@sizeOf`, `@ptrCast`) are handled via a long chain of `strcmp` calls inside the main call visitor. Moving these to a dispatch table or specialized functions would significantly clean up the code. |
| **Manual Placeholder Unwrapping** | Global | 3 | 8 | 9 | The pattern `if (t->kind == TYPE_PLACEHOLDER) t = resolvePlaceholder(t);` is repeated nearly 100 times. A unified `getConcreteType(Type*)` helper would reduce noise and prevent "forgot-to-unwrap" bugs. |
| **Redundant Undefined Checks** | Global | 2 | 6 | 7 | Nearly 200 occurrences of `if (!t || is_type_undefined(t)) return get_g_type_undefined();`. Standardizing this into a macro or a short-circuiting helper would improve readability. |
| **Complex VarDecl State Machine** | `visitVarDecl` | 8 | 7 | 6 | Handles local/global distinction, pre-insertion for inference, placeholder registration, and recursive resolution. The logic flow is hard to follow due to mixed concerns. |
| **Scattered Literal Promotion** | `checkBinaryOperation`, `visitAssignment` | 5 | 6 | 7 | Logic for promoting `TYPE_INTEGER_LITERAL` to concrete types is duplicated and slightly varied across binary ops and assignments. |
| **Manual CallSite Cataloging** | `visitFunctionCall` | 4 | 5 | 6 | The setup and resolution of `CallSiteLookupTable` entries adds significant boilerplate to every function call visit. |
| **Switch-Case Exhaustiveness** | `visit` | 3 | 4 | 5 | The main `visit` dispatcher is a large switch. Using a visitor pattern or at least ensuring better modularization of each case would help file size. |

## Detailed Observations

### 1. Deep Nesting in `visitMemberAccess`
The logic for determining if a member access is a "static type access" vs "instance field access" involves multiple levels of `if (node->base->type == NODE_...)` and `if (sym->kind == ...)` which are repeated for different node types. This could be unified by a helper that classifies the base expression.

### 2. Redundant Type Resolution
Methods often call `resolveOrVisit` or `visit` and then immediately perform the same placeholder check. Centralizing this into the `visit` mechanism or a dedicated unwrapper would shave off hundreds of lines.

### 3. Error Reporting Boilerplate
Most error reports follow a pattern of `reportAndReturnUndefined(loc, ERR_CODE, "custom msg")`. While `reportAndReturnUndefined` exists, many places still manually call `unit_.getErrorHandler().report(...)` followed by `return get_g_type_undefined()`.

### 4. Built-in Function Complexity
Built-ins like `@std.debug.print` have specialized, complex validation logic (like format string checking) embedded directly in `visitFunctionCall`. These should be encapsulated in their own validation classes or functions.
