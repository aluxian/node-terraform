# Product Requirements Document: Multi-Platform Package Distribution

## Overview

Convert node-terraform from runtime binary downloads to esbuild-style platform-specific packages for improved performance and offline support.

## Current State Analysis

### Existing Implementation
- **Single Package**: `@jahed/terraform` contains all logic
- **Runtime Downloads**: Terraform binaries downloaded on first execution
- **Platform Detection**: Dynamic detection of `process.platform` and `os.arch()`
- **Caching Strategy**: Binaries stored in system cache via `find-cache-dir`
- **Download Source**: Direct downloads from HashiCorp releases

### Current Flow
```
npm install @jahed/terraform
↓
User runs: npx terraform
↓
CLI detects platform → downloads binary → caches → executes
```

### Pain Points
- **Cold Start Delay**: First execution requires download time
- **Network Dependency**: Requires internet connectivity on first use
- **CI/CD Friction**: Download delays in containerized environments
- **Offline Usage**: Impossible without prior cache population

## Proposed Solution

### esbuild-Style Architecture
Adopt esbuild's proven multi-platform distribution pattern:

1. **Main Package**: Contains JavaScript wrapper and platform detection
2. **Platform Packages**: Individual packages per OS/architecture combination
3. **Optional Dependencies**: Automatic platform-appropriate installation
4. **Install-Time Resolution**: Binary availability determined at install time

### Target Architecture
```
@jahed/terraform (main)
├── optionalDependencies: all platform packages
├── install.js: platform detection & binary resolution
└── lib/: JavaScript API and CLI wrapper

@jahed/terraform-darwin-arm64
├── package.json: os: ["darwin"], cpu: ["arm64"]
└── bin/terraform: actual terraform binary

@jahed/terraform-darwin-x64
├── package.json: os: ["darwin"], cpu: ["x64"]  
└── bin/terraform: actual terraform binary

[...additional platform packages...]
```

### Target Flow
```
npm install @jahed/terraform
↓
npm automatically installs correct platform package
↓
User runs: npx terraform
↓
CLI immediately executes cached binary
```

## Technical Implementation

### 1. Platform Detection Module

Create `src/platform.ts` based on esbuild's approach:

```typescript
export interface PlatformInfo {
  pkg: string;
  subpath: string;
}

export function getPlatformPackage(): PlatformInfo {
  const platformKey = `${process.platform} ${os.arch()}`;
  
  const platformMap: Record<string, PlatformInfo> = {
    'darwin arm64': {
      pkg: '@jahed/terraform-darwin-arm64',
      subpath: 'bin/terraform'
    },
    'darwin x64': {
      pkg: '@jahed/terraform-darwin-x64', 
      subpath: 'bin/terraform'
    },
    'linux x64': {
      pkg: '@jahed/terraform-linux-x64',
      subpath: 'bin/terraform'
    },
    'win32 x64': {
      pkg: '@jahed/terraform-win32-x64',
      subpath: 'terraform.exe'
    }
    // ... additional platforms
  };
  
  const platform = platformMap[platformKey];
  if (!platform) {
    throw new Error(`Unsupported platform: ${platformKey}`);
  }
  
  return platform;
}
```

### 2. Binary Resolution Logic

Create `src/install.ts` with fallback strategy:

```typescript
export async function resolveTerraformBinary(): Promise<string> {
  const { pkg, subpath } = getPlatformPackage();
  
  try {
    // Primary: Use platform package binary
    return require.resolve(`${pkg}/${subpath}`);
  } catch (error) {
    console.warn(`Platform package ${pkg} not found, falling back to download`);
    
    // Fallback: Current download logic
    return await downloadAndCacheTerraform();
  }
}
```

### 3. Main Package Updates

Update `package.json`:

```json
{
  "name": "@jahed/terraform",
  "scripts": {
    "postinstall": "node install.js"
  },
  "optionalDependencies": {
    "@jahed/terraform-darwin-arm64": "1.13.1",
    "@jahed/terraform-darwin-x64": "1.13.1",
    "@jahed/terraform-linux-arm64": "1.13.1", 
    "@jahed/terraform-linux-x64": "1.13.1",
    "@jahed/terraform-win32-arm64": "1.13.1",
    "@jahed/terraform-win32-x64": "1.13.1",
    "@jahed/terraform-freebsd-x64": "1.13.1",
    "@jahed/terraform-openbsd-x64": "1.13.1",
    "@jahed/terraform-solaris-x64": "1.13.1"
  }
}
```

### 4. Platform Package Structure

Each platform package follows this template:

**`@jahed/terraform-darwin-arm64/package.json`:**
```json
{
  "name": "@jahed/terraform-darwin-arm64",
  "version": "1.13.1",
  "description": "Terraform binary for macOS ARM64",
  "repository": "https://github.com/jahed/node-terraform",
  "license": "MIT",
  "os": ["darwin"],
  "cpu": ["arm64"],
  "files": ["bin"]
}
```

**Directory structure:**
```
@jahed/terraform-darwin-arm64/
├── package.json
├── README.md
└── bin/
    └── terraform (binary executable)
```

### 5. CLI Updates

Update `src/cli.ts` to use new resolution:

```typescript
const cli = async () => {
  const args = process.argv.slice(2);
  
  // New: Use install-time resolved binary
  const terraformPath = await resolveTerraformBinary();
  
  const terraform = spawn(terraformPath, args, {
    stdio: [process.stdin, process.stdout, process.stderr],
  });

  terraform.on("close", (code) => process.exit(code || undefined));
};
```

## Platform Support Matrix

| Platform | Architecture | Package Name | Binary Path |
|----------|-------------|--------------|-------------|
| macOS | ARM64 | `@jahed/terraform-darwin-arm64` | `bin/terraform` |
| macOS | x64 | `@jahed/terraform-darwin-x64` | `bin/terraform` |
| Linux | ARM64 | `@jahed/terraform-linux-arm64` | `bin/terraform` |
| Linux | x64 | `@jahed/terraform-linux-x64` | `bin/terraform` |
| Windows | ARM64 | `@jahed/terraform-win32-arm64` | `terraform.exe` |
| Windows | x64 | `@jahed/terraform-win32-x64` | `terraform.exe` |
| FreeBSD | x64 | `@jahed/terraform-freebsd-x64` | `bin/terraform` |
| OpenBSD | x64 | `@jahed/terraform-openbsd-x64` | `bin/terraform` |
| Solaris | x64 | `@jahed/terraform-solaris-x64` | `bin/terraform` |

## Build & Release Automation

### 1. GitHub Workflows Updates

**`.github/workflows/build-platform-packages.yml`:**
```yaml
name: Build Platform Packages

on:
  workflow_dispatch:
    inputs:
      terraform_version:
        description: 'Terraform version to package'
        required: true
        type: string

jobs:
  build-packages:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        include:
          - platform: darwin
            arch: arm64
            terraform_arch: darwin_arm64
          - platform: darwin  
            arch: x64
            terraform_arch: darwin_amd64
          - platform: linux
            arch: x64
            terraform_arch: linux_amd64
          - platform: win32
            arch: x64
            terraform_arch: windows_amd64
          # ... additional platforms
            
    steps:
      - uses: actions/checkout@v4
      
      - name: Download Terraform Binary
        run: |
          wget https://releases.hashicorp.com/terraform/${{ inputs.terraform_version }}/terraform_${{ inputs.terraform_version }}_${{ matrix.terraform_arch }}.zip
          unzip terraform_${{ inputs.terraform_version }}_${{ matrix.terraform_arch }}.zip
          
      - name: Create Platform Package
        run: |
          mkdir -p platform-packages/@jahed/terraform-${{ matrix.platform }}-${{ matrix.arch }}
          cd platform-packages/@jahed/terraform-${{ matrix.platform }}-${{ matrix.arch }}
          
          # Create package.json
          cat > package.json << EOF
          {
            "name": "@jahed/terraform-${{ matrix.platform }}-${{ matrix.arch }}",
            "version": "${{ inputs.terraform_version }}",
            "description": "Terraform binary for ${{ matrix.platform }} ${{ matrix.arch }}",
            "repository": "https://github.com/jahed/node-terraform",
            "license": "MIT",
            "os": ["${{ matrix.platform }}"],
            "cpu": ["${{ matrix.arch }}"],
            "files": ["bin"]
          }
          EOF
          
          # Copy binary
          mkdir -p bin
          cp ../../../terraform${{ matrix.platform == 'win32' && '.exe' || '' }} bin/
          chmod +x bin/terraform${{ matrix.platform == 'win32' && '.exe' || '' }}
          
      - name: Publish Platform Package
        run: |
          cd platform-packages/@jahed/terraform-${{ matrix.platform }}-${{ matrix.arch }}
          npm publish
        env:
          NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
```

**`.github/workflows/release.yml`:**
```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build-platform-packages:
    uses: ./.github/workflows/build-platform-packages.yml
    with:
      terraform_version: ${{ github.ref_name }}
    secrets: inherit
    
  publish-main-package:
    needs: build-platform-packages
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
      
      - name: Update optionalDependencies
        run: |
          # Script to update package.json with new platform package versions
          node scripts/update-optional-deps.js ${{ github.ref_name }}
          
      - name: Build and Publish
        run: |
          npm ci
          npm run build
          npm publish
        env:
          NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
```

### 2. Version Synchronization Script

Create `scripts/update-optional-deps.js`:

```javascript
const fs = require('fs');
const path = require('path');

const version = process.argv[2];
const packageJsonPath = path.join(__dirname, '../package.json');
const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));

// Update all optionalDependencies to new version
Object.keys(packageJson.optionalDependencies || {}).forEach(dep => {
  if (dep.startsWith('@jahed/terraform-')) {
    packageJson.optionalDependencies[dep] = version;
  }
});

fs.writeFileSync(packageJsonPath, JSON.stringify(packageJson, null, 2));
console.log(`Updated optionalDependencies to version ${version}`);
```

### 3. Terraform Version Tracking

Create `scripts/check-terraform-updates.js` for automated updates:

```javascript
// Monitor HashiCorp releases API
// Create PRs when new Terraform versions are available
// Trigger platform package builds automatically
```

## Migration Strategy

### Phase 1: Dual Support (1-2 releases)
- Implement new platform package system alongside existing download logic
- Default to platform packages, fallback to downloads
- Monitor adoption and identify issues

### Phase 2: Platform Package Priority (2-3 releases)  
- Prioritize platform packages over downloads
- Add deprecation warnings for download fallback
- Gather performance metrics

### Phase 3: Full Migration (Future release)
- Remove download fallback logic
- Platform packages become the only installation method
- Update documentation and examples

### Backward Compatibility
- Support `--no-optional` flag scenarios via download fallback
- Maintain existing CLI interface and behavior
- Preserve environment variable overrides (`TERRAFORM_VERSION`, etc.)

## Testing Strategy

### Unit Tests
- Platform detection logic
- Binary resolution with mocked platform packages
- Fallback scenarios when platform packages unavailable

### Integration Tests
- Install testing across all supported platforms
- `--no-optional` flag behavior verification
- Offline execution testing

### End-to-End Tests
- Full workflow testing in GitHub Actions
- Docker container testing (common CI/CD scenario)
- Cross-platform compatibility validation

## Success Metrics

### Performance Improvements
- **Cold Start Time**: Measure first execution latency reduction
- **Install Time**: Compare total installation time vs. current approach
- **Network Requests**: Eliminate runtime HTTP requests

### Reliability Metrics
- **Offline Success Rate**: Percentage of successful offline executions
- **Install Failure Rate**: Platform package resolution success rate
- **CI/CD Performance**: Build time improvements in containerized environments

### Adoption Metrics  
- **Download vs Platform Package Usage**: Track resolution method usage
- **Platform Coverage**: Verify all supported platforms work correctly
- **User Feedback**: Monitor issues and feature requests

## Risk Assessment

### High Risk
- **Package Publishing Complexity**: Multiple packages increase release overhead
- **Version Synchronization**: Keeping all platform packages in sync
- **npm Registry Dependencies**: Reliance on optional dependency resolution

### Medium Risk
- **Binary Size Impact**: Larger total installation footprint
- **Platform Support Matrix**: Maintaining binaries for all Terraform platforms
- **Migration Complexity**: User adaptation to new installation behavior

### Low Risk
- **API Compatibility**: CLI interface remains unchanged
- **Fallback Reliability**: Existing download logic preserved as backup
- **Testing Coverage**: Comprehensive test strategy mitigates issues

## Timeline

### Week 1-2: Foundation
- Implement platform detection module
- Create binary resolution logic
- Update main package structure

### Week 3-4: Platform Packages
- Create platform package templates
- Implement build automation
- Test package generation process

### Week 5-6: CI/CD Integration
- Update GitHub workflows
- Implement version synchronization
- Test end-to-end release process

### Week 7-8: Testing & Documentation
- Comprehensive testing across platforms
- Update README and documentation
- Prepare migration guide

### Week 9: Release
- Deploy Phase 1 (dual support)
- Monitor adoption and performance
- Gather user feedback

## Conclusion

Converting to esbuild-style platform packages will significantly improve node-terraform's user experience through faster execution, offline support, and better CI/CD integration. The phased migration approach ensures backward compatibility while providing a clear path to the new architecture.

The implementation leverages proven patterns from esbuild's ecosystem while maintaining node-terraform's existing API surface and user expectations.