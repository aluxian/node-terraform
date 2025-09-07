#!/bin/bash

set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <package_dir> <package_name> <version> [npm_token]" >&2
  exit 1
fi

PACKAGE_DIR="$1"
PACKAGE_NAME="$2"
VERSION="$3"
NPM_TOKEN_ARG="${4:-}"

if [[ -n "$NPM_TOKEN_ARG" ]]; then
  export NPM_TOKEN="$NPM_TOKEN_ARG"
fi

if [[ ! -d "$PACKAGE_DIR" || ! -f "$PACKAGE_DIR/package.json" ]]; then
  echo "Error: Invalid package directory: $PACKAGE_DIR" >&2
  exit 1
fi

cd "$PACKAGE_DIR"

# Check if already published
if npm view "$PACKAGE_NAME@$VERSION" version >/dev/null 2>&1; then
  echo "Package $PACKAGE_NAME@$VERSION already exists, skipping"
  exit 0
fi

# Publish
if [[ "${DRY_RUN:-false}" == "true" ]]; then
  echo "DRY RUN: Would publish $PACKAGE_NAME@$VERSION"
else
  npm config set registry "https://registry.npmjs.org"
  npm publish --access public --provenance
  echo "✓ Published $PACKAGE_NAME@$VERSION"
fi