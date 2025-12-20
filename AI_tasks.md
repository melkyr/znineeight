# AI Agent Tasks for RetroZig Compiler

This document outlines a granular, step-by-step roadmap for an AI agent to implement the RetroZig compiler. The tasks are organized by phase and component, starting with the C++ bootstrap compiler.

## Phase 0: The Bootstrap Compiler (C++98)

### Milestone 1: Core Infrastructure (COMPLETE)
1.  **Task 1:** Set up the basic directory structure. (DONE)
2.  **Task 2:** Create the `common.hpp` compatibility header. (DONE)
3.  **Task 3:** Implement the `ArenaAllocator` class. (DONE)
4.  **Task 4:** Add alignment support to `ArenaAllocator`. (DONE)
5.  **Task 5:** Implement the `StringInterner` class. (DONE)
6.  **Task 6:** Implement the `SourceManager` class. (DONE)
7.  **Task 7:** Define the `ErrorReport` struct and `ErrorCode` enum. (DONE)
8.  **Task 8:** Implement a basic diagnostic printing function. (DONE)
9.  **Task 9:** Create a minimal unit testing framework. (DONE)
10. **Task 10:** Create initial `build.bat` and `test.bat` scripts. (DONE)

### Milestone 2: Lexer Implementation (COMPLETE)
11. **Task 11:** Define initial `TokenType` enum in `lexer.hpp`. (DONE)
12. **Task 12:** Implement the `Token` struct with a union for literal values. (DONE)
13. **Task 13:** Implement the `Lexer` class skeleton. (DONE)
14. **Task 14:** Implement lexing for single-character tokens. (DONE)
15. **Task 15:** Implement lexing for multi-character tokens. (DONE)
16. **Task 16:** Implement basic identifier and keyword recognition. (DONE)
17. **Task 17:** Update `TokenType` enum in `src/include/lexer.hpp` to include all missing tokens as defined in `Lexer.md`. (DONE)
18. **Task 18:** Implement lexing for `TOKEN_CHAR_LITERAL` (e.g., `'a'`). (DONE)
19. **Task 19:** Implement lexing for `TOKEN_FLOAT_LITERAL` (e.g., `3.14`). (DONE)
20. **Task 20:** Implement lexing for remaining arithmetic and bitwise operators (`%`, `~`, `&`, `|`, `^`, `<<`, `>>`). (DONE)
21. **Task 21:** Implement lexing for compound assignment operators (`+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`, `<<=`, `>>=`). (DONE)
22. **Task 22:** Implement lexing for special and wrapping operators (`.`, `.*`, `.?`, `?`, `++`, `**`, `||`, `+%`, `-%`, `*%`). (DONE)
23. **Task 23:** Implement lexing for remaining delimiters (`:`, `->`, `=>`, `...`). (DONE)
24. **Task 24:** Implement keyword recognition for control flow (`break`, `catch`, `continue`, `else`, `for`, `if`, `orelse`, `resume`, `suspend`, `switch`, `try`, `while`). (DONE)
25. **Task 25:** Implement keyword recognition for type declarations (`enum`, `error`, `struct`, `union`, `opaque`). (DONE)
26. **Task 26:** Implement keyword recognition for visibility and linkage (`export`, `extern`, `pub`, `linksection`, `usingnamespace`). (DONE)
27. **Task 27:** Implement keyword recognition for compile-time and special functions (`asm`, `comptime`, `errdefer`, `inline`, `noinline`, `test`, `unreachable`). (DONE)
28. **Task 28:** Implement keyword recognition for memory and calling conventions (`addrspace`, `align`, `allowzero`, `and`, `anyframe`, `anytype`, `callconv`, `noalias`, `nosuspend`, `or`, `packed`, `threadlocal`, `volatile`). (DONE)
29. **Task 29:** Implement logic to skip single-line and block comments. (This was previously part of other tasks, now consolidated). (DONE)
30. **Task 30:** Write comprehensive unit tests for the lexer, covering all new token types and edge cases.
31. **Task 31:** Implement lexing for `TOKEN_STRING_LITERAL` and properly handle `TOKEN_IDENTIFIER` values. This includes storing the string content (for string literals) and the identifier name, likely using the string interner. (DONE)
32. **Task 32:** Extend the lexer to handle escaped characters in string literals (e.g., `\n`, `\t`, `\\`, `\"`). (DONE)
33. **Task 33:** Implement lexing for crucial missing keywords (`fn`, `var`, `defer`). (DONE)
34. **Task 34:** Implement lexing for missing operators (`--`, `&&`).

### Milestone 3: Parser & AST (COMPLETE)
35. **Task 35:** Define foundational AST structures and nodes for Expressions (Literals, Unary, Binary). (DONE)
36. **Task 36:** Define AST nodes for Statements (`IfStmt`, `WhileStmt`, `ReturnStmt`, `DeferStmt`, `BlockStmt`). (DONE)
37. **Task 37:** Define AST nodes for Declarations (`FnDecl`, `VarDecl`, `ParamDecl`). (DONE)
38. **Task 38:** Define AST nodes for Type Expressions (`TypeName`, `PointerType`, `ArrayType`). (DONE)
39. **Task 39:** Define AST nodes for Container Declarations (`struct`, `enum`, `union`). (DONE)
40. **Task 40:** Define AST nodes for Control Flow (`for`, `switch`). (DONE)
41. **Task 41:** Define AST nodes for Error Handling (`try`, `catch`, `errdefer`). (DONE)
42. **Task 42:** Define AST nodes for Async Operations (`async`, `await`). (DONE)
43. **Task 43:** Define AST nodes for Comptime Operations (`comptime`). (DONE)
44. **Task 44:** Implement the `Parser` class skeleton with helper methods (`advance`, `match`, `expect`). (DONE)
45. **Task 45:** Implement `parseType` to handle type expressions (e.g., `i32`, `*u8`, `[]bool`). (DONE)
46. **Task 46:** Implement parsing for top-level variable declarations (`var` and `const`). (DONE)
47. **Task 47:** Refactor Parser Error Handling and Cleanup. (DONE)
48. **Task 48:** Implement `parseFnDecl` for function definitions. (DONE)
49. **Task 49:** Implement `parseBlockStatement`. (DONE)
50. **Task 50:** Implement `parseIfStatement`. (DONE)
51. **Task 51:** Implement `parseWhileStatement`. (DONE)
52. **Task 52:** Refactor `AST_parser.md` for clarity and correctness. (DONE)
53. **Task 53:** Add Doxygen comments to `parser.cpp` functions. (DONE)
54. **Task 54:** Resolve Technical Constraint Violations in Parser. (DONE)
55. **Task 55:** Implement `parseDeferStatement`. (DONE)
56. **Task 56:** Implement `parseReturnStatement`. (DONE)
57. **Task 57:** Implement `parsePrimaryExpr` for primary expressions. (DONE)
58. **Task 58:** Implement parsing for postfix expressions. (DONE)
59. **Task 59:** Implement `parseUnaryExpr` for unary operators. (DONE)
60. **Task 60:** Implement `parseBinaryExpr` for Core Binary Operators. (DONE)
61. **Task 61:** Extend `parseBinaryExpr` for Bitwise Operators. (DONE)
62. **Task 62:** Extend `parseBinaryExpr` for Logical Operators. (DONE)
63. **Task 63:** Implement `parseForStatement`.
64. **Task 64:** Implement `parseSwitchExpression`.
65. **Task 65:** Implement `parseStructDeclaration`.
66. **Task 66:** Implement `parseUnionDeclaration`.
67. **Task 67:** Implement `parseEnumDeclaration`.
68. **Task 68:** Implement `parseTryExpression`. (DONE)
69. **Task 69:** Implement `parseCatchExpression`.
70. **Task 70:** Implement `parseErrDeferStatement`.
71. **Task 71:** Implement `parseAsyncExpression`. (DONE - NOT SUPPORTED BY DESIGN)
72. **Task 72:** Implement `parseAwaitExpression`. (DONE - NOT SUPPORTED BY DESIGN)
73. **Task 73:** Implement `parseComptimeBlock`. (DONE)
74. **Task 74:** Create Integration Tests for the Parser.
75. **Task 75:** Implement Range Operator (..) Lexing. (DONE)
76. **Task 76:** Implement Non-Empty Function Body Support. (DONE)
77. **Task 77:** Enhance Expression Parsing State Management. (DONE)
78. **Task 78:** Implement Array Slice Expression Parsing. (DONE)
79. **Task 79:** Complete For Loop Statement Parsing with Slice Iteration. (DONE)
80. **Task 80:** Fixing minor concerns. (DONE)
81. **Task 81:** Final Integration Test Suite Validation. (DONE)

### Milestone 4: Bootstrap Type System & Semantic Analysis (IN PROGRESS)
82. **Task 82:** Define core Type struct and TypeKind for C89-compatible types.
83. **Task 83:** Implement minimal Symbol struct and SymbolTable.
84. **Task 84:** Implement basic scope management.
85. **Task 85:** Implement symbol insertion and lookup.
86. **Task 86:** Implement TypeChecker skeleton for bootstrap types.
87. **Task 87:** Implement basic type compatibility.
88. **Task 88:** Type-check variable declarations (basic).
89. **Task 89:** Type-check function signatures.
90. **Task 90:** Implement basic expression type checking.
91. **Task 91:** Reject complex function calls (e.g., >4 arguments, function pointers, variadic).
92. **Task 92:** Implement basic function call validation (argument count and type compatibility).
93. **Task 93:** Implement basic control flow checking (e.g., `if` and `while` conditions must be boolean).
94. **Task 94:** Implement basic pointer operation checking for `&` and `*`.
95. **Task 95:** Create a primitive type mapping table for C89 compatibility.
96. **Task 96:** Implement integer type compatibility validation.
97. **Task 97:** Implement float type compatibility validation.
98. **Task 98:** Implement boolean type compatibility validation.
99. **Task 99:** Implement void type compatibility validation.
100. **Task 100:** Implement pointer type compatibility validation.
101. **Task 101:** Implement array type compatibility validation.
102. **Task 102:** Implement function type compatibility validation.
103. **Task 103:** Implement struct field type compatibility validation.
104. **Task 104:** Implement enum value type compatibility validation.
105. **Task 105:** Implement literal expression compatibility validation.
106. **Task 106:** Implement binary operator compatibility validation.
107. **Task 107:** Implement unary operator compatibility validation.
108. **Task 108:** Implement assignment compatibility validation.
109. **Task 109:** Implement a framework to detect and reject non-C89 features.
110. **Task 110:** Implement `&` (address-of) operator validation.
111. **Task 111:** Implement `*` (dereference) operator validation.
112. **Task 112:** Implement pointer arithmetic validation.
113. **Task 113:** Implement compile-time array bounds analysis.
114. **Task 114:** Detect array slicing syntax `[start..end]`.
115. **Task 115:** Detect slice parameter types.
116. **Task 116:** Detect slice return types.
117. **Task 117:** Detect slice literal creation.
118. **Task 118:** Report slice operations as compilation errors.
119. **Task 119:** Scan for allocation keywords (e.g., `new`, `create`).
120. **Task 120:** Detect heap allocation function calls.
121. **Task 121:** Identify memory management utilities.
122. **Task 122:** Flag all dynamic allocation operations as C89-incompatible.
123. **Task 123:** Provide C89-safe allocation alternatives.
124. **Task 124:** Implement a framework for lifetime analysis.
125. **Task 125:** Identify potential null pointer dereferences.
126. **Task 126:** Track allocation sites for double-free detection.
127. **Task 127:** Track deallocation sites for double-free detection.
128. **Task 128:** Analyze control flow paths for double-free detection.
129. **Task 129:** Identify potential multiple deallocations.
130. **Task 130:** Flag all double-free risks.
131. **Task 131:** Implement struct type checking (simple field access and initialization).
132. **Task 132:** Implement basic enum type checking.
133. **Task 133:** Identify when error union types are used.
134. **Task 134:** Find all error set declarations.
135. **Task 135:** Identify functions that return errors.
136. **Task 136:** Find all `try` expressions in the code.
137. **Task 137:** Find all `catch` expressions.
138. **Task 138:** Design a strategy for mapping Zig errors to C89 integer codes.
139. **Task 139:** Design a strategy to extract success values from error unions.
140. **Task 140:** Design a C89 alternative to Zig's error propagation.
141. **Task 141:** Generate C89-compatible error return patterns.
142. **Task 142:** Define rules to validate error handling patterns.
143. **Task 143:** Implement the elimination of error types from the type system.
144. **Task 144:** Convert error union types to their base types for code generation.
145. **Task 145:** Find functions with identical names.
146. **Task 146:** Analyze function parameter types for uniqueness.
147. **Task 147:** Identify generic/polymorphic functions.
148. **Task 148:** Detect explicit template instantiation.
149. **Task 149:** Detect implicit template instantiation.
150. **Task 150:** Track template specialization.
151. **Task 151:** Catalog instantiation parameters.
152. **Task 152:** Validate instantiation safety.
153. **Task 153:** Design a name-mangling algorithm to create unique C89 function names.
154. **Task 154:** Generate unique, C89-compliant names for all functions.
155. **Task 155:** Build a call site lookup table.
156. **Task 156:** Update direct function calls to use mangled names.
157. **Task 157:** Update indirect function calls.
158. **Task 158:** Update recursive calls.
159. **Task 159:** Validate all call resolutions work correctly.
160. **Task 160:** Write bootstrap-specific unit tests for the type system.
161. **Task 161:** Test literal expressions end-to-end.
162. **Task 162:** Test variable declarations end-to-end.
163. **Task 163:** Test arithmetic operations end-to-end.
164. **Task 164:** Test function declarations end-to-end.
165. **Task 165:** Test simple function calls end-to-end.
166. **Task 166:** Test `if` statements end-to-end.
167. **Task 167:** Test `while` loops end-to-end.
168. **Task 168:** Test basic struct usage end-to-end.
169. **Task 169:** Test pointer operations end-to-end.
170. **Task 170:** Implement a framework to compile and validate generated C89 code.
171. **Task 171:** Optimize for bootstrap performance.
172. **Task 172:** Document bootstrap limitations clearly.

### Milestone 5: Code Generation (C89)
173. **Task 173:** Implement a basic C89 emitter class in `codegen.hpp`.
174. **Task 174:** Implement `CVariableAllocator` to manage C variable names.
175. **Task 175:** Generate C89 function declarations.
176. **Task 176:** Generate C89 code for integer literals.
177. **Task 177:** Generate C89 code for local variable declarations.
178. **Task 178:** Generate C89 code for basic arithmetic operations.
179. **Task 179:** Generate C89 code for comparison and logical operations.
180. **Task 180:** Generate C89 code for if statements.
181. **Task 181:** Generate C89 code for while and for loops.
182. **Task 182:** Generate C89 code for return statements.
183. **Task 183:** Implement C89 function call generation.
184. **Task 184:** Implement C89 code generation for defer statements.
185. **Task 185:** Generate C89 code for slice types.
186. **Task 186:** Generate C89 code for error unions.
187. **Task 187:** Write integration tests for the C89 code generator.

### Milestone 6: C Library Integration & Final Bootstrap
188. **Task 188:** Implement the CBackend class skeleton for final code emission.
189. **Task 189:** Add logic to generate proper C89 headers and include guards.
190. **Task 190:** Implement wrappers for Zig runtime features to C library calls.
191. **Task 191:** Handle Zig memory management with C89-compatible patterns.
192. **Task 192:** Integrate CBackend to write complete C89 `.c` files.
193. **Task 193:** Compile a "hello world" Zig program end-to-end.

## Phase 1: The Cross-Compiler (Zig)
194. **Task 194:** Translate the C++ compiler logic into the supported Zig subset.
195. **Task 195:** Use the C++ bootstrap compiler (`zig0.exe`) to compile the new Zig compiler (`zig1.exe`).
196. **Task 196:** Verify `zig1.exe` by using it to compile the test suite.

## Phase 2: Self-Hosting
197. **Task 197:** Use `zig1.exe` to compile its own source code, producing `zig2.exe`.
198. **Task 198:** Perform a binary comparison between `zig1.exe` and `zig2.exe` to confirm self-hosting.
