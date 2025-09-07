#!/usr/bin/env node

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { fetchTerraformReleases } from "./check-terraform-updates.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function getCurrentVersions() {
  const packageJsonPath = path.join(__dirname, "..", "package.json");
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
  const optionalDeps = packageJson.optionalDependencies || {};
  
  const terraformPackages = Object.keys(optionalDeps).filter(pkg => pkg.startsWith("@aluxian/terraform-"));
  const platformVersions = {};
  terraformPackages.forEach(pkg => { platformVersions[pkg] = optionalDeps[pkg]; });
  
  return { mainVersion: packageJson.version, platformVersions, packageJson };
}

async function getLatestTerraformVersion() {
  const releases = await fetchTerraformReleases();
  releases.sort((a, b) => {
    const parseVersion = (v) => v.split('.').map(Number);
    const vA = parseVersion(a.version);
    const vB = parseVersion(b.version);
    for (let i = 0; i < 3; i++) {
      if (vA[i] !== vB[i]) return vB[i] - vA[i];
    }
    return 0;
  });
  return releases[0].version;
}

async function main() {
  const args = process.argv.slice(2);
  
  if (args.includes("--check")) {
    const versions = getCurrentVersions();
    const uniquePlatformVersions = [...new Set(Object.values(versions.platformVersions))];
    const platformsConsistent = uniquePlatformVersions.length === 1;
    const mainMatchesPlatforms = platformsConsistent && versions.mainVersion === uniquePlatformVersions[0];
    
    console.log(`Main: ${versions.mainVersion}`);
    console.log(`Platforms: ${platformsConsistent ? uniquePlatformVersions[0] : "inconsistent"}`);
    console.log(`Status: ${mainMatchesPlatforms ? "synchronized" : "out-of-sync"}`);
    process.exit(mainMatchesPlatforms ? 0 : 1);
  }

  try {
    const versions = getCurrentVersions();
    let targetVersion;
    
    if (args.includes("--latest")) {
      targetVersion = await getLatestTerraformVersion();
    } else if (args.includes("--version")) {
      const versionIndex = args.indexOf("--version") + 1;
      targetVersion = args[versionIndex];
    } else {
      console.log("Usage: --check | --latest | --version <version>");
      process.exit(1);
    }
    
    console.log(`Target version: ${targetVersion}`);
    
    const packageJsonPath = path.join(__dirname, "..", "package.json");
    const packageJson = JSON.parse(JSON.stringify(versions.packageJson));
    
    // Update main version
    packageJson.version = targetVersion;
    
    // Update platform versions
    const optionalDeps = packageJson.optionalDependencies || {};
    Object.keys(optionalDeps).forEach(pkg => {
      if (pkg.startsWith("@aluxian/terraform-")) {
        optionalDeps[pkg] = targetVersion;
      }
    });
    
    if (!args.includes("--dry-run")) {
      fs.writeFileSync(packageJsonPath, JSON.stringify(packageJson, null, 2) + "\n", "utf8");
      console.log("✅ Versions synchronized");
    } else {
      console.log("✅ Dry run - no changes made");
    }
  } catch (error) {
    console.error(`Error: ${error.message}`);
    process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}

export { getCurrentVersions, getLatestTerraformVersion };
