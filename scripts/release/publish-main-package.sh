#!/bin/bash

# Publish main package to npm with safety checks
# Usage: publish-main-package.sh <tarball_path> <package_version> [npm_token]
# Example: publish-main-package.sh ./artifacts/package.tgz 1.13.1

set -euo pipefail

# Function to show usage
usage() {
  cat << EOF
Usage: $0 <tarball_path> <package_version> [npm_token]

Publishes the main npm package tarball with safety checks and verification.

Arguments:
  tarball_path    Path to the package tarball (.tgz file)
  package_version Expected package version (for verification)
  npm_token       npm authentication token (optional, can use NPM_TOKEN env var)

Examples:
  $0 ./artifacts/package.tgz 1.13.1
  $0 ./package.tgz 1.13.1 npm_xxxxxxxx
  
Environment Variables:
  NPM_TOKEN         npm authentication token (alternative to passing as argument)
  DRY_RUN          Set to 'true' to simulate publish without actually publishing
  FORCE_PUBLISH    Set to 'true' to publish even if version already exists (not recommended)
  NPM_REGISTRY     npm registry URL (default: https://registry.npmjs.org)
  PUBLISH_ACCESS   npm publish access level (default: public)
  PACKAGE_NAME     Expected package name (default: @jahed/terraform)

Safety Features:
  - Verifies tarball integrity before publishing
  - Checks if version already exists on npm
  - Validates package structure and metadata
  - Supports dry-run mode for testing
  - Verifies authentication before attempting publish
  - Uses provenance for supply chain security
  - Confirms successful publication
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
PACKAGE_VERSION="$2"
NPM_TOKEN_ARG="${3:-}"

# Environment variables
DRY_RUN="${DRY_RUN:-false}"
FORCE_PUBLISH="${FORCE_PUBLISH:-false}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmjs.org}"
PUBLISH_ACCESS="${PUBLISH_ACCESS:-public}"
PACKAGE_NAME="${PACKAGE_NAME:-@jahed/terraform}"

# Set npm token
if [[ -n "$NPM_TOKEN_ARG" ]]; then
  export NPM_TOKEN="$NPM_TOKEN_ARG"
elif [[ -z "${NPM_TOKEN:-}" ]]; then
  error "npm token not provided"
  echo "Provide token via argument or NPM_TOKEN environment variable" >&2
  exit 1
fi

# Validate tarball exists
if [[ ! -f "$TARBALL_PATH" ]]; then
  error "Tarball file does not exist: $TARBALL_PATH"
  exit 1
fi

# Validate package version format
if [[ ! "$PACKAGE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?(\+[a-z0-9.-]+)?$ ]]; then
  error "Invalid package version format: $PACKAGE_VERSION"
  echo "Expected format: X.Y.Z" >&2
  exit 1
fi

# Convert to absolute path
TARBALL_PATH=$(realpath "$TARBALL_PATH")

info "Publishing main package: $PACKAGE_NAME@$PACKAGE_VERSION"
info "Tarball: $TARBALL_PATH"
info "Registry: $NPM_REGISTRY"
info "Dry run: $DRY_RUN"

# Verify tarball integrity
info "Verifying tarball integrity..."

WORK_DIR=$(mktemp -d)
trap "rm -rf '$WORK_DIR'" EXIT

cd "$WORK_DIR"

# Test tarball extraction
if ! tar -tzf "$TARBALL_PATH" >/dev/null 2>&1; then
  error "Tarball is invalid or corrupted"
  exit 1
fi

# Extract and validate package.json
tar -xzf "$TARBALL_PATH"

if [[ ! -f "package/package.json" ]]; then
  error "package.json not found in tarball"
  exit 1
fi

# Verify package metadata
ACTUAL_NAME=$(jq -r '.name' package/package.json)
ACTUAL_VERSION=$(jq -r '.version' package/package.json)

if [[ "$ACTUAL_NAME" != "$PACKAGE_NAME" ]]; then
  error "Package name mismatch: expected '$PACKAGE_NAME', found '$ACTUAL_NAME'"
  exit 1
fi

if [[ "$ACTUAL_VERSION" != "$PACKAGE_VERSION" ]]; then
  error "Package version mismatch: expected '$PACKAGE_VERSION', found '$ACTUAL_VERSION'"
  exit 1
fi

success "Tarball integrity verification passed"

# Check if package version already exists on npm
info "Checking if package version already exists..."

if npm view "$PACKAGE_NAME@$PACKAGE_VERSION" version >/dev/null 2>&1; then
  if [[ "$FORCE_PUBLISH" != "true" ]]; then
    warning "Package $PACKAGE_NAME@$PACKAGE_VERSION already exists on npm"
    info "This might be a republish attempt. Skipping to avoid conflicts."
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

# Configure npm for this registry
npm config set registry "$NPM_REGISTRY"

# Publish or dry-run
if [[ "$DRY_RUN" == "true" ]]; then
  info "DRY RUN: Would publish package with command:"
  echo "  npm publish --provenance --access $PUBLISH_ACCESS $TARBALL_PATH"
  success "Dry run completed - no actual publishing performed"
else
  info "Publishing package to npm..."
  
  # Publish with provenance for supply chain security
  if npm publish --provenance --access "$PUBLISH_ACCESS" "$TARBALL_PATH"; then
    success "Successfully published $PACKAGE_NAME@$PACKAGE_VERSION"
    
    # Verify the publish was successful
    info "Verifying published package..."
    sleep 3 # Brief delay for npm registry propagation
    
    if npm view "$PACKAGE_NAME@$PACKAGE_VERSION" version >/dev/null 2>&1; then
      success "Package verification passed - available on npm"
      
      # Show detailed package info
      info "Published package details:"
      npm view "$PACKAGE_NAME@$PACKAGE_VERSION" --json | jq -r '
        "  Name: " + .name + 
        "\n  Version: " + .version + 
        "\n  Description: " + (.description // "N/A") +
        "\n  Size (unpacked): " + ((.dist.unpackedSize // 0) | tostring) + " bytes" +
        "\n  Size (packed): " + ((.dist.size // 0) | tostring) + " bytes" +
        "\n  Tarball: " + .dist.tarball +
        "\n  Optional Dependencies: " + ((.optionalDependencies // {} | keys | length) | tostring) + " packages" +
        "\n  Published: " + (.time.modified // .time.created // "unknown")
      '
      
      # Show platform packages info
      PLATFORM_PACKAGES=$(npm view "$PACKAGE_NAME@$PACKAGE_VERSION" optionalDependencies --json 2>/dev/null || echo "{}")
      if [[ "$PLATFORM_PACKAGES" != "{}" ]]; then
        info "Platform packages included:"
        echo "$PLATFORM_PACKAGES" | jq -r 'to_entries | .[] | "  " + .key + ": " + .value'
      fi
      
    else
      warning "Package published but verification failed (may need time to propagate)"
      info "Check manually: npm view $PACKAGE_NAME@$PACKAGE_VERSION"
    fi
    
    # Show npm package URL
    info "Package URL: https://www.npmjs.com/package/$PACKAGE_NAME/v/$PACKAGE_VERSION"
    
  else
    error "npm publish failed"
    echo "Check npm logs for details" >&2
    exit 1
  fi
fi

success "Main package publishing completed successfully"