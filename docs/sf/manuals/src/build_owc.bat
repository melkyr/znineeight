@echo off
REM build_owc.bat - example-only Win9x companion for the manual's programs.
REM This is NOT the seed builder. To build the compiler itself on Win9x,
REM unzip release/seed/zig1_seed_w9.zip, change into its win\ folder, and run
REM one of its two static-CRT scripts:
REM     build_owc_crt.bat ..\zig1.exe
REM     build_target_crt.bat ..\zig1.exe
REM The compiler's own no-CRT build is deferred until the asm_x86 backend;
REM emitted programs still default to no-CRT.
REM
REM For an example program, emit the Windows target first:
REM     zig1 -osw -o out hello.z98
REM The compiler writes its own command.com-safe scripts into out\. Prefer
REM those: build_owc_nocrt.bat is the Win9x no-CRT default and
REM build_owc_crt.bat is the static-CLIB alternate. This file only forwards
REM to the emitted no-CRT OpenWatcom script so older manual text has a
REM command.com-safe entry point; do not use it as a seed recipe.
if exist build_owc_nocrt.bat goto emitted
echo This is an example companion; run it from a -osw emitted output folder.
echo Emit first: zig1 -osw -o out hello.z98
goto done
:emitted
call build_owc_nocrt.bat %1
:done
