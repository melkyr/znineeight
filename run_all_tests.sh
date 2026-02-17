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

# Use find to get all batch runners and sort them numerically
BATCHES=$(ls ./test_runner_batch* 2>/dev/null | sed 's/\.\/test_runner_batch//' | sort -n)

if [ -z "$BATCHES" ]; then
    echo "No test runners found. Run ./test.sh first."
    exit 1
fi

for i in $BATCHES; do
    BINARY="./test_runner_batch$i"
    echo "Batch $i..."

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
