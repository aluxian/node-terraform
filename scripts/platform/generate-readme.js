#!/usr/bin/env node

import fs from "fs";
import path from "path";

const args = process.argv.slice(2);
if (args.length < 5) {
  console.error("Usage: node generate-readme.js <package_name> <platform> <npm_arch> <terraform_version> <package_dir>");
  process.exit(1);
}

const [packageName, platform, npmArch, terraformVersion, packageDir] = args;

const platformNames = {
  darwin: "macOS", linux: "Linux", win32: "Windows", 
  freebsd: "FreeBSD", openbsd: "OpenBSD", solaris: "Solaris"
};

const archNames = {
  arm64: "ARM64", x64: "x64", arm: "ARM 32-bit", ia32: "x86 32-bit"
};

const readmeContent = `# ${packageName}

Platform-specific Terraform binary for ${platformNames[platform] || platform} ${archNames[npmArch] || npmArch}.

**Do not install directly.** Install [@aluxian/terraform](https://www.npmjs.com/package/@aluxian/terraform) instead:

\`\`\`bash
npm install @aluxian/terraform
\`\`\`

This package contains Terraform ${terraformVersion} and gets installed automatically as an optional dependency.

For documentation and usage instructions, see the [main repository](https://github.com/aluxian/node-terraform).
`;

const readmePath = path.join(packageDir, "README.md");
fs.writeFileSync(readmePath, readmeContent, "utf8");
console.log(`✓ Generated README.md: ${readmePath}`);