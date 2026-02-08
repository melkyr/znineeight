#!/bin/bash
echo "Running RetroZig test batches..."
echo "================================"

FAILED=0

for i in 1 2 3 4 5 6 7 8 9 10 11; do
    echo "Batch $i..."
    if [ -f "./test_runner_batch$i" ]; then
        ./test_runner_batch$i
        if [ $? -ne 0 ]; then
            echo "✗ Batch $i failed"
            FAILED=1
        else
            echo "✓ Batch $i passed"
        fi
    else
        echo "✗ test_runner_batch$i not found"
        FAILED=1
    fi
    echo ""
done

echo "================================"
if [ $FAILED -eq 0 ]; then
    echo "All test batches passed!"
    exit 0
else
    echo "Some test batches failed."
    exit 1
fi
