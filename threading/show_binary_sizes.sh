#!/bin/bash

# Build both configurations
echo "Building empty programs..."
dub clean > /dev/null 2>&1
dub build --compiler=ldc2 --config=empty_native > /dev/null 2>&1
dub build --compiler=ldc2 --config=empty_betterC > /dev/null 2>&1

# Find the executables
NATIVE_PATH=$(find ~/.dub/cache/threading/~master/build -name "threading" -path "*/empty_native-*" -type f 2>/dev/null | head -1)
BETTERC_PATH=$(find ~/.dub/cache/threading/~master/build -name "threading" -path "*/empty_betterC-*" -type f 2>/dev/null | head -1)

if [ -z "$NATIVE_PATH" ] || [ -z "$BETTERC_PATH" ]; then
    echo "Error: Could not find built executables"
    exit 1
fi

# Display comparison
echo ""
echo "=== Binary Size Comparison: Empty Program ==="
echo ""
echo "Native D (with runtime):"
ls -lh "$NATIVE_PATH"
echo ""
echo "betterC (without runtime):"
ls -lh "$BETTERC_PATH"
echo ""

# Calculate and display detailed stats
NATIVE_SIZE=$(stat -f%z "$NATIVE_PATH")
BETTERC_SIZE=$(stat -f%z "$BETTERC_PATH")
RATIO=$(echo "scale=2; $NATIVE_SIZE / $BETTERC_SIZE" | bc)
NATIVE_MB=$(echo "scale=2; $NATIVE_SIZE / 1024 / 1024" | bc)
BETTERC_MB=$(echo "scale=2; $BETTERC_SIZE / 1024 / 1024" | bc)

echo "=== Size Details ==="
echo "Native:   $NATIVE_SIZE bytes ($NATIVE_MB MB)"
echo "betterC:  $BETTERC_SIZE bytes ($BETTERC_MB MB)"
echo "Ratio:    ${RATIO}x smaller"

