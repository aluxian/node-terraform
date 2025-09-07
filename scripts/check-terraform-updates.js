#!/usr/bin/env node

import fs from "fs";
import path from "path";
import https from "https";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function makeHttpRequest(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (response) => {
      let data = "";
      response.on("data", (chunk) => { data += chunk; });
      response.on("end", () => {
        if (response.statusCode === 200) {
          try {
            resolve(JSON.parse(data));
          } catch (error) {
            reject(new Error(`Failed to parse JSON: ${error.message}`));
          }
        } else {
          reject(new Error(`HTTP ${response.statusCode}`));
        }
      });
    }).on("error", reject);
  });
}

async function fetchTerraformReleases() {
  const url = "https://api.releases.hashicorp.com/v1/releases/terraform";
  const data = await makeHttpRequest(url);
  return data.filter(release => !release.version.includes("-"));
}

function compareVersions(a, b) {
  const parseVersion = (v) => v.split('.').map(Number);
  const vA = parseVersion(a);
  const vB = parseVersion(b);
  
  for (let i = 0; i < 3; i++) {
    if (vA[i] !== vB[i]) return vB[i] - vA[i];
  }
  return 0;
}

function getCurrentVersion() {
  const packageJsonPath = path.join(__dirname, "..", "package.json");
  try {
    const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
    const optionalDeps = packageJson.optionalDependencies || {};
    const platformPackages = Object.keys(optionalDeps).filter(pkg => pkg.startsWith("@aluxian/terraform-"));
    return platformPackages.length > 0 ? optionalDeps[platformPackages[0]] : null;
  } catch (error) {
    return null;
  }
}

async function main() {
  const args = process.argv.slice(2);
  const mode = args.includes("--latest") ? "latest" : "check";

  try {
    const releases = await fetchTerraformReleases();
    releases.sort((a, b) => compareVersions(a.version, b.version));
    const currentVersion = getCurrentVersion();

    if (mode === "latest") {
      console.log(releases[0]?.version || "No releases found");
      return;
    }

    const newerReleases = releases.filter(release => compareVersions(release.version, currentVersion) < 0);
    
    console.log(`Current: ${currentVersion || "unknown"}`);
    console.log(`Updates available: ${newerReleases.length}`);
    
    if (newerReleases.length > 0) {
      console.log(`Latest: ${newerReleases[0].version}`);
      console.log(`Update command: node scripts/update-optional-deps.js ${newerReleases[0].version}`);
    }
    
    process.exit(newerReleases.length > 0 ? 1 : 0);
  } catch (error) {
    console.error(`Error: ${error.message}`);
    process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}

export { fetchTerraformReleases, compareVersions, getCurrentVersion };
