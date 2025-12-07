@echo off
cl /EHsc /W4 src\bootstrap\*.cpp /Fe:zig0.exe
cl /EHsc /W4 tests\test_arena.cpp /Fe:test_arena.exe
