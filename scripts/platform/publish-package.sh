#!/bin/bash

# Publish platform package to npm with safety checks
# Usage: publish-package.sh <package_dir> <package_name> <version> [npm_token]
# Example: publish-package.sh ./platform-packages/@jahed/terraform-darwin-arm64 @jahed/terraform-darwin-arm64 1.13.1

set -euo pipefail

# Function to show usage
usage() {
  cat << EOF
Usage: $0 <package_dir> <package_name> <version> [npm_token]

Publishes a platform-specific npm package with safety checks and verification.

Arguments:
  package_dir   Path to the package directory containing package.json
  package_name  Full npm package name (e.g., @jahed/terraform-darwin-arm64)
  version       Expected package version (for verification)
  npm_token     npm authentication token (optional, can use NPM_TOKEN env var)

Examples:
  $0 ./platform-packages/@jahed/terraform-darwin-arm64 @jahed/terraform-darwin-arm64 1.13.1
  $0 ./packages/linux-x64 @jahed/terraform-linux-x64 1.13.1 npm_xxxxxxxx
  
Environment Variables:
  NPM_TOKEN       npm authentication token (alternative to passing as argument)
  DRY_RUN         Set to 'true' to simulate publish without actually publishing
  FORCE_PUBLISH   Set to 'true' to publish even if version already exists (not recommended)
  NPM_REGISTRY    npm registry URL (default: https://registry.npmjs.org)
  PUBLISH_ACCESS  npm publish access level (default: public)

Safety Features:
  - Checks if version already exists on npm
  - Validates package structure before publishing
  - Supports dry-run mode for testing
  - Verifies authentication before attempting publish
  - Uses provenance for supply chain security
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
if [[ $# -lt 3 ]]; then
  error "Missing required arguments"
  usage >&2
  exit 1
fi

PACKAGE_DIR="$1"
PACKAGE_NAME="$2"
VERSION="$3"
NPM_TOKEN_ARG="${4:-}"

# Environment variables
DRY_RUN="${DRY_RUN:-false}"
FORCE_PUBLISH="${FORCE_PUBLISH:-false}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmjs.org}"
PUBLISH_ACCESS="${PUBLISH_ACCESS:-public}"

# Set npm token
if [[ -n "$NPM_TOKEN_ARG" ]]; then
  export NPM_TOKEN="$NPM_TOKEN_ARG"
elif [[ -z "${NPM_TOKEN:-}" ]]; then
  error "npm token not provided"
  echo "Provide token via argument or NPM_TOKEN environment variable" >&2
  exit 1
fi

# Validate package directory
if [[ ! -d "$PACKAGE_DIR" ]]; then
  error "Package directory does not exist: $PACKAGE_DIR"
  exit 1
fi

if [[ ! -f "$PACKAGE_DIR/package.json" ]]; then
  error "package.json not found in $PACKAGE_DIR"
  exit 1
fi

# Validate package name format
if [[ ! "$PACKAGE_NAME" =~ ^@[a-z0-9-]+/[a-z0-9-]+$ ]]; then
  error "Invalid package name format: $PACKAGE_NAME"
  echo "Expected format: @scope/package-name" >&2
  exit 1
fi

# Validate version format
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[\w.-]+)?(\+[\w.-]+)?$ ]]; then
  error "Invalid version format: $VERSION"
  echo "Expected format: X.Y.Z" >&2
  exit 1
fi

cd "$PACKAGE_DIR"

info "Publishing package: $PACKAGE_NAME@$VERSION"
info "Package directory: $PACKAGE_DIR"
info "Registry: $NPM_REGISTRY"
info "Dry run: $DRY_RUN"

# Verify package.json matches expected values
ACTUAL_NAME=$(jq -r '.name' package.json)
ACTUAL_VERSION=$(jq -r '.version' package.json)

if [[ "$ACTUAL_NAME" != "$PACKAGE_NAME" ]]; then
  error "Package name mismatch: expected '$PACKAGE_NAME', found '$ACTUAL_NAME'"
  exit 1
fi

if [[ "$ACTUAL_VERSION" != "$VERSION" ]]; then
  error "Package version mismatch: expected '$VERSION', found '$ACTUAL_VERSION'"
  exit 1
fi

success "Package metadata validation passed"

# Check if package version already exists on npm
info "Checking if package version already exists..."

if npm view "$PACKAGE_NAME@$VERSION" version >/dev/null 2>&1; then
  if [[ "$FORCE_PUBLISH" != "true" ]]; then
    warning "Package $PACKAGE_NAME@$VERSION already exists on npm"
    info "Skipping publish to avoid conflicts"
    info "Use FORCE_PUBLISH=true to override (not recommended)"
    exit 0
  else
    warning "Package already exists but FORCE_PUBLISH=true, proceeding..."
  fi
else
  success "Package version is new, proceeding with publish"
fi

# Verify npm authentication
info "Verifying npm authentication..."

if ! npm whoami >/dev/null 2>&1; then
  error "npm authentication failed"
  echo "Check your NPM_TOKEN or run 'npm login'" >&2
  exit 1
fi

NPM_USER=$(npm whoami)
success "Authenticated as npm user: $NPM_USER"

# Final package validation
info "Running final package validation..."

if ! npm pack --dry-run >/dev/null 2>&1; then
  error "Package validation failed"
  echo "Running npm pack --dry-run with verbose output:" >&2
  npm pack --dry-run
  exit 1
fi

success "Final package validation passed"

# Publish or dry-run
if [[ "$DRY_RUN" == "true" ]]; then
  info "DRY RUN: Would publish package with command:"
  echo "  npm publish --access $PUBLISH_ACCESS --provenance"
  success "Dry run completed - no actual publishing performed"
else
  info "Publishing package to npm..."
  
  # Configure npm for this registry
  npm config set registry "$NPM_REGISTRY"
  
  # Publish with provenance for supply chain security
  if npm publish --access "$PUBLISH_ACCESS" --provenance; then
    success "Successfully published $PACKAGE_NAME@$VERSION"
    
    # Verify the publish was successful
    info "Verifying published package..."
    sleep 2 # Brief delay for npm registry propagation
    
    if npm view "$PACKAGE_NAME@$VERSION" version >/dev/null 2>&1; then
      success "Package verification passed - available on npm"
      
      # Show package info
      info "Published package details:"
      npm view "$PACKAGE_NAME@$VERSION" --json | jq -r '
        "  Name: " + .name + 
        "\n  Version: " + .version + 
        "\n  Size: " + (.dist.unpackedSize | tostring) + " bytes" +
        "\n  Tarball: " + .dist.tarball
      '
      
    else
      warning "Package published but verification failed (may need time to propagate)"
    fi
  else
    error "npm publish failed"
    exit 1
  fi
fi

success "Package publishing completed successfully"