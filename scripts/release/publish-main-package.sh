#!/bin/bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <tarball_path> <package_version> [npm_token]" >&2
  exit 1
fi

TARBALL_PATH="$1"
PACKAGE_VERSION="$2"
NPM_TOKEN_ARG="${3:-}"
PACKAGE_NAME="${PACKAGE_NAME:-@aluxian/terraform}"

if [[ -n "$NPM_TOKEN_ARG" ]]; then
  export NPM_TOKEN="$NPM_TOKEN_ARG"
fi

if [[ ! -f "$TARBALL_PATH" ]]; then
  echo "Error: Tarball not found: $TARBALL_PATH" >&2
  exit 1
fi

# Check if already published
if npm view "$PACKAGE_NAME@$PACKAGE_VERSION" version >/dev/null 2>&1; then
  if [[ "${FORCE_PUBLISH:-false}" != "true" ]]; then
    echo "Package $PACKAGE_NAME@$PACKAGE_VERSION already exists, skipping"
    exit 0
  fi
fi

# Verify tarball has correct package.json
WORK_DIR=$(mktemp -d)
trap "rm -rf '$WORK_DIR'" EXIT
cd "$WORK_DIR"
tar -xzf "$TARBALL_PATH"
ACTUAL_VERSION=$(jq -r '.version' package/package.json 2>/dev/null || echo "")

if [[ "$ACTUAL_VERSION" != "$PACKAGE_VERSION" ]]; then
  echo "Error: Version mismatch: expected '$PACKAGE_VERSION', found '$ACTUAL_VERSION'" >&2
  exit 1
fi

# Publish
if [[ "${DRY_RUN:-false}" == "true" ]]; then
  echo "DRY RUN: Would publish $PACKAGE_NAME@$PACKAGE_VERSION from $TARBALL_PATH"
else
  npm config set registry "https://registry.npmjs.org"
  npm publish --provenance --access public "$TARBALL_PATH"
  echo "✓ Published $PACKAGE_NAME@$PACKAGE_VERSION"
fi