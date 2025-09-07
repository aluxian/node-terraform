#!/bin/bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <package_dir> [test_type]" >&2
  exit 1
fi

PACKAGE_DIR="$1"
TEST_TYPE="${2:-basic}"

if [[ ! -d "$PACKAGE_DIR" || ! -f "$PACKAGE_DIR/package.json" ]]; then
  echo "Error: Invalid package directory: $PACKAGE_DIR" >&2
  exit 1
fi

# Basic test: npm pack dry-run
npm pack --dry-run >/dev/null

echo "✓ Package test passed"