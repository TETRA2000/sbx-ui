# Welcome to sbx-ui

This guide will help you get up and running with sbx-ui development.

## What is sbx-ui?

sbx-ui is a native macOS desktop GUI and Linux CLI tool for managing Docker Sandboxes (`sbx`). It provides a visual interface for sandbox lifecycle management, network policies, port forwarding, environment variables, and embedded terminal sessions - all without requiring terminal interaction.

### Key Features

- **Sandbox Management**: Create, stop, and terminate sandboxes with a click
- **Network Policies**: Global allow/deny rules with activity logging
- **Port Forwarding**: Easy host-to-sandbox port mapping
- **Environment Variables**: Persistent per-sandbox configuration
- **Terminal Sessions**: Embedded agent and shell sessions (powered by SwiftTerm)
- **Linux CLI**: Full feature parity from the command line
- **Testing**: Mock CLI for development without Docker

## Quick Start

### 5-Minute Setup

**macOS GUI:**
```bash
# 1. Clone the repository
git clone https://github.com/TETRA2000/sbx-ui.git
cd sbx-ui

# 2. Open in Xcode
open sbx-ui.xcodeproj

# 3. Configure mock CLI (no Docker required)
# - Product → Scheme → Edit Scheme
# - Run → Arguments → Environment Variables:
#   - SBX_CLI_MOCK = 1
#   - PATH = <project-root>/tools:$PATH

# 4. Run the app
# Product → Run (Cmd+R)
```

**Linux CLI:**
```bash
# 1. Clone the repository
git clone https://github.com/TETRA2000/sbx-ui.git
cd sbx-ui

# 2. Build
swift build

# 3. Test
swift test

# 4. Run
swift run sbx-ui-cli ls
```

### Your First Contribution

1. **Read the documentation:**
   - `README.md` - Project overview and features
   - `CONTRIBUTING.md` - Contribution guidelines
   - `DEVELOPMENT.md` - Detailed development setup
   - `CLAUDE.md` - AI-assisted development workflow (if using Claude Code)

2. **Set up your environment:**
   - Follow the [Development Setup](#development-setup) section below
   - Run the tests to verify everything works

3. **Find something to work on:**
   - Check the [Issues](https://github.com/TETRA2000/sbx-ui/issues) page
   - Look for issues tagged `good first issue`
   - Or propose a new feature/fix

4. **Make your changes:**
   - Create a feature branch: `git checkout -b feature/your-feature`
   - Make your changes following the [Coding Guidelines](CONTRIBUTING.md#coding-guidelines)
   - Write tests for your changes
   - Commit and push: `git push origin feature/your-feature`

5. **Create a Pull Request:**
   - Go to GitHub and open a PR
   - Fill in the PR template
   - Wait for review and address feedback

## Development Setup

### Prerequisites

**macOS GUI:**
- macOS 14.0+
- Xcode 16+
- Docker Desktop with `sbx` CLI v0.23.0+ (or use the mock CLI)

**Linux CLI:**
- Linux (Ubuntu 22.04+)
- Swift 6.0+
- Docker with `sbx` CLI v0.23.0+ (or use the mock CLI)

### Detailed Setup Instructions

See [`DEVELOPMENT.md`](DEVELOPMENT.md) for comprehensive setup instructions, including:
- Project structure walkthrough
- Development environment configuration
- Building and running
- Testing strategies
- Debugging tips
- Common development tasks

## Project Architecture

sbx-ui has a layered architecture that shares code between the macOS GUI and Linux CLI:

```
┌─────────────────────────────────────────────────┐
│  macOS GUI (SwiftUI)     Linux CLI (ArgumentParser)  │
│         │                         │              │
│      Views                    Commands           │
│         │                         │              │
│      Stores                       │              │
│         │                         │              │
│         └─────────┬───────────────┘              │
│                   │                              │
│              SBXCore Library                     │
│         (Models + Services)                      │
│                   │                              │
│            SbxServiceProtocol                    │
│                   │                              │
│            RealSbxService                        │
│                   │                              │
│             CliExecutor                          │
│                   │                              │
│           sbx CLI / mock-sbx                     │
└─────────────────────────────────────────────────┘
```

**Key Layers:**

1. **SBXCore** - Shared library (Models + Services)
   - Used by both macOS GUI and Linux CLI
   - Built via Swift Package Manager
   - Contains domain types and service implementation

2. **Stores** - State management (macOS only)
   - `@MainActor @Observable` classes
   - Bridge between services and views

3. **Views** - UI layer (macOS only)
   - SwiftUI views organized by feature
   - Follows "The Technical Monolith" design system

4. **CLI** - Command-line interface (Linux)
   - Swift ArgumentParser commands
   - Calls SBXCore directly

See [`DEVELOPMENT.md`](DEVELOPMENT.md#project-structure) for detailed structure.

## Testing

sbx-ui has comprehensive test coverage:

- **73 tests** (macOS Xcode)
- **25 tests** (Linux SPM)
- **32 tests** (CLI mock)

All tests run using the **CLI mock** - no Docker required!

### Running Tests

**macOS (all tests):**
```bash
# In Xcode: Product → Test (Cmd+U)
```

**Linux (SPM tests):**
```bash
swift test
```

**CLI mock tests:**
```bash
bash tools/mock-sbx-tests.sh
```

### Test Structure

- **Unit tests**: Test stores and service logic with stubs
- **UI/E2E tests**: Test full user flows with CLI mock
- **Integration tests**: Test service layer against mock CLI

See `CLAUDE.md` → Testing Guide for detailed testing patterns.

## Key Concepts

### The CLI Mock

The `tools/mock-sbx` bash script emulates the Docker Sandbox CLI for development without Docker. It:
- Implements all `sbx` commands used by sbx-ui
- Stores state in JSON files
- Matches real CLI output formats
- Enables testing without Docker Desktop

**Using the mock:**
```bash
export SBX_MOCK_STATE_DIR=$(mktemp -d)
export PATH="$(pwd)/tools:$PATH"
sbx ls
```

See `docs/mock-sbx.md` for details.

### Main Actor Isolation

The Xcode project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which means:
- All types default to `@MainActor` unless opted out
- Explicit inits on `Sendable` types must be `nonisolated`
- Access properties from test context: `await store.property`

### Cross-Platform Code (SBXCore)

Code in `sbx-ui/Models/` and `sbx-ui/Services/` must work on both macOS and Linux:
- Use `#if canImport(os)` for macOS-only code
- Use `SBX_SPM` flag for SPM-specific code
- No SwiftUI or AppKit dependencies

## Common Tasks

### Adding a Feature

1. Update the service layer if needed (`SbxServiceProtocol`)
2. Add store logic for macOS GUI (`@MainActor @Observable`)
3. Create the view with accessibility identifiers
4. Write unit tests and UI tests
5. Update documentation

See [`DEVELOPMENT.md`](DEVELOPMENT.md#common-development-tasks) for step-by-step guides.

### Fixing a Bug

1. Write a failing test that reproduces the bug
2. Fix the bug
3. Verify the test passes
4. Run the full test suite
5. Commit with a clear message

### Improving Documentation

1. Identify what's unclear or missing
2. Update the relevant file (README, CONTRIBUTING, DEVELOPMENT, docs/)
3. Test any code examples
4. Submit a PR

## Getting Help

### Documentation

- **README.md** - Project overview, features, basic usage
- **CONTRIBUTING.md** - How to contribute
- **DEVELOPMENT.md** - Detailed development guide
- **CLAUDE.md** - AI-assisted development (Claude Code)
- **docs/** - Specialized documentation (CLI, mock, plugins)

### Community

- **GitHub Issues** - Bug reports and feature requests
- **GitHub Discussions** - Questions and general discussion
- **Pull Requests** - Code review and feedback

### Claude Code Users

If you're using Claude Code for development, check out:
- `CLAUDE.md` - Full AI development workflow
- `.kiro/` - Kiro Spec-Driven Development setup
- `/kiro:*` commands - Spec workflow commands

The project uses:
- `/kiro:spec-design` - Create technical designs
- `/kiro:spec-impl` - TDD implementation
- `/kiro:validate-design` - Design review
- Xcode MCP server - Build, run, test from Claude

## What's Next?

1. **Explore the codebase:**
   - Start with `sbx-ui/sbx_uiApp.swift` (entry point)
   - Look at `sbx-ui/Views/Dashboard/` for UI examples
   - Check `sbx-ui/Services/` for the core logic

2. **Run the app:**
   - Build and run in Xcode (Cmd+R)
   - Create a test sandbox
   - Explore the features

3. **Run the tests:**
   - Run all tests in Xcode (Cmd+U)
   - Check the test files to understand patterns
   - Try writing a simple test

4. **Pick an issue:**
   - Find a `good first issue` on GitHub
   - Or fix something that bothers you
   - Ask questions if stuck

5. **Make your first PR:**
   - Even a small improvement helps!
   - Documentation fixes are always welcome
   - Tests make great first contributions

---

**Welcome aboard!** We're excited to have you contributing to sbx-ui. Don't hesitate to ask questions - the community is here to help. 🚀
