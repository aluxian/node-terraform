#!/usr/bin/env node

import fs from "fs";
import path from "path";

const args = process.argv.slice(2);
if (args.length < 5) {
  console.error("Usage: node generate-package-json.js <package_name> <version> <platform> <npm_arch> <package_dir>");
  process.exit(1);
}

const [packageName, version, platform, npmArch, packageDir] = args;

const packageJson = {
  name: packageName,
  version: version,
  description: `Terraform binary for ${platform} ${npmArch}`,
  license: "MIT",
  repository: "https://github.com/aluxian/node-terraform",
  homepage: "https://github.com/aluxian/node-terraform",
  bugs: "https://github.com/aluxian/node-terraform/issues",
  funding: "https://aluxian.dev/donate",
  keywords: ["terraform", "hashicorp", "infrastructure", "automation", "executable", "binary", platform, npmArch],
  os: [platform],
  cpu: [npmArch],
  files: ["bin"],
  engines: { node: ">=16.0.0" }
};

const packageJsonPath = path.join(packageDir, "package.json");
fs.writeFileSync(packageJsonPath, JSON.stringify(packageJson, null, 2) + "\n", "utf8");
console.log(`✓ Generated package.json: ${packageJsonPath}`);