#!/bin/bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <tarball_path> <terraform_version> [output_path]" >&2
  exit 1
fi

TARBALL_PATH="$1"
TERRAFORM_VERSION="$2"
OUTPUT_PATH="${3:-$TARBALL_PATH}"

if [[ ! -f "$TARBALL_PATH" ]]; then
  echo "Error: Tarball not found: $TARBALL_PATH" >&2
  exit 1
fi

WORK_DIR=$(mktemp -d)
trap "rm -rf '$WORK_DIR'" EXIT
cd "$WORK_DIR"

# Extract tarball
tar -xzf "$TARBALL_PATH"

if [[ ! -f "package/package.json" ]]; then
  echo "Error: package.json not found in tarball" >&2
  exit 1
fi

# Update optionalDependencies
jq --arg version "$TERRAFORM_VERSION" '
  .optionalDependencies = (.optionalDependencies // {} | 
    with_entries(
      if .key | startswith("@aluxian/terraform-") then
        .value = $version
      else
        .
      end
    )
  )
' "package/package.json" > "package/package.json.tmp"

mv "package/package.json.tmp" "package/package.json"

# Repackage
tar -czf "$OUTPUT_PATH" package/

echo "✓ Updated tarball dependencies to terraform $TERRAFORM_VERSION"