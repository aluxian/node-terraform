#!/usr/bin/env node

/**
 * Generate README.md for platform-specific Terraform packages
 * Usage: node generate-readme.js <package_name> <platform> <npm_arch> <terraform_version> <package_dir>
 * Example: node generate-readme.js @aluxian/terraform-darwin-arm64 darwin arm64 1.13.1 ./platform-packages/@aluxian/terraform-darwin-arm64
 */

import fs from "fs";
import path from "path";

function usage() {
  console.log(`
Usage: node ${process.argv[1]} <package_name> <platform> <npm_arch> <terraform_version> <package_dir>

Generates a README.md file for a platform-specific Terraform package.

Arguments:
  package_name       Full npm package name (e.g., @aluxian/terraform-darwin-arm64)
  platform          Platform name (darwin, linux, win32, freebsd, openbsd, solaris)
  npm_arch          npm architecture (arm64, x64, arm)
  terraform_version Terraform version (e.g., 1.13.1)
  package_dir       Directory where README.md will be created

Examples:
  node ${process.argv[1]} @aluxian/terraform-darwin-arm64 darwin arm64 1.13.1 ./platform-packages/@aluxian/terraform-darwin-arm64
  node ${process.argv[1]} @aluxian/terraform-linux-x64 linux x64 1.13.1 ./packages/linux-x64
  node ${process.argv[1]} @aluxian/terraform-win32-x64 win32 x64 1.13.1 ./win32-package

Environment Variables:
  MAIN_PACKAGE_NAME  Main package name (default: "@aluxian/terraform")
  REPOSITORY_URL     Repository URL (default: "https://github.com/aluxian/node-terraform")
  NPM_URL           npm URL base (default: "https://www.npmjs.com/package")
`);
}

function validateArguments(args) {
  if (args.length < 5) {
    console.error("Error: Missing required arguments");
    usage();
    process.exit(1);
  }

  const [packageName, platform, npmArch, terraformVersion, packageDir] = args;

  // Validate package name
  if (!/^@[a-z0-9-]+\/[a-z0-9-]+$/.test(packageName)) {
    console.error(`Error: Invalid package name format: ${packageName}`);
    console.error("Expected format: @scope/package-name");
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

  // Validate terraform version
  if (!/^\d+\.\d+\.\d+(-[\w.-]+)?(\+[\w.-]+)?$/.test(terraformVersion)) {
    console.error(`Error: Invalid Terraform version format: ${terraformVersion}`);
    console.error("Expected format: X.Y.Z");
    process.exit(1);
  }

  return { packageName, platform, npmArch, terraformVersion, packageDir };
}

function getPlatformDisplayName(platform) {
  const platformNames = {
    darwin: "macOS",
    linux: "Linux",
    win32: "Windows",
    freebsd: "FreeBSD",
    openbsd: "OpenBSD",
    solaris: "Solaris"
  };
  return platformNames[platform] || platform;
}

function getArchDisplayName(npmArch) {
  const archNames = {
    arm64: "ARM64",
    x64: "x64 (Intel/AMD 64-bit)",
    arm: "ARM 32-bit",
    ia32: "x86 (32-bit)"
  };
  return archNames[npmArch] || npmArch;
}

function generateReadme(packageName, platform, npmArch, terraformVersion) {
  // Environment variables with defaults
  const mainPackageName = process.env.MAIN_PACKAGE_NAME || "@aluxian/terraform";
  const repositoryUrl = process.env.REPOSITORY_URL || "https://github.com/aluxian/node-terraform";
  const npmUrl = process.env.NPM_URL || "https://www.npmjs.com/package";

  const platformDisplay = getPlatformDisplayName(platform);
  const archDisplay = getArchDisplayName(npmArch);

  return `# ${packageName}

This package contains the Terraform binary for ${platformDisplay} ${archDisplay}.

This is a platform-specific package that gets automatically installed as an optional dependency of [${mainPackageName}](${npmUrl}/${encodeURIComponent(mainPackageName)}).

**Do not install this package directly.** Instead, install the main package:

\`\`\`bash
npm install ${mainPackageName}
\`\`\`

## Platform Support

- **Operating System**: ${platformDisplay}
- **Architecture**: ${archDisplay}
- **Terraform Version**: ${terraformVersion}

## Usage

After installing the main package, you can use Terraform normally:

\`\`\`bash
# Via npm scripts
npm exec terraform --version

# Via npx
npx terraform --version

# Direct binary (if in PATH)
terraform --version
\`\`\`

## Package Contents

This package contains:
- The official Terraform ${terraformVersion} binary for ${platformDisplay} ${archDisplay}
- Platform and architecture restrictions to ensure correct installation
- No additional dependencies or modifications

## Verification

The Terraform binary included in this package:
- Is downloaded directly from [HashiCorp's official releases](https://releases.hashicorp.com/terraform/)
- Has its SHA256 checksum verified against HashiCorp's published checksums
- Is not modified in any way from the official distribution

## License

MIT - See the main [${mainPackageName}](${repositoryUrl}) repository for details.

## Related Packages

This package is part of the ${mainPackageName} ecosystem:

- **Main package**: [${mainPackageName}](${npmUrl}/${encodeURIComponent(mainPackageName)}) - Install this instead
- **Source code**: [${repositoryUrl}](${repositoryUrl})
- **Issues**: [${repositoryUrl}/issues](${repositoryUrl}/issues)

## Technical Details

- **Package Type**: Platform-specific binary distribution
- **Installation**: Automatic via npm's optionalDependencies
- **Node.js**: Requires Node.js 16.0.0 or later
- **Platform Detection**: Automatic based on \`process.platform\` and \`process.arch\`
`;
}

function writeReadme(readmeContent, packageDir) {
  // Ensure package directory exists
  if (!fs.existsSync(packageDir)) {
    console.error(`Error: Package directory does not exist: ${packageDir}`);
    process.exit(1);
  }

  const readmePath = path.join(packageDir, "README.md");
  
  try {
    fs.writeFileSync(readmePath, readmeContent, "utf8");
    console.log(`✓ Generated README.md: ${readmePath}`);
    return readmePath;
  } catch (error) {
    console.error(`Error: Failed to write README.md: ${error.message}`);
    process.exit(1);
  }
}

function validateGeneratedReadme(readmePath) {
  try {
    const content = fs.readFileSync(readmePath, "utf8");
    
    // Basic validation - check for required sections
    const requiredSections = [
      "# @aluxian/terraform-", // Package title
      "## Platform Support",
      "## Usage",
      "## License"
    ];
    
    for (const section of requiredSections) {
      if (!content.includes(section)) {
        throw new Error(`Missing required section: ${section}`);
      }
    }
    
    // Check minimum length
    if (content.length < 500) {
      throw new Error("README content seems too short");
    }
    
    console.log(`✓ README validation passed (${content.length} characters)`);
    return true;
  } catch (error) {
    console.error(`Error: README validation failed: ${error.message}`);
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
  
  const { packageName, platform, npmArch, terraformVersion, packageDir } = validateArguments(args);
  
  console.log(`Generating README.md for ${packageName}...`);
  console.log(`Platform: ${getPlatformDisplayName(platform)} ${getArchDisplayName(npmArch)}`);
  console.log(`Terraform version: ${terraformVersion}`);
  console.log(`Output directory: ${packageDir}`);
  
  const readmeContent = generateReadme(packageName, platform, npmArch, terraformVersion);
  const readmePath = writeReadme(readmeContent, packageDir);
  validateGeneratedReadme(readmePath);
  
  console.log("✅ README.md generation completed successfully");
}

if (require.main === module) {
  main();
}

module.exports = {
  generateReadme,
  validateArguments,
  writeReadme,
  validateGeneratedReadme,
  getPlatformDisplayName,
  getArchDisplayName,
};