# AI Agent Tasks

This document outlines a series of tasks that can be completed by an AI agent to help with the development of the RetroZig compiler.

## Task 1: Implement the Lexer

The first task is to implement the lexer, which is responsible for taking the source code as input and producing a stream of tokens. The lexer should be able to recognize all of the keywords, operators, and literals in the Zig subset language.

**Acceptance Criteria:**

*   The lexer should be able to correctly tokenize all of the files in the `tests/` directory.
*   The lexer should be able to handle all of the error conditions described in the `error_handler.hpp` file.

## Task 2: Implement the Parser

The second task is to implement the parser, which is responsible for taking the stream of tokens and building an Abstract Syntax Tree (AST). The parser should be able to recognize all of the grammar rules in the Zig subset language.

**Acceptance Criteria:**

*   The parser should be able to correctly parse all of the files in the `tests/` directory.
*   The parser should be able to handle all of the error conditions described in the `error_handler.hpp` file.

## Task 3: Implement the Type System

The third task is to implement the type system, which is responsible for checking the AST for type errors and enforcing the language's type rules.

**Acceptance Criteria:**

*   The type system should be able to correctly identify all of the type errors in the `tests/` directory.
*   The type system should be able to handle all of the error conditions described in the `error_handler.hpp` file.

## Task 4: Implement the Code Generator

The fourth task is to implement the code generator, which is responsible for taking the AST and producing x86 assembly code.

**Acceptance Criteria:**

*   The code generator should be able to produce correct x86 assembly code for all of the files in the `tests/` directory.
*   The generated code should be able to be assembled and run on a Windows 98 machine.

## Coding Conventions

All code should be written in C++98 and should adhere to the following coding conventions:

*   Use 4 spaces for indentation.
*   Use `//` for single-line comments and `/* */` for multi-line comments.
*   All identifiers should be in `snake_case`.
*   All classes and structs should be in `PascalCase`.

## Testing

All code should be accompanied by unit tests. The unit tests should be located in the `tests/` directory and should be written using the testing framework in the `test_framework.h` file.
