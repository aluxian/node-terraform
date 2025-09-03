#!/bin/bash

# Create GitHub release with release notes and artifacts
# Usage: create-github-release.sh <package_version> <terraform_version> [tarball_path]
# Example: create-github-release.sh 1.13.1 1.13.1 ./artifacts/package.tgz

set -euo pipefail

# Function to show usage
usage() {
  cat << EOF
Usage: $0 <package_version> <terraform_version> [tarball_path]

Creates a GitHub release with generated release notes and optional package attachment.

Arguments:
  package_version    Version of the main package (e.g., 1.13.1)
  terraform_version  Version of Terraform included (e.g., 1.13.1)
  tarball_path      Path to package tarball to attach (optional)

Examples:
  $0 1.13.1 1.13.1
  $0 1.13.1 1.13.1 ./artifacts/package.tgz
  $0 2.0.0 1.13.1 ./package.tgz

Environment Variables:
  GITHUB_TOKEN      GitHub token for authentication (required)
  GITHUB_REPOSITORY Repository in format owner/repo (default: auto-detect)
  DRY_RUN          Set to 'true' to generate notes without creating release
  PRERELEASE       Set to 'true' to mark as prerelease
  DRAFT            Set to 'true' to create as draft
  GENERATE_NOTES   Set to 'false' to skip auto-generated release notes

Release Features:
  - Auto-generates comprehensive release notes
  - Lists all supported platforms
  - Includes installation and usage instructions
  - Attaches package tarball if provided
  - Links to full changelog and documentation
  - Supports draft and prerelease modes
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

PACKAGE_VERSION="$1"
TERRAFORM_VERSION="$2"
TARBALL_PATH="${3:-}"

# Environment variables
DRY_RUN="${DRY_RUN:-false}"
PRERELEASE="${PRERELEASE:-false}"
DRAFT="${DRAFT:-false}"
GENERATE_NOTES="${GENERATE_NOTES:-true}"

# Auto-detect GitHub repository if not set
if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  if [[ -d ".git" ]]; then
    ORIGIN_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
    if [[ "$ORIGIN_URL" =~ github\.com[:/]([^/]+/[^/]+) ]]; then
      GITHUB_REPOSITORY="${BASH_REMATCH[1]%.git}"
    fi
  fi
fi

# Validate required environment
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  error "GITHUB_TOKEN environment variable is required"
  exit 1
fi

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  error "GITHUB_REPOSITORY not set and could not auto-detect"
  echo "Set GITHUB_REPOSITORY=owner/repo or run from git repository" >&2
  exit 1
fi

# Validate versions
if [[ ! "$PACKAGE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?(\+[a-z0-9.-]+)?$ ]]; then
  error "Invalid package version format: $PACKAGE_VERSION"
  echo "Expected format: X.Y.Z" >&2
  exit 1
fi

if [[ ! "$TERRAFORM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?(\+[a-z0-9.-]+)?$ ]]; then
  error "Invalid terraform version format: $TERRAFORM_VERSION"
  echo "Expected format: X.Y.Z" >&2
  exit 1
fi

# Validate tarball if provided
if [[ -n "$TARBALL_PATH" && ! -f "$TARBALL_PATH" ]]; then
  error "Tarball file does not exist: $TARBALL_PATH"
  exit 1
fi

info "Creating GitHub release..."
info "Repository: $GITHUB_REPOSITORY"
info "Package version: $PACKAGE_VERSION"
info "Terraform version: $TERRAFORM_VERSION"
info "Dry run: $DRY_RUN"

# Check if gh CLI is available
if ! command -v gh >/dev/null; then
  error "GitHub CLI (gh) is required but not installed"
  echo "Install from: https://cli.github.com/" >&2
  exit 1
fi

# Verify authentication
if ! gh auth status >/dev/null 2>&1; then
  error "GitHub CLI authentication failed"
  echo "Run 'gh auth login' or check GITHUB_TOKEN" >&2
  exit 1
fi

success "GitHub CLI authentication verified"

# Check if release already exists
TAG_NAME="v$PACKAGE_VERSION"
if gh release view "$TAG_NAME" >/dev/null 2>&1; then
  warning "Release $TAG_NAME already exists"
  if [[ "$DRY_RUN" != "true" ]]; then
    info "Use 'gh release delete $TAG_NAME' to remove existing release"
    exit 1
  fi
fi

# Generate release notes
generate_release_notes() {
  cat << EOF
# Release v${PACKAGE_VERSION}

This release includes Terraform ${TERRAFORM_VERSION} binaries for all supported platforms.

## What's Changed

- Updated to Terraform ${TERRAFORM_VERSION}
- Pre-built binaries available for all supported platforms
- Improved installation performance with platform-specific packages

## Platform Support

This release includes platform-specific packages for:

- **macOS**: ARM64, x64 (Intel)
- **Linux**: ARM64, x64, ARM 32-bit
- **Windows**: ARM64, x64
- **FreeBSD**: x64
- **OpenBSD**: x64
- **Solaris**: x64

## Installation

\`\`\`bash
npm install @jahed/terraform
\`\`\`

The appropriate platform binary will be automatically installed based on your system.

## Usage

\`\`\`bash
# Check version
npx terraform --version

# Use terraform normally
npx terraform init
npx terraform plan
npx terraform apply
\`\`\`

## Verification

All binaries in this release are:
- Downloaded directly from [HashiCorp's official releases](https://releases.hashicorp.com/terraform/)
- SHA256 checksum verified against HashiCorp's published checksums
- Distributed without any modifications from the official binaries

## Technical Details

- **Package Manager**: npm with platform-specific optional dependencies
- **Node.js**: Requires Node.js 16.0.0 or later
- **Installation Method**: Automatic platform detection via npm
- **Binary Location**: Resolved at runtime using Node.js \`require.resolve()\`

## Platform Package Versions

All platform-specific packages are published at version \`${TERRAFORM_VERSION}\`:

\`\`\`
@jahed/terraform-darwin-arm64@${TERRAFORM_VERSION}
@jahed/terraform-darwin-x64@${TERRAFORM_VERSION}
@jahed/terraform-linux-arm64@${TERRAFORM_VERSION}
@jahed/terraform-linux-x64@${TERRAFORM_VERSION}
@jahed/terraform-linux-arm@${TERRAFORM_VERSION}
@jahed/terraform-win32-arm64@${TERRAFORM_VERSION}
@jahed/terraform-win32-x64@${TERRAFORM_VERSION}
@jahed/terraform-freebsd-x64@${TERRAFORM_VERSION}
@jahed/terraform-openbsd-x64@${TERRAFORM_VERSION}
@jahed/terraform-solaris-x64@${TERRAFORM_VERSION}
\`\`\`

## Links

- **npm Package**: [https://www.npmjs.com/package/@jahed/terraform](https://www.npmjs.com/package/@jahed/terraform)
- **Documentation**: [README.md](https://github.com/${GITHUB_REPOSITORY}/blob/v${PACKAGE_VERSION}/README.md)
- **Issues**: [GitHub Issues](https://github.com/${GITHUB_REPOSITORY}/issues)
- **Terraform Official**: [https://www.terraform.io/](https://www.terraform.io/)

---

**Full Changelog**: [v${PACKAGE_VERSION}...v${PACKAGE_VERSION}](https://github.com/${GITHUB_REPOSITORY}/compare/v${PACKAGE_VERSION}...v${PACKAGE_VERSION})
EOF
}

# Create release notes
RELEASE_NOTES=$(generate_release_notes)

# Prepare gh release command arguments
GH_ARGS=("release" "create" "$TAG_NAME")
GH_ARGS+=("--title" "v${PACKAGE_VERSION}")
GH_ARGS+=("--notes" "$RELEASE_NOTES")

if [[ "$PRERELEASE" == "true" ]]; then
  GH_ARGS+=("--prerelease")
fi

if [[ "$DRAFT" == "true" ]]; then
  GH_ARGS+=("--draft")
fi

if [[ "$GENERATE_NOTES" == "true" ]]; then
  GH_ARGS+=("--generate-notes")
fi

# Add tarball if provided
if [[ -n "$TARBALL_PATH" ]]; then
  GH_ARGS+=("$TARBALL_PATH")
fi

# Create release or show dry run
if [[ "$DRY_RUN" == "true" ]]; then
  info "DRY RUN: Would create release with command:"
  printf '  gh %s\n' "${GH_ARGS[*]}"
  echo ""
  info "Release notes would be:"
  echo "----------------------------------------"
  echo "$RELEASE_NOTES"
  echo "----------------------------------------"
  success "Dry run completed - no release created"
else
  info "Creating GitHub release..."
  
  if gh "${GH_ARGS[@]}"; then
    success "Successfully created release v${PACKAGE_VERSION}"
    
    # Show release info
    RELEASE_URL="https://github.com/${GITHUB_REPOSITORY}/releases/tag/${TAG_NAME}"
    info "Release URL: $RELEASE_URL"
    
    # Show release details
    info "Release details:"
    gh release view "$TAG_NAME" --json name,tagName,createdAt,url,assets | jq -r '
      "  Title: " + .name +
      "\n  Tag: " + .tagName +
      "\n  Created: " + .createdAt +
      "\n  URL: " + .url +
      "\n  Assets: " + (.assets | length | tostring)
    '
    
  else
    error "Failed to create GitHub release"
    exit 1
  fi
fi

success "GitHub release creation completed successfully"