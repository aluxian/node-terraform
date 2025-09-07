#!/usr/bin/env node

/**
 * Generate package.json for platform-specific Terraform packages
 * Usage: node generate-package-json.js <package_name> <version> <platform> <npm_arch> <package_dir>
 * Example: node generate-package-json.js @aluxian/terraform-darwin-arm64 1.13.1 darwin arm64 ./platform-packages/@aluxian/terraform-darwin-arm64
 */

import fs from "fs";
import path from "path";

function usage() {
  console.log(`
Usage: node ${process.argv[1]} <package_name> <version> <platform> <npm_arch> <package_dir>

Generates a package.json file for a platform-specific Terraform package.

Arguments:
  package_name    Full npm package name (e.g., @aluxian/terraform-darwin-arm64)
  version         Terraform version (e.g., 1.13.1)
  platform        Platform name (darwin, linux, win32, freebsd, openbsd, solaris)
  npm_arch        npm architecture (arm64, x64, arm)
  package_dir     Directory where package.json will be created

Examples:
  node ${process.argv[1]} @aluxian/terraform-darwin-arm64 1.13.1 darwin arm64 ./platform-packages/@aluxian/terraform-darwin-arm64
  node ${process.argv[1]} @aluxian/terraform-linux-x64 1.13.1 linux x64 ./packages/linux-x64
  node ${process.argv[1]} @aluxian/terraform-win32-x64 1.13.1 win32 x64 ./win32-package

Environment Variables:
  AUTHOR          Package author (default: "Jahed Ahmed <aluxian.public@gmail.com> (https://aluxian.dev)")
  REPOSITORY      Repository URL (default: "https://github.com/aluxian/node-terraform")
  HOMEPAGE        Homepage URL (default: same as repository)
  BUGS            Bug tracker URL (default: repository + /issues)
  FUNDING         Funding URL (default: "https://aluxian.dev/donate")
`);
}

function validateArguments(args) {
  if (args.length < 5) {
    console.error("Error: Missing required arguments");
    usage();
    process.exit(1);
  }

  const [packageName, version, platform, npmArch, packageDir] = args;

  // Validate package name
  if (!/^@[a-z0-9-]+\/[a-z0-9-]+$/.test(packageName)) {
    console.error(`Error: Invalid package name format: ${packageName}`);
    console.error("Expected format: @scope/package-name");
    process.exit(1);
  }

  // Validate version
  if (!/^\d+\.\d+\.\d+(-[\w.-]+)?(\+[\w.-]+)?$/.test(version)) {
    console.error(`Error: Invalid semantic version format: ${version}`);
    console.error("Expected format: X.Y.Z");
    process.exit(1);
  }

  // Validate platform
  const validPlatforms = ["darwin", "linux", "win32", "freebsd", "openbsd", "solaris"];
  if (!validPlatforms.includes(platform)) {
    console.error(`Error: Invalid platform: ${platform}`);
    console.error(`Valid platforms: ${validPlatforms.join(", ")}`);
    process.exit(1);
  }

  // Validate npm architecture
  const validArchs = ["arm64", "x64", "arm", "ia32"];
  if (!validArchs.includes(npmArch)) {
    console.error(`Error: Invalid npm architecture: ${npmArch}`);
    console.error(`Valid architectures: ${validArchs.join(", ")}`);
    process.exit(1);
  }

  return { packageName, version, platform, npmArch, packageDir };
}

function generatePackageJson(packageName, version, platform, npmArch) {
  // Environment variables with defaults
  const author = process.env.AUTHOR || "Jahed Ahmed <aluxian.public@gmail.com> (https://aluxian.dev)";
  const repository = process.env.REPOSITORY || "https://github.com/aluxian/node-terraform";
  const homepage = process.env.HOMEPAGE || repository;
  const bugs = process.env.BUGS || `${repository}/issues`;
  const funding = process.env.FUNDING || "https://aluxian.dev/donate";

  return {
    name: packageName,
    version: version,
    description: `Terraform binary for ${platform} ${npmArch}`,
    author: author,
    license: "MIT",
    repository: repository,
    homepage: homepage,
    bugs: bugs,
    funding: funding,
    keywords: [
      "terraform",
      "hashicorp",
      "infrastructure",
      "automation",
      "executable",
      "binary",
      platform,
      npmArch
    ],
    os: [platform],
    cpu: [npmArch],
    files: [
      "bin"
    ],
    engines: {
      node: ">=16.0.0"
    }
  };
}

function writePackageJson(packageJson, packageDir) {
  // Ensure package directory exists
  if (!fs.existsSync(packageDir)) {
    console.error(`Error: Package directory does not exist: ${packageDir}`);
    process.exit(1);
  }

  const packageJsonPath = path.join(packageDir, "package.json");
  
  try {
    const content = JSON.stringify(packageJson, null, 2) + "\n";
    fs.writeFileSync(packageJsonPath, content, "utf8");
    console.log(`✓ Generated package.json: ${packageJsonPath}`);
    return packageJsonPath;
  } catch (error) {
    console.error(`Error: Failed to write package.json: ${error.message}`);
    process.exit(1);
  }
}

function validateGeneratedPackage(packageJsonPath) {
  try {
    const content = fs.readFileSync(packageJsonPath, "utf8");
    const parsed = JSON.parse(content);
    
    // Basic validation
    const requiredFields = ["name", "version", "description", "license", "os", "cpu"];
    for (const field of requiredFields) {
      if (!parsed[field]) {
        throw new Error(`Missing required field: ${field}`);
      }
    }
    
    console.log(`✓ Package validation passed: ${parsed.name}`);
    return true;
  } catch (error) {
    console.error(`Error: Package validation failed: ${error.message}`);
    process.exit(1);
  }
}

function main() {
  const args = process.argv.slice(2);
  
  // Handle help flag
  if (args.includes("--help") || args.includes("-h")) {
    usage();
    process.exit(0);
  }
  
  const { packageName, version, platform, npmArch, packageDir } = validateArguments(args);
  
  console.log(`Generating package.json for ${packageName}...`);
  console.log(`Version: ${version}`);
  console.log(`Platform: ${platform} ${npmArch}`);
  console.log(`Output directory: ${packageDir}`);
  
  const packageJson = generatePackageJson(packageName, version, platform, npmArch);
  const packageJsonPath = writePackageJson(packageJson, packageDir);
  validateGeneratedPackage(packageJsonPath);
  
  console.log("✅ Package.json generation completed successfully");
}

if (require.main === module) {
  main();
}

module.exports = {
  generatePackageJson,
  validateArguments,
  writePackageJson,
  validateGeneratedPackage,
};