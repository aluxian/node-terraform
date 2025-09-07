#!/bin/bash

set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <package_name> <platform> <downloads_dir> [output_base_dir]" >&2
  exit 1
fi

PACKAGE_NAME="$1"
PLATFORM="$2" 
DOWNLOADS_DIR="$3"
OUTPUT_BASE_DIR="${4:-./platform-packages}"

# Determine binary name
if [[ "$PLATFORM" == "win32" ]]; then
  BINARY_NAME="terraform.exe"
else
  BINARY_NAME="terraform"
fi

BINARY_PATH="$DOWNLOADS_DIR/$BINARY_NAME"
PACKAGE_DIR="$OUTPUT_BASE_DIR/$PACKAGE_NAME"

mkdir -p "$PACKAGE_DIR/bin"
cp "$BINARY_PATH" "$PACKAGE_DIR/bin/"

if [[ "$PLATFORM" != "win32" ]]; then
  chmod +x "$PACKAGE_DIR/bin/$BINARY_NAME"
fi

echo "✓ Package structure created: $PACKAGE_DIR"