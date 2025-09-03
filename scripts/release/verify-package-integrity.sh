#!/bin/bash

# Verify package tarball integrity and structure
# Usage: verify-package-integrity.sh <tarball_path> [terraform_version]
# Example: verify-package-integrity.sh ./artifacts/package.tgz 1.13.1

set -euo pipefail

# Function to show usage
usage() {
  cat << EOF
Usage: $0 <tarball_path> [terraform_version]

Verifies the integrity and structure of a package tarball before publishing.

Arguments:
  tarball_path      Path to the package tarball (.tgz file)
  terraform_version Expected terraform version in optionalDependencies (optional)

Examples:
  $0 ./artifacts/package.tgz
  $0 ./package.tgz 1.13.1
  $0 /tmp/build/package.tgz 1.5.7

Verification Checks:
  - Tarball is valid and extractable
  - package.json exists and is valid JSON
  - Required package.json fields are present
  - optionalDependencies contain expected platform packages
  - Platform package versions match terraform version (if specified)
  - Files listed in 'files' field actually exist
  - No unexpected or sensitive files are included

Environment Variables:
  EXPECTED_PLATFORMS  Comma-separated list of expected platforms (default: auto-detect)
  STRICT_MODE         Set to 'true' for stricter validation (default: false)
  WORK_DIR           Temporary directory for extraction (default: auto-created)
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
if [[ $# -lt 1 ]]; then
  error "Missing required arguments"
  usage >&2
  exit 1
fi

TARBALL_PATH="$1"
TERRAFORM_VERSION="${2:-}"

# Environment variables
STRICT_MODE="${STRICT_MODE:-false}"
EXPECTED_PLATFORMS="${EXPECTED_PLATFORMS:-darwin-arm64,darwin-x64,linux-x64,linux-arm64,linux-arm,win32-x64,win32-arm64,freebsd-x64,openbsd-x64,solaris-x64}"

# Validate tarball exists
if [[ ! -f "$TARBALL_PATH" ]]; then
  error "Tarball file does not exist: $TARBALL_PATH"
  exit 1
fi

# Convert to absolute path
TARBALL_PATH=$(realpath "$TARBALL_PATH")

info "Verifying package integrity..."
info "Tarball: $TARBALL_PATH"
if [[ -n "$TERRAFORM_VERSION" ]]; then
  info "Expected terraform version: $TERRAFORM_VERSION"
fi
info "Strict mode: $STRICT_MODE"

VALIDATION_ERRORS=0

# Create temporary working directory
WORK_DIR=$(mktemp -d)
trap "rm -rf '$WORK_DIR'" EXIT

cd "$WORK_DIR"

# Test tarball extraction
info "Testing tarball extraction..."
if ! tar -tzf "$TARBALL_PATH" >/dev/null 2>&1; then
  error "Tarball is invalid or corrupted"
  exit 1
fi

success "Tarball is valid"

# Extract tarball
if ! tar -xzf "$TARBALL_PATH"; then
  error "Failed to extract tarball"
  exit 1
fi

success "Tarball extracted successfully"

# Verify package structure
if [[ ! -d "package" ]]; then
  error "Expected 'package' directory not found in tarball"
  exit 1
fi

if [[ ! -f "package/package.json" ]]; then
  error "package.json not found in extracted package"
  exit 1
fi

success "Package structure is valid"

# Validate package.json
PACKAGE_JSON_PATH="package/package.json"

info "Validating package.json..."

if ! jq . "$PACKAGE_JSON_PATH" >/dev/null 2>&1; then
  error "package.json is not valid JSON"
  VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
else
  success "package.json is valid JSON"
fi

# Check required fields
REQUIRED_FIELDS=("name" "version" "description" "license" "files")

for field in "${REQUIRED_FIELDS[@]}"; do
  if ! jq -e ".$field" "$PACKAGE_JSON_PATH" >/dev/null 2>&1; then
    error "package.json missing required field: $field"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
  else
    success "package.json has required field: $field"
  fi
done

# Get package info
PACKAGE_NAME=$(jq -r '.name' "$PACKAGE_JSON_PATH")
PACKAGE_VERSION=$(jq -r '.version' "$PACKAGE_JSON_PATH")

info "Package: $PACKAGE_NAME@$PACKAGE_VERSION"

# Validate optionalDependencies
info "Validating optionalDependencies..."

if ! jq -e '.optionalDependencies' "$PACKAGE_JSON_PATH" >/dev/null 2>&1; then
  error "No optionalDependencies found in package.json"
  VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
else
  success "optionalDependencies section exists"
  
  # Convert expected platforms to package names
  IFS=',' read -ra PLATFORMS <<< "$EXPECTED_PLATFORMS"
  EXPECTED_PACKAGES=()
  
  for platform in "${PLATFORMS[@]}"; do
    EXPECTED_PACKAGES+=("@jahed/terraform-$platform")
  done
  
  info "Expected platform packages: ${#EXPECTED_PACKAGES[@]}"
  
  # Check each expected package
  for package in "${EXPECTED_PACKAGES[@]}"; do
    if jq -e ".optionalDependencies[\"$package\"]" "$PACKAGE_JSON_PATH" >/dev/null 2>&1; then
      ACTUAL_VERSION=$(jq -r ".optionalDependencies[\"$package\"]" "$PACKAGE_JSON_PATH")
      success "Found $package: $ACTUAL_VERSION"
      
      # Check version matches if terraform version specified
      if [[ -n "$TERRAFORM_VERSION" && "$ACTUAL_VERSION" != "$TERRAFORM_VERSION" ]]; then
        error "Version mismatch for $package: expected $TERRAFORM_VERSION, got $ACTUAL_VERSION"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
      fi
    else
      error "Missing expected package: $package"
      VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    fi
  done
  
  # Check for unexpected platform packages
  TERRAFORM_PACKAGES=$(jq -r '.optionalDependencies | keys[] | select(startswith("@jahed/terraform-"))' "$PACKAGE_JSON_PATH")
  
  while IFS= read -r pkg; do
    if [[ ! " ${EXPECTED_PACKAGES[*]} " =~ " ${pkg} " ]]; then
      warning "Unexpected platform package: $pkg"
      if [[ "$STRICT_MODE" == "true" ]]; then
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
      fi
    fi
  done <<< "$TERRAFORM_PACKAGES"
fi

# Verify files listed in 'files' field actually exist
info "Verifying package files..."

if jq -e '.files' "$PACKAGE_JSON_PATH" >/dev/null 2>&1; then
  FILES_ARRAY=$(jq -r '.files[]' "$PACKAGE_JSON_PATH")
  
  while IFS= read -r file_pattern; do
    # Check if files matching pattern exist
    if find "package" -path "package/$file_pattern" -o -name "$file_pattern" | grep -q .; then
      success "Files found for pattern: $file_pattern"
    else
      error "No files found for pattern: $file_pattern"
      VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    fi
  done <<< "$FILES_ARRAY"
else
  warning "No 'files' field in package.json"
fi

# Check for sensitive files that shouldn't be included
SENSITIVE_PATTERNS=("*.key" "*.pem" "*.p12" ".env" "*.secret" "node_modules" ".git" "*.log")
SENSITIVE_FOUND=()

info "Checking for sensitive files..."

for pattern in "${SENSITIVE_PATTERNS[@]}"; do
  if find "package" -name "$pattern" -type f | grep -q .; then
    SENSITIVE_FOUND+=("$pattern")
  fi
done

if [[ ${#SENSITIVE_FOUND[@]} -gt 0 ]]; then
  error "Sensitive files found in package:"
  for pattern in "${SENSITIVE_FOUND[@]}"; do
    error "  $pattern"
    find "package" -name "$pattern" -type f
  done
  VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
else
  success "No sensitive files found"
fi

# Package size analysis
TARBALL_SIZE=$(stat -f%z "$TARBALL_PATH" 2>/dev/null || stat -c%s "$TARBALL_PATH" 2>/dev/null || echo "unknown")
info "Package size: $TARBALL_SIZE bytes"

if [[ "$TARBALL_SIZE" != "unknown" ]]; then
  # Warn if package is unusually large or small
  if [[ $TARBALL_SIZE -gt 50000000 ]]; then # 50MB
    warning "Package is quite large ($TARBALL_SIZE bytes)"
  elif [[ $TARBALL_SIZE -lt 1000 ]]; then # 1KB
    warning "Package is very small ($TARBALL_SIZE bytes)"
  fi
fi

# Final summary
echo ""
info "Package Integrity Verification Summary"
info "======================================"
info "Package: $PACKAGE_NAME@$PACKAGE_VERSION"
info "Tarball: $TARBALL_PATH"
info "Size: $TARBALL_SIZE bytes"
info "Validation errors: $VALIDATION_ERRORS"

if [[ $VALIDATION_ERRORS -eq 0 ]]; then
  success "Package integrity verification PASSED"
  exit 0
else
  error "Package integrity verification FAILED with $VALIDATION_ERRORS errors"
  exit 1
fi