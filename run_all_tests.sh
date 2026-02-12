#!/bin/bash

POSTCLEAN=true
for arg in "$@"; do
    if [ "$arg" == "--no-postclean" ]; then
        POSTCLEAN=false
    fi
done

echo "Running RetroZig test batches..."
echo "================================"

FAILED=0

for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26; do
    BINARY="./test_runner_batch$i"
    echo "Batch $i..."
    if [ -f "$BINARY" ]; then
        # Run the binary directly to ensure output goes to console
        $BINARY
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
            echo "✗ Batch $i failed"
            FAILED=1
        else
            echo "✓ Batch $i passed"
        fi

        if [ "$POSTCLEAN" = true ]; then
            rm -f "$BINARY"
            echo "Cleaned up $BINARY"
        fi
    else
        echo "✗ $BINARY not found"
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
