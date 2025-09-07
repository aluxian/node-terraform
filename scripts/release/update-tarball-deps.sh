#!/bin/bash

# Update optionalDependencies in a package tarball
# Usage: update-tarball-deps.sh <tarball_path> <terraform_version> [output_path]
# Example: update-tarball-deps.sh ./artifacts/package.tgz 1.13.1

set -euo pipefail

# Function to show usage
usage() {
  cat << EOF
Usage: $0 <tarball_path> <terraform_version> [output_path]

Updates the optionalDependencies in a package tarball with new terraform version.

Arguments:
  tarball_path      Path to the input tarball (.tgz file)
  terraform_version Terraform version for platform packages
  output_path       Path for updated tarball (default: overwrites input)

Examples:
  $0 ./artifacts/package.tgz 1.13.1
  $0 ./package.tgz 1.13.1 ./updated-package.tgz
  $0 /tmp/build/package.tgz 1.5.7

Process:
  1. Extracts package.json from tarball
  2. Updates all @aluxian/terraform-* packages in optionalDependencies
  3. Validates the updated JSON structure
  4. Repackages with updated package.json
  5. Verifies the final tarball integrity

Environment Variables:
  WORK_DIR          Temporary directory for extraction (default: auto-created)
  BACKUP            Set to 'true' to create backup of original tarball
  VALIDATE_BEFORE   Set to 'false' to skip initial tarball validation
EOF
}

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

error() {
  echo -e "${RED}❌ Error: $1${NC}" >&2
}

warning() {
  echo -e "${YELLOW}⚠️  Warning: $1${NC}" >&2
}

success() {
  echo -e "${GREEN}✅ $1${NC}"
}

info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

# Validate arguments
if [[ $# -lt 2 ]]; then
  error "Missing required arguments"
  usage >&2
  exit 1
fi

TARBALL_PATH="$1"
TERRAFORM_VERSION="$2"
OUTPUT_PATH="${3:-$TARBALL_PATH}"

# Environment variables
BACKUP="${BACKUP:-false}"
VALIDATE_BEFORE="${VALIDATE_BEFORE:-true}"

# Validate inputs
if [[ ! -f "$TARBALL_PATH" ]]; then
  error "Tarball file does not exist: $TARBALL_PATH"
  exit 1
fi

if [[ ! "$TERRAFORM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?(\+[a-z0-9.-]+)?$ ]]; then
  error "Invalid terraform version format: $TERRAFORM_VERSION"
  echo "Expected format: X.Y.Z" >&2
  exit 1
fi

# Convert to absolute paths
TARBALL_PATH=$(realpath "$TARBALL_PATH")
OUTPUT_PATH=$(realpath "$OUTPUT_PATH")

info "Updating tarball dependencies..."
info "Input tarball: $TARBALL_PATH"
info "Terraform version: $TERRAFORM_VERSION"
info "Output tarball: $OUTPUT_PATH"

# Create backup if requested
if [[ "$BACKUP" == "true" && "$OUTPUT_PATH" == "$TARBALL_PATH" ]]; then
  BACKUP_PATH="${TARBALL_PATH}.backup.$(date +%s)"
  cp "$TARBALL_PATH" "$BACKUP_PATH"
  success "Backup created: $BACKUP_PATH"
fi

# Create temporary working directory
WORK_DIR=$(mktemp -d)
trap "rm -rf '$WORK_DIR'" EXIT

cd "$WORK_DIR"

# Validate tarball before processing
if [[ "$VALIDATE_BEFORE" == "true" ]]; then
  info "Validating input tarball..."
  if ! tar -tzf "$TARBALL_PATH" >/dev/null 2>&1; then
    error "Invalid or corrupted tarball: $TARBALL_PATH"
    exit 1
  fi
  success "Input tarball validation passed"
fi

# Extract tarball
info "Extracting tarball..."
if ! tar -xzf "$TARBALL_PATH"; then
  error "Failed to extract tarball"
  exit 1
fi

# Verify package structure
if [[ ! -f "package/package.json" ]]; then
  error "package.json not found in extracted tarball"
  echo "Tarball contents:" >&2
  tar -tzf "$TARBALL_PATH" | head -20 >&2
  exit 1
fi

success "Tarball extracted successfully"

# Load current package.json
PACKAGE_JSON_PATH="package/package.json"
if ! jq . "$PACKAGE_JSON_PATH" >/dev/null 2>&1; then
  error "Invalid JSON in package.json"
  exit 1
fi

# Create updated package.json
TEMP_PKG_JSON=$(mktemp)

info "Updating optionalDependencies to terraform version: $TERRAFORM_VERSION"

# Update optionalDependencies using jq
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
' "$PACKAGE_JSON_PATH" > "$TEMP_PKG_JSON"

# Validate the updated JSON
if ! jq . "$TEMP_PKG_JSON" >/dev/null 2>&1; then
  error "Generated invalid JSON during update"
  exit 1
fi

# Show what was updated
info "Updated optionalDependencies:"
jq '.optionalDependencies' "$TEMP_PKG_JSON"

# Count updated packages
UPDATED_COUNT=$(jq '.optionalDependencies | to_entries | map(select(.key | startswith("@aluxian/terraform-"))) | length' "$TEMP_PKG_JSON")
success "Updated $UPDATED_COUNT platform packages"

# Replace package.json in extracted directory
cp "$TEMP_PKG_JSON" "$PACKAGE_JSON_PATH"

# Verify the replacement was successful
if ! jq . "$PACKAGE_JSON_PATH" >/dev/null 2>&1; then
  error "Failed to update package.json in extracted directory"
  exit 1
fi

success "package.json updated in extracted directory"

# Repackage with updated package.json
info "Repackaging tarball..."

# Create new tarball at output path
if ! tar -czf "$OUTPUT_PATH" package/; then
  error "Failed to create updated tarball"
  exit 1
fi

success "Updated tarball created: $OUTPUT_PATH"

# Verify the final tarball
info "Verifying updated tarball..."

# Extract and check the final package.json
VERIFY_DIR=$(mktemp -d)
trap "rm -rf '$VERIFY_DIR'" EXIT

cd "$VERIFY_DIR"
if ! tar -xzf "$OUTPUT_PATH"; then
  error "Final tarball is invalid or corrupted"
  exit 1
fi

if [[ ! -f "package/package.json" ]]; then
  error "package.json missing from final tarball"
  exit 1
fi

# Verify optionalDependencies were updated correctly
FINAL_TERRAFORM_PACKAGES=$(jq '.optionalDependencies | to_entries | map(select(.key | startswith("@aluxian/terraform-")))' "package/package.json")
EXPECTED_VERSION_COUNT=$(echo "$FINAL_TERRAFORM_PACKAGES" | jq "map(select(.value == \"$TERRAFORM_VERSION\")) | length")
TOTAL_TERRAFORM_PACKAGES=$(echo "$FINAL_TERRAFORM_PACKAGES" | jq 'length')

if [[ "$EXPECTED_VERSION_COUNT" != "$TOTAL_TERRAFORM_PACKAGES" ]]; then
  error "Not all terraform packages updated to version $TERRAFORM_VERSION"
  echo "Expected: $TOTAL_TERRAFORM_PACKAGES, Updated: $EXPECTED_VERSION_COUNT" >&2
  exit 1
fi

success "Final tarball verification passed"

# Get file sizes for reporting
INPUT_SIZE=$(stat -f%z "$TARBALL_PATH" 2>/dev/null || stat -c%s "$TARBALL_PATH" 2>/dev/null || echo "unknown")
OUTPUT_SIZE=$(stat -f%z "$OUTPUT_PATH" 2>/dev/null || stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "unknown")

success "Tarball dependency update completed successfully"
info "Input size: $INPUT_SIZE bytes"
info "Output size: $OUTPUT_SIZE bytes"
info "Platform packages updated: $TOTAL_TERRAFORM_PACKAGES"