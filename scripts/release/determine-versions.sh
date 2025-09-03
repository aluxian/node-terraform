#!/bin/bash

# Determine package and terraform versions for release
# Usage: determine-versions.sh [terraform_version] [output_format]
# Example: determine-versions.sh 1.13.1 github

set -euo pipefail

# Function to show usage
usage() {
  cat << EOF
Usage: $0 [terraform_version] [output_format]

Determines package and terraform versions for release workflows.

Arguments:
  terraform_version  Terraform version to use (optional)
  output_format      Output format: github, json, env (default: github)

Examples:
  $0                    # Auto-detect versions, GitHub Actions output
  $0 1.13.1            # Use specific terraform version
  $0 1.13.1 json       # Output as JSON
  $0 "" env            # Output as environment variables

Version Resolution Priority:
  1. Command line argument (terraform_version)
  2. TERRAFORM_VERSION environment variable
  3. Git tag (if GITHUB_REF_TYPE=tag)
  4. package.json version (fallback)

Environment Variables:
  TERRAFORM_VERSION   Override terraform version
  GITHUB_REF_TYPE     GitHub ref type (tag, branch)
  GITHUB_REF_NAME     GitHub ref name
  PACKAGE_JSON_PATH   Path to package.json (default: ./package.json)

Output Formats:
  github  - GitHub Actions output format (GITHUB_OUTPUT)
  json    - JSON object with version information
  env     - Environment variable format (KEY=value)
EOF
}

# Color output functions (only for non-output modes)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  if [[ "${OUTPUT_FORMAT:-github}" != "json" ]]; then
    echo -e "${BLUE}ℹ️  $1${NC}" >&2
  fi
}

log_success() {
  if [[ "${OUTPUT_FORMAT:-github}" != "json" ]]; then
    echo -e "${GREEN}✅ $1${NC}" >&2
  fi
}

log_warning() {
  if [[ "${OUTPUT_FORMAT:-github}" != "json" ]]; then
    echo -e "${YELLOW}⚠️  Warning: $1${NC}" >&2
  fi
}

log_error() {
  echo -e "${RED}❌ Error: $1${NC}" >&2
}

# Parse arguments
TERRAFORM_VERSION_ARG="${1:-}"
OUTPUT_FORMAT="${2:-github}"

# Environment variables
PACKAGE_JSON_PATH="${PACKAGE_JSON_PATH:-./package.json}"

# Validate output format
case "$OUTPUT_FORMAT" in
  github|json|env)
    ;;
  *)
    log_error "Invalid output format: $OUTPUT_FORMAT"
    echo "Valid formats: github, json, env" >&2
    exit 1
    ;;
esac

# Validate package.json exists
if [[ ! -f "$PACKAGE_JSON_PATH" ]]; then
  log_error "package.json not found: $PACKAGE_JSON_PATH"
  exit 1
fi

log_info "Determining versions for release..."
log_info "Package.json: $PACKAGE_JSON_PATH"
log_info "Output format: $OUTPUT_FORMAT"

# Get package version from package.json
if ! PACKAGE_VERSION=$(jq -r '.version' "$PACKAGE_JSON_PATH" 2>/dev/null); then
  log_error "Failed to read version from package.json"
  exit 1
fi

if [[ "$PACKAGE_VERSION" == "null" || -z "$PACKAGE_VERSION" ]]; then
  log_error "No version found in package.json"
  exit 1
fi

log_success "Package version: $PACKAGE_VERSION"

# Determine terraform version with priority order
TERRAFORM_VERSION=""

# 1. Command line argument
if [[ -n "$TERRAFORM_VERSION_ARG" ]]; then
  TERRAFORM_VERSION="$TERRAFORM_VERSION_ARG"
  log_info "Using command line terraform version: $TERRAFORM_VERSION"

# 2. Environment variable
elif [[ -n "${TERRAFORM_VERSION:-}" ]]; then
  TERRAFORM_VERSION="$TERRAFORM_VERSION"
  log_info "Using environment variable terraform version: $TERRAFORM_VERSION"

# 3. Git tag (GitHub Actions context)
elif [[ "${GITHUB_REF_TYPE:-}" == "tag" && -n "${GITHUB_REF_NAME:-}" ]]; then
  # Extract version from git tag (remove 'v' prefix if present)
  TERRAFORM_VERSION="${GITHUB_REF_NAME#v}"
  log_info "Using git tag terraform version: $TERRAFORM_VERSION"

# 4. Fallback to package.json version
else
  TERRAFORM_VERSION="$PACKAGE_VERSION"
  log_warning "No terraform version specified, using package.json version: $TERRAFORM_VERSION"
fi

# Validate terraform version format
if [[ ! "$TERRAFORM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?(\+[a-z0-9.-]+)?$ ]]; then
  log_error "Invalid terraform version format: $TERRAFORM_VERSION"
  echo "Expected format: X.Y.Z" >&2
  exit 1
fi

log_success "Terraform version: $TERRAFORM_VERSION"

# Output versions in requested format
case "$OUTPUT_FORMAT" in
  github)
    # GitHub Actions output format
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      echo "package_version=$PACKAGE_VERSION" >> "$GITHUB_OUTPUT"
      echo "terraform_version=$TERRAFORM_VERSION" >> "$GITHUB_OUTPUT"
      log_success "Versions written to GITHUB_OUTPUT"
    else
      log_warning "GITHUB_OUTPUT not set, outputting to stdout"
      echo "package_version=$PACKAGE_VERSION"
      echo "terraform_version=$TERRAFORM_VERSION"
    fi
    ;;
    
  json)
    # JSON output
    jq -n \
      --arg package_version "$PACKAGE_VERSION" \
      --arg terraform_version "$TERRAFORM_VERSION" \
      '{
        package_version: $package_version,
        terraform_version: $terraform_version,
        source: {
          package_json: $package_version,
          terraform: $terraform_version
        }
      }'
    ;;
    
  env)
    # Environment variable format
    echo "PACKAGE_VERSION=$PACKAGE_VERSION"
    echo "TERRAFORM_VERSION=$TERRAFORM_VERSION"
    ;;
esac

log_info "Version determination completed successfully"