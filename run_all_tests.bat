@echo off
echo Running RetroZig test batches...
echo ================================

set FAILED=0

for %%i in (1 2 3 4 5 6 7) do (
    echo Batch %%i...
    if exist test_runner_batch%%i.exe (
        test_runner_batch%%i.exe
        if errorlevel 1 (
            echo ^[Batch %%i failed^]
            set FAILED=1
        ) else (
            echo ^[Batch %%i passed^]
        )
    ) else (
        echo ^[test_runner_batch%%i.exe not found^]
        set FAILED=1
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
