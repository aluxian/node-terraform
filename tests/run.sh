#!/usr/bin/env bash
set -euo pipefail

function get_version_line {
  x_terraform --version | fgrep 'Terraform v' | head -n1
}

function run_tests {
  source "./tests/variants/${1}.sh"

  echo
  echo "[${1}] SETTING UP TEST PROJECT"
  local project_dir="$(mktemp --tmpdir -d node-terraform-test-XXXX)"
  cp -r ./tests/fixtures/. "${project_dir}"
  cp ./artifacts/package.tgz "${project_dir}"
  
  # Set up platform package for testing (generate as needed)
  local platform=$(uname -s | tr '[:upper:]' '[:lower:]')
  local arch=$(uname -m)
  
  # Map architecture names to terraform naming
  case "${arch}" in
    "x86_64") arch="amd64" ;;
    "aarch64") arch="arm64" ;;
    "arm64") arch="arm64" ;;
    *) arch="${arch}" ;;
  esac
  
  # Only set up platform package for current platform
  if [[ "${platform}" == "darwin" && "${arch}" == "arm64" ]]; then
    echo "[${1}] Setting up platform package for ${platform}-${arch}"
    
    # Download terraform binary if not cached
    local cache_dir="${HOME}/.cache/node-terraform-test"
    local terraform_zip="${cache_dir}/terraform_1.13.1_${platform}_${arch}.zip"
    local terraform_binary="${cache_dir}/terraform_1.13.1_${platform}_${arch}"
    
    mkdir -p "${cache_dir}"
    
    if [[ ! -f "${terraform_binary}" ]]; then
      echo "[${1}] Downloading terraform binary for testing..."
      curl -L -o "${terraform_zip}" "https://releases.hashicorp.com/terraform/1.13.1/terraform_1.13.1_${platform}_${arch}.zip"
      unzip -j "${terraform_zip}" terraform -d "${cache_dir}"
      mv "${cache_dir}/terraform" "${terraform_binary}"
      chmod +x "${terraform_binary}"
      rm -f "${terraform_zip}"
    fi
    
    # Create platform package structure in test directory
    mkdir -p "${project_dir}/node_modules/@jahed/terraform-${platform}-${arch}/bin"
    cp "${terraform_binary}" "${project_dir}/node_modules/@jahed/terraform-${platform}-${arch}/bin/terraform"
    chmod +x "${project_dir}/node_modules/@jahed/terraform-${platform}-${arch}/bin/terraform"
    
    # Create package.json for platform package
    cat > "${project_dir}/node_modules/@jahed/terraform-${platform}-${arch}/package.json" << EOF
{
  "name": "@jahed/terraform-${platform}-${arch}",
  "version": "1.13.1",
  "description": "Platform-specific terraform binary for ${platform} ${arch}",
  "main": "index.js",
  "bin": {
    "terraform": "bin/terraform"
  },
  "files": ["bin/**/*", "index.js"]
}
EOF
    
    # Create index.js for platform package
    echo "module.exports = require('./bin/terraform');" > "${project_dir}/node_modules/@jahed/terraform-${platform}-${arch}/index.js"
  fi
  
  echo "[${1}] Created: ${project_dir}"
  pushd "${project_dir}"

  echo
  echo "[${1}] TEST: Executes existing Terraform"
  
  # Set up platform package before installing main package
  # This ensures the platform package is available when terraform tries to run
  local platform=$(uname -s | tr '[:upper:]' '[:lower:]')
  local arch=$(uname -m)
  
  # Map architecture names to terraform naming
  case "${arch}" in
    "x86_64") arch="amd64" ;;
    "aarch64") arch="arm64" ;;
    "arm64") arch="arm64" ;;
    *) arch="${arch}" ;;
  esac
  
  if [[ "${platform}" == "darwin" && "${arch}" == "arm64" ]]; then
    echo "[${1}] Ensuring platform package is available for npm install..."
    # The package structure was already set up earlier, just verify it exists
    if [[ ! -f "./node_modules/@jahed/terraform-${platform}-${arch}/bin/terraform" ]]; then
      echo "[${1}] ERROR: Platform package setup failed"
      exit 1
    fi
  fi
  
  x_install
  local result=$(get_version_line)
  if [[ "${result}" != "Terraform v${expected_version}" ]]; then
    echo "[${1}] Test failed."
    exit 1
  fi

  echo
  echo "[${1}] TEST: Forwards exit codes"
  set +e
  x_terraform --bad-arg > /dev/null 2>&1
  local result=$?
  set -e
  if [[ "${result}" != "127" ]]; then
    echo "[${1}] Test failed."
    exit 1
  fi

  echo
  echo "[${1}] TEST: Reinstalls Terraform with correct version"
  rm -rf ./node_modules/.cache
  x_install
  local result=$(get_version_line)
  if [[ "${result}" != "Terraform v${expected_version}" ]]; then
    echo "[${1}] Test failed."
    exit 1
  fi

  popd
  rm -rf "${project_dir}"

  echo
  echo "[${1}] Tests passed."
}

expected_version="$(cat package.json | jq -r '.version' | cut -d'-' -f1)"

variants="${@:-"npm"}"

for variant in ${variants}; do
  run_tests "${variant}"
done

echo
echo "All tests passed."
