#!/usr/bin/env node

/**
 * Script to validate platform package configuration and matrix setup
 * This helps ensure that the GitHub workflows are properly configured
 */

const fs = require('fs');
const path = require('path');

// Platform mapping from terraform naming to npm package naming
const PLATFORM_MAPPING = {
  'darwin_amd64': { npm: '@jahed/terraform-darwin-x64', os: 'darwin', cpu: 'x64' },
  'darwin_arm64': { npm: '@jahed/terraform-darwin-arm64', os: 'darwin', cpu: 'arm64' },
  'linux_amd64': { npm: '@jahed/terraform-linux-x64', os: 'linux', cpu: 'x64' },
  'linux_arm64': { npm: '@jahed/terraform-linux-arm64', os: 'linux', cpu: 'arm64' },
  'linux_arm': { npm: '@jahed/terraform-linux-arm', os: 'linux', cpu: 'arm' },
  'windows_amd64': { npm: '@jahed/terraform-win32-x64', os: 'win32', cpu: 'x64' },
  'windows_arm64': { npm: '@jahed/terraform-win32-arm64', os: 'win32', cpu: 'arm64' },
  'freebsd_amd64': { npm: '@jahed/terraform-freebsd-x64', os: 'freebsd', cpu: 'x64' },
  'openbsd_amd64': { npm: '@jahed/terraform-openbsd-x64', os: 'openbsd', cpu: 'x64' },
  'solaris_amd64': { npm: '@jahed/terraform-solaris-x64', os: 'solaris', cpu: 'x64' }
};

function validatePackageJson() {
  console.log('🔍 Validating package.json...');
  
  const packageJsonPath = path.join(__dirname, '..', 'package.json');
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
  
  const optionalDeps = packageJson.optionalDependencies || {};
  const expectedPackages = Object.values(PLATFORM_MAPPING).map(p => p.npm);
  
  console.log(`📦 Found ${Object.keys(optionalDeps).length} optional dependencies`);
  console.log(`📦 Expected ${expectedPackages.length} platform packages`);
  
  let missingPackages = [];
  let extraPackages = [];
  
  // Check for missing packages
  expectedPackages.forEach(pkg => {
    if (!optionalDeps[pkg]) {
      missingPackages.push(pkg);
    }
  });
  
  // Check for extra packages
  Object.keys(optionalDeps).forEach(pkg => {
    if (pkg.startsWith('@jahed/terraform-') && !expectedPackages.includes(pkg)) {
      extraPackages.push(pkg);
    }
  });
  
  if (missingPackages.length > 0) {
    console.error('❌ Missing platform packages:');
    missingPackages.forEach(pkg => console.error(`   - ${pkg}`));
  }
  
  if (extraPackages.length > 0) {
    console.warn('⚠️  Extra platform packages (not in workflow):');
    extraPackages.forEach(pkg => console.warn(`   - ${pkg}`));
  }
  
  if (missingPackages.length === 0 && extraPackages.length === 0) {
    console.log('✅ All platform packages are correctly configured');
  }
  
  return { missingPackages, extraPackages, totalPackages: expectedPackages.length, optionalDeps };
}

function validateWorkflowMatrix() {
  console.log('\n🔍 Validating workflow matrix...');
  
  const workflowPath = path.join(__dirname, '..', '.github', 'workflows', 'build-platform-packages.yml');
  const workflowContent = fs.readFileSync(workflowPath, 'utf8');
  
  // Extract matrix entries from the workflow file
  const matrixMatches = workflowContent.match(/- platform: (\w+)\s+arch: ([\w\d]+)\s+terraform_arch: (\w+_\w+)/g);
  
  if (!matrixMatches) {
    console.error('❌ Could not find matrix entries in workflow');
    return { matrixValid: false };
  }
  
  console.log(`📋 Found ${matrixMatches.length} matrix entries in workflow`);
  
  const workflowPlatforms = new Set();
  matrixMatches.forEach(match => {
    const terraformArch = match.match(/terraform_arch: (\w+_\w+)/)[1];
    workflowPlatforms.add(terraformArch);
  });
  
  const expectedPlatforms = new Set(Object.keys(PLATFORM_MAPPING));
  
  let missingFromWorkflow = [];
  let extraInWorkflow = [];
  
  // Check for missing platforms in workflow
  expectedPlatforms.forEach(platform => {
    if (!workflowPlatforms.has(platform)) {
      missingFromWorkflow.push(platform);
    }
  });
  
  // Check for extra platforms in workflow
  workflowPlatforms.forEach(platform => {
    if (!expectedPlatforms.has(platform)) {
      extraInWorkflow.push(platform);
    }
  });
  
  if (missingFromWorkflow.length > 0) {
    console.error('❌ Platforms missing from workflow matrix:');
    missingFromWorkflow.forEach(platform => console.error(`   - ${platform}`));
  }
  
  if (extraInWorkflow.length > 0) {
    console.warn('⚠️  Extra platforms in workflow matrix:');
    extraInWorkflow.forEach(platform => console.warn(`   - ${platform}`));
  }
  
  if (missingFromWorkflow.length === 0 && extraInWorkflow.length === 0) {
    console.log('✅ Workflow matrix is correctly configured');
  }
  
  return { 
    matrixValid: missingFromWorkflow.length === 0 && extraInWorkflow.length === 0,
    totalMatrixEntries: workflowPlatforms.size 
  };
}

function validateBinaryNames() {
  console.log('\n🔍 Validating binary names...');
  
  const workflowPath = path.join(__dirname, '..', '.github', 'workflows', 'build-platform-packages.yml');
  const workflowContent = fs.readFileSync(workflowPath, 'utf8');
  
  // Check that Windows platforms have .exe extension
  const windowsMatches = workflowContent.match(/platform: win32[\s\S]*?binary_name: ([^\s]+)/g);
  
  let windowsValid = true;
  if (windowsMatches) {
    windowsMatches.forEach(match => {
      const binaryName = match.match(/binary_name: ([^\s]+)/)[1];
      if (!binaryName.endsWith('.exe')) {
        console.error(`❌ Windows binary should end with .exe: ${binaryName}`);
        windowsValid = false;
      }
    });
  }
  
  // Check that non-Windows platforms don't have .exe extension
  const nonWindowsMatches = workflowContent.match(/platform: (?!win32)[\w]+[\s\S]*?binary_name: ([^\s]+)/g);
  
  let nonWindowsValid = true;
  if (nonWindowsMatches) {
    nonWindowsMatches.forEach(match => {
      const binaryName = match.match(/binary_name: ([^\s]+)/)[1];
      if (binaryName.endsWith('.exe')) {
        console.error(`❌ Non-Windows binary should not end with .exe: ${binaryName}`);
        nonWindowsValid = false;
      }
    });
  }
  
  if (windowsValid && nonWindowsValid) {
    console.log('✅ Binary names are correctly configured');
  }
  
  return { binaryNamesValid: windowsValid && nonWindowsValid };
}

function validateVersionConsistency() {
  console.log('\n🔍 Validating version consistency...');
  
  const packageJsonPath = path.join(__dirname, '..', 'package.json');
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
  
  const optionalDeps = packageJson.optionalDependencies || {};
  const terraformPackages = Object.keys(optionalDeps).filter(pkg => 
    pkg.startsWith('@jahed/terraform-')
  );
  
  if (terraformPackages.length === 0) {
    console.error('❌ No Terraform platform packages found in optionalDependencies');
    return { versionConsistent: false };
  }
  
  // Check if all platform packages have the same version
  const versions = new Set(terraformPackages.map(pkg => optionalDeps[pkg]));
  
  if (versions.size === 1) {
    const version = Array.from(versions)[0];
    console.log(`✅ All platform packages use consistent version: ${version}`);
    
    // Check if main package version matches platform packages
    if (packageJson.version === version) {
      console.log(`✅ Main package version matches platform packages: ${version}`);
    } else {
      console.warn(`⚠️  Main package version (${packageJson.version}) differs from platform packages (${version})`);
    }
    
    return { versionConsistent: true, version };
  } else {
    console.error('❌ Platform packages have inconsistent versions:');
    terraformPackages.forEach(pkg => {
      console.error(`   ${pkg}: ${optionalDeps[pkg]}`);
    });
    return { versionConsistent: false, versions: Array.from(versions) };
  }
}

function validatePackageNaming() {
  console.log('\n🔍 Validating package naming conventions...');
  
  const packageJsonPath = path.join(__dirname, '..', 'package.json');
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
  
  const optionalDeps = packageJson.optionalDependencies || {};
  const expectedPackages = Object.values(PLATFORM_MAPPING).map(p => p.npm);
  
  let namingValid = true;
  const issues = [];
  
  // Check for packages that follow the pattern but aren't in our mapping
  Object.keys(optionalDeps).forEach(pkg => {
    if (pkg.startsWith('@jahed/terraform-') && !expectedPackages.includes(pkg)) {
      issues.push(`Unknown platform package: ${pkg}`);
      namingValid = false;
    }
  });
  
  // Validate naming pattern consistency
  expectedPackages.forEach(expectedPkg => {
    // Package names are like @jahed/terraform-darwin-x64
    // Split by '/' first to handle scoped packages
    const scope = expectedPkg.split('/');
    if (scope.length !== 2 || scope[0] !== '@jahed') {
      issues.push(`Invalid scope in package name: ${expectedPkg}`);
      namingValid = false;
      return;
    }
    
    const parts = scope[1].split('-');
    if (parts.length !== 3 || parts[0] !== 'terraform') {
      issues.push(`Invalid naming pattern: ${expectedPkg} (expected: @jahed/terraform-platform-arch)`);
      namingValid = false;
    }
  });
  
  if (namingValid) {
    console.log('✅ All package names follow correct naming conventions');
  } else {
    console.error('❌ Package naming issues found:');
    issues.forEach(issue => console.error(`   - ${issue}`));
  }
  
  return { namingValid, issues };
}

function validateSemanticVersions() {
  console.log('\n🔍 Validating semantic versions...');
  
  const packageJsonPath = path.join(__dirname, '..', 'package.json');
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
  
  const optionalDeps = packageJson.optionalDependencies || {};
  const terraformPackages = Object.keys(optionalDeps).filter(pkg => 
    pkg.startsWith('@jahed/terraform-')
  );
  
  let versionsValid = true;
  const invalidVersions = [];
  
  // Basic semantic version regex
  const semverRegex = /^\d+\.\d+\.\d+(-[\w.-]+)?(\+[\w.-]+)?$/;
  
  terraformPackages.forEach(pkg => {
    const version = optionalDeps[pkg];
    if (!semverRegex.test(version)) {
      invalidVersions.push({ package: pkg, version });
      versionsValid = false;
    }
  });
  
  // Also check main package version
  if (!semverRegex.test(packageJson.version)) {
    invalidVersions.push({ package: 'main', version: packageJson.version });
    versionsValid = false;
  }
  
  if (versionsValid) {
    console.log('✅ All versions follow semantic versioning format');
  } else {
    console.error('❌ Invalid semantic versions found:');
    invalidVersions.forEach(({ package: pkg, version }) => {
      console.error(`   ${pkg}: ${version}`);
    });
  }
  
  return { versionsValid, invalidVersions };
}

function validateSecrets() {
  console.log('\n🔍 Validating secrets configuration...');
  
  const workflows = [
    '.github/workflows/build-platform-packages.yml',
    '.github/workflows/publish.yml'
  ];
  
  let secretsValid = true;
  
  workflows.forEach(workflowFile => {
    try {
      const content = fs.readFileSync(workflowFile, 'utf8');
      
      // Check that NPM_TOKEN is used consistently
      if (content.includes('secrets.NPM_TOKEN') && content.includes('NODE_AUTH_TOKEN')) {
        console.log(`✅ ${workflowFile} uses NPM_TOKEN correctly`);
      } else if (content.includes('NPM_TOKEN')) {
        console.warn(`⚠️  ${workflowFile} references NPM_TOKEN but may not use it correctly`);
      }
    } catch (error) {
      console.warn(`⚠️  Could not read ${workflowFile}: ${error.message}`);
    }
  });
  
  return { secretsValid };
}

function main() {
  console.log('🚀 Validating Platform Package Workflow Configuration\n');
  
  const packageResult = validatePackageJson();
  const matrixResult = validateWorkflowMatrix();
  const binaryResult = validateBinaryNames();
  const versionResult = validateVersionConsistency();
  const namingResult = validatePackageNaming();
  const semverResult = validateSemanticVersions();
  const secretsResult = validateSecrets();
  
  console.log('\n📊 Validation Summary:');
  console.log('====================');
  console.log(`Package configuration: ${packageResult.missingPackages.length === 0 && packageResult.extraPackages.length === 0 ? '✅ Valid' : '❌ Issues found'}`);
  console.log(`Workflow matrix: ${matrixResult.matrixValid ? '✅ Valid' : '❌ Issues found'}`);
  console.log(`Binary names: ${binaryResult.binaryNamesValid ? '✅ Valid' : '❌ Issues found'}`);
  console.log(`Version consistency: ${versionResult.versionConsistent ? '✅ Valid' : '❌ Issues found'}`);
  console.log(`Package naming: ${namingResult.namingValid ? '✅ Valid' : '❌ Issues found'}`);
  console.log(`Semantic versions: ${semverResult.versionsValid ? '✅ Valid' : '❌ Issues found'}`);
  console.log(`Secrets config: ${secretsResult.secretsValid ? '✅ Valid' : '❌ Issues found'}`);
  
  console.log(`\n📈 Statistics:`);
  console.log(`- Platform packages in package.json: ${Object.keys(packageResult.optionalDeps || {}).length}`);
  console.log(`- Matrix entries in workflow: ${matrixResult.totalMatrixEntries || 0}`);
  console.log(`- Total supported platforms: ${packageResult.totalPackages}`);
  if (versionResult.version) {
    console.log(`- Current Terraform version: ${versionResult.version}`);
  }
  
  const allValid = packageResult.missingPackages.length === 0 && 
                   packageResult.extraPackages.length === 0 && 
                   matrixResult.matrixValid && 
                   binaryResult.binaryNamesValid && 
                   versionResult.versionConsistent &&
                   namingResult.namingValid &&
                   semverResult.versionsValid &&
                   secretsResult.secretsValid;
  
  if (allValid) {
    console.log('\n🎉 All validations passed! The platform package workflows are ready to use.');
    console.log('\n💡 Useful commands:');
    console.log('   - Check for updates: node scripts/check-terraform-updates.js');
    console.log('   - Update versions: node scripts/update-optional-deps.js <version>');
    console.log('   - Sync versions: node scripts/sync-versions.js');
    process.exit(0);
  } else {
    console.log('\n💥 Some validations failed. Please review and fix the issues above.');
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}

module.exports = {
  validatePackageJson,
  validateWorkflowMatrix,
  validateBinaryNames,
  validateVersionConsistency,
  validatePackageNaming,
  validateSemanticVersions,
  validateSecrets,
  PLATFORM_MAPPING
};