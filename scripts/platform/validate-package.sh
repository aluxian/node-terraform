#!/bin/bash

set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <package_dir> <package_name> <platform> <binary_name>" >&2
  exit 1
fi

PACKAGE_DIR="$1"
PACKAGE_NAME="$2"
PLATFORM="$3"
BINARY_NAME="$4"

ERRORS=0

# Check basic structure
for file in "package.json" "README.md" "bin/$BINARY_NAME"; do
  if [[ ! -f "$PACKAGE_DIR/$file" ]]; then
    echo "❌ Missing: $file" >&2
    ERRORS=$((ERRORS + 1))
  fi
done

# Check package.json name
if [[ -f "$PACKAGE_DIR/package.json" ]]; then
  ACTUAL_NAME=$(jq -r '.name' "$PACKAGE_DIR/package.json" 2>/dev/null || echo "")
  if [[ "$ACTUAL_NAME" != "$PACKAGE_NAME" ]]; then
    echo "❌ package.json name mismatch: expected '$PACKAGE_NAME', got '$ACTUAL_NAME'" >&2
    ERRORS=$((ERRORS + 1))
  fi
fi

# Check binary is executable (Unix-like systems)
if [[ "$PLATFORM" != "win32" && -f "$PACKAGE_DIR/bin/$BINARY_NAME" && ! -x "$PACKAGE_DIR/bin/$BINARY_NAME" ]]; then
  echo "❌ Binary is not executable" >&2
  ERRORS=$((ERRORS + 1))
fi

if [[ $ERRORS -eq 0 ]]; then
  echo "✅ Package validation passed"
  exit 0
else
  echo "❌ Package validation failed with $ERRORS errors" >&2
  exit 1
fi