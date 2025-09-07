#!/usr/bin/env node

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PLATFORM_MAPPING = {
  darwin_amd64: { npm: "@aluxian/terraform-darwin-x64", os: "darwin", cpu: "x64" },
  darwin_arm64: { npm: "@aluxian/terraform-darwin-arm64", os: "darwin", cpu: "arm64" },
  linux_amd64: { npm: "@aluxian/terraform-linux-x64", os: "linux", cpu: "x64" },
  linux_arm64: { npm: "@aluxian/terraform-linux-arm64", os: "linux", cpu: "arm64" },
  linux_arm: { npm: "@aluxian/terraform-linux-arm", os: "linux", cpu: "arm" },
  windows_amd64: { npm: "@aluxian/terraform-win32-x64", os: "win32", cpu: "x64" },
  windows_arm64: { npm: "@aluxian/terraform-win32-arm64", os: "win32", cpu: "arm64" },
  freebsd_amd64: { npm: "@aluxian/terraform-freebsd-x64", os: "freebsd", cpu: "x64" },
  openbsd_amd64: { npm: "@aluxian/terraform-openbsd-x64", os: "openbsd", cpu: "x64" },
  solaris_amd64: { npm: "@aluxian/terraform-solaris-x64", os: "solaris", cpu: "x64" },
};

function validatePackageJson() {
  const packageJsonPath = path.join(__dirname, "..", "package.json");
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
  const optionalDeps = packageJson.optionalDependencies || {};
  const expectedPackages = Object.values(PLATFORM_MAPPING).map((p) => p.npm);
  
  const missing = expectedPackages.filter(pkg => !optionalDeps[pkg]);
  const extra = Object.keys(optionalDeps).filter(pkg => 
    pkg.startsWith("@aluxian/terraform-") && !expectedPackages.includes(pkg));
  
  if (missing.length) console.error("Missing packages:", missing);
  if (extra.length) console.error("Extra packages:", extra);
  
  return missing.length === 0 && extra.length === 0;
}

function validateWorkflowMatrix() {
  const workflowPath = path.join(__dirname, "..", ".github", "workflows", "build-platform-packages.yml");
  const content = fs.readFileSync(workflowPath, "utf8");
  const matches = content.match(/terraform_arch: (\w+_\w+)/g) || [];
  const workflowPlatforms = new Set(matches.map(m => m.match(/terraform_arch: (\w+_\w+)/)[1]));
  const expectedPlatforms = new Set(Object.keys(PLATFORM_MAPPING));
  
  return workflowPlatforms.size === expectedPlatforms.size && 
    [...expectedPlatforms].every(p => workflowPlatforms.has(p));
}

function validateVersions() {
  const packageJsonPath = path.join(__dirname, "..", "package.json");
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
  const optionalDeps = packageJson.optionalDependencies || {};
  const terraformPackages = Object.keys(optionalDeps).filter(pkg => pkg.startsWith("@aluxian/terraform-"));
  
  if (terraformPackages.length === 0) return false;
  
  const versions = new Set(terraformPackages.map(pkg => optionalDeps[pkg]));
  return versions.size === 1;
}

function main() {
  console.log("Validating platform packages...");
  
  const packageValid = validatePackageJson();
  const matrixValid = validateWorkflowMatrix();
  const versionsValid = validateVersions();
  
  if (packageValid && matrixValid && versionsValid) {
    console.log("✅ All validations passed");
    process.exit(0);
  } else {
    console.log("❌ Validation failed");
    process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}

export { PLATFORM_MAPPING };
