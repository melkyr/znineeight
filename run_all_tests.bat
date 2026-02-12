@echo off
setlocal enabledelayedexpansion

set POSTCLEAN=true
for %%a in (%*) do (
    if "%%a"=="--no-postclean" set POSTCLEAN=false
)

echo Running RetroZig test batches...
echo ================================

set FAILED=0

for %%i in (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23) do (
    echo Batch %%i...
    if exist test_runner_batch%%i.exe (
        test_runner_batch%%i.exe
        if errorlevel 1 (
            echo [Batch %%i failed]
            set FAILED=1
        ) else (
            echo [Batch %%i passed]
        )

        if "%POSTCLEAN%"=="true" (
            del /f /q test_runner_batch%%i.exe
            echo Cleaned up test_runner_batch%%i.exe
        )
    ) else (
        if exist test_runner_batch%%i (
            test_runner_batch%%i
            if errorlevel 1 (
                echo [Batch %%i failed]
                set FAILED=1
            ) else (
                echo [Batch %%i passed]
            )

            if "%POSTCLEAN%"=="true" (
                del /f /q test_runner_batch%%i
                echo Cleaned up test_runner_batch%%i
            )
        ) else (
            echo [test_runner_batch%%i not found]
            set FAILED=1
        )
    )
    echo.
)

echo ================================
if %FAILED%==0 (
    echo All test batches passed!
    exit /b 0
) else (
    echo Some test batches failed.
    exit /b 1
)
