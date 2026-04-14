# Quick Start Guide

Get up and running with sbx-ui in 5 minutes.

## For Users

### macOS GUI

**Requirements**: macOS 14.0+, Docker Desktop with `sbx` CLI v0.23.0+

**Install**:
1. Download the latest release from [Releases](https://github.com/TETRA2000/sbx-ui/releases)
2. Open the `.dmg` and drag sbx-ui to Applications
3. Launch sbx-ui

**First Steps**:
1. Click "Deploy Agent" to create your first sandbox
2. Select a workspace directory (your project folder)
3. Enter a sandbox name (lowercase, alphanumeric with hyphens)
4. Click "Deploy" to create and start the sandbox
5. The sandbox appears in the dashboard - click to open a terminal session

### Linux CLI

**Requirements**: Linux (Ubuntu 22.04+), Swift 6.0+, Docker with `sbx` CLI v0.23.0+

**Install**:
```bash
# Download binary from releases
wget https://github.com/TETRA2000/sbx-ui/releases/latest/download/sbx-ui-cli-linux
chmod +x sbx-ui-cli-linux
sudo mv sbx-ui-cli-linux /usr/local/bin/sbx-ui
```

**Quick Commands**:
```bash
# List sandboxes
sbx-ui ls

# Create a sandbox
sbx-ui create /path/to/project --name my-sandbox

# Show status
sbx-ui status my-sandbox

# Manage ports
sbx-ui ports publish my-sandbox 8080:3000

# Set environment variables
sbx-ui env set my-sandbox API_KEY secret123

# Network policies
sbx-ui policy allow example.com
sbx-ui policy log --blocked

# JSON output
sbx-ui --json ls
```

See [docs/linux-cli.md](docs/linux-cli.md) for full reference.

---

## For Developers

### macOS GUI Development

**Requirements**: macOS 14.0+, Xcode 16+

**Setup** (no Docker required):
```bash
# 1. Clone
git clone https://github.com/TETRA2000/sbx-ui.git
cd sbx-ui

# 2. Open in Xcode
open sbx-ui.xcodeproj

# 3. Configure mock CLI
# Product → Scheme → Edit Scheme
# Run → Arguments → Environment Variables:
#   - SBX_CLI_MOCK = 1
#   - PATH = <project-root>/tools:$PATH

# 4. Run
# Product → Run (Cmd+R)

# 5. Test
# Product → Test (Cmd+U)
```

### Linux CLI Development

**Requirements**: Swift 6.0+

**Setup**:
```bash
# 1. Clone
git clone https://github.com/TETRA2000/sbx-ui.git
cd sbx-ui

# 2. Build
swift build

# 3. Test
swift test

# 4. Run
swift run sbx-ui-cli ls

# 5. Install (optional)
swift build -c release
cp .build/release/sbx-ui-cli /usr/local/bin/sbx-ui
```

### Your First Contribution

**5-minute workflow**:
```bash
# 1. Find an issue
# Browse: https://github.com/TETRA2000/sbx-ui/issues
# Look for: "good first issue" label

# 2. Create a branch
git checkout -b feature/your-feature

# 3. Make changes
# - Follow coding guidelines in CONTRIBUTING.md
# - Write tests for your changes
# - Update documentation

# 4. Test
# macOS: Product → Test (Cmd+U)
# Linux: swift test

# 5. Commit and push
git add .
git commit -m "Brief description of changes"
git push origin feature/your-feature

# 6. Create PR
# Go to GitHub and open a pull request
```

### Development Resources

| Resource | Description |
|----------|-------------|
| [ONBOARDING.md](ONBOARDING.md) | **Start here** - Developer onboarding guide |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution guidelines, coding standards |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Detailed development setup, common tasks |
| [CLAUDE.md](CLAUDE.md) | AI-assisted development with Claude Code |
| [docs/TESTING.md](docs/TESTING.md) | Comprehensive testing guide |

### Key Concepts

**CLI Mock**: Development without Docker
```bash
export SBX_MOCK_STATE_DIR=$(mktemp -d)
export PATH="$(pwd)/tools:$PATH"
sbx ls  # Uses mock CLI
```

**Main Actor Isolation**: Project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- Access store properties from tests: `await store.property`
- Mark inits on `Sendable` types as `nonisolated`

**Cross-Platform Code**: SBXCore works on macOS and Linux
- Use `#if canImport(os)` for platform-specific code
- No SwiftUI in Models/Services

### Common Tasks

**Add a new view feature**:
1. Create view file in `sbx-ui/Views/MyFeature/`
2. Add accessibility identifiers: `.accessibilityIdentifier("myButton")`
3. Write UI test: `app.buttons["myButton"].click()`
4. Update documentation

**Add a service method**:
1. Add to `SbxServiceProtocol`
2. Implement in `RealSbxService`
3. Add parsing in `SbxOutputParser`
4. Add to `StubSbxService` for tests
5. Write tests

**Add a CLI command**:
1. Create command struct in `Sources/sbx-ui-cli/`
2. Register in `CLI.swift` subcommands
3. Add formatting (optional)
4. Test: `swift run sbx-ui-cli my-command`

See [DEVELOPMENT.md](DEVELOPMENT.md#common-development-tasks) for detailed guides.

### Testing

**Run all tests**:
```bash
# macOS (Xcode): Product → Test (Cmd+U)
# Linux (SPM): swift test
# CLI mock: bash tools/mock-sbx-tests.sh
```

**Test structure**:
- 73 tests (macOS Xcode) - Unit + UI/E2E
- 25 tests (Linux SPM) - Models, parsers, integration
- 32 tests (CLI mock) - Bash test suite

All tests use the CLI mock - **no Docker required!**

See [docs/TESTING.md](docs/TESTING.md) for comprehensive testing guide.

### Getting Help

- **Questions?** [GitHub Discussions](https://github.com/TETRA2000/sbx-ui/discussions)
- **Bug reports?** [GitHub Issues](https://github.com/TETRA2000/sbx-ui/issues)
- **Feature requests?** [GitHub Issues](https://github.com/TETRA2000/sbx-ui/issues)

---

**Next Steps**:
- Read [ONBOARDING.md](ONBOARDING.md) for detailed onboarding
- Check [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines
- Explore [DEVELOPMENT.md](DEVELOPMENT.md) for development workflows
- Browse [docs/](docs/) for specialized documentation

Happy coding! 🚀
