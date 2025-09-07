#!/usr/bin/env node

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { PLATFORM_MAPPING } from "./validate-platform-packages.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function validateVersion(version) {
  if (!version) {
    console.error("Version is required");
    process.exit(1);
  }
  const semverRegex = /^\d+\.\d+\.\d+(-[\w.-]+)?(\+[\w.-]+)?$/;
  if (!semverRegex.test(version)) {
    console.error(`Invalid version format: ${version}`);
    process.exit(1);
  }
  return version;
}

function updateOptionalDependencies(packageJson, version) {
  const optionalDeps = packageJson.optionalDependencies || {};
  const expectedPackages = Object.values(PLATFORM_MAPPING).map(p => p.npm);
  
  // Update existing packages
  Object.keys(optionalDeps).forEach(pkg => {
    if (pkg.startsWith("@aluxian/terraform-")) {
      optionalDeps[pkg] = version;
    }
  });
  
  // Add missing packages
  expectedPackages.forEach(pkg => {
    if (!optionalDeps[pkg]) {
      optionalDeps[pkg] = version;
    }
  });
  
  packageJson.optionalDependencies = optionalDeps;
  return { updatedPackageJson: packageJson };
}

function main() {
  const args = process.argv.slice(2);
  const version = validateVersion(args[0] || args[args.indexOf("--version") + 1]);
  const dryRun = args.includes("--dry-run");
  
  const packageJsonPath = path.join(__dirname, "..", "package.json");
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
  
  const result = updateOptionalDependencies(packageJson, version);
  
  console.log(`Target version: ${version}`);
  
  if (dryRun) {
    console.log("Dry run - no changes made");
    process.exit(0);
  }
  
  const content = JSON.stringify(result.updatedPackageJson, null, 2) + "\n";
  fs.writeFileSync(packageJsonPath, content, "utf8");
  console.log("✅ Updated optionalDependencies");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}

export { validateVersion, updateOptionalDependencies };
