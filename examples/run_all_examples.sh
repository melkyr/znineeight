#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Running all RetroZig Examples ==="

EXAMPLES="hello prime fibonacci heapsort quicksort sort_strings func_ptr_return"

for ex in $EXAMPLES; do
    echo ""
    echo "--- Example: $ex ---"
    cd "$SCRIPT_DIR/$ex"
    ./run.sh
    cd "$SCRIPT_DIR"
done

echo ""
echo "=== All examples completed successfully! ==="
