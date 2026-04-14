# Contributing to sbx-ui

Thank you for your interest in contributing to sbx-ui! This guide will help you get started.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Pull Request Process](#pull-request-process)
- [Coding Guidelines](#coding-guidelines)
- [Testing Requirements](#testing-requirements)
- [Documentation](#documentation)

## Code of Conduct

This project follows standard open-source conduct guidelines. Be respectful, collaborative, and constructive in all interactions.

## Getting Started

### Prerequisites

**For macOS GUI development:**
- macOS 14.0+
- Xcode 16+
- Docker Desktop with `sbx` CLI (v0.23.0+)

**For Linux CLI development:**
- Linux (Ubuntu 22.04+)
- Swift 6.0+
- Docker with `sbx` CLI (v0.23.0+)

### Initial Setup

1. **Fork and clone the repository:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/sbx-ui.git
   cd sbx-ui
   ```

2. **Set up development environment:**

   **macOS (Xcode):**
   ```bash
   open sbx-ui.xcodeproj
   ```

   Configure the mock CLI for development without Docker:
   - Product → Scheme → Edit Scheme
   - Run → Arguments → Environment Variables:
     - `SBX_CLI_MOCK` = `1`
     - `PATH` = `<project-root>/tools:$PATH`

   **Linux (SPM):**
   ```bash
   swift build
   swift test
   ```

3. **Verify the setup:**

   **macOS:**
   ```bash
   # In Xcode: Product → Test (Cmd+U)
   # Should run all 73 tests
   ```

   **Linux:**
   ```bash
   swift test  # Runs 25 SBXCore tests
   bash tools/mock-sbx-tests.sh  # Runs 32 CLI mock tests
   ```

## Development Workflow

### Branch Naming

Use descriptive branch names with prefixes:
- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation updates
- `refactor/` - Code refactoring
- `test/` - Test improvements

Example: `feature/add-session-persistence`

### Making Changes

1. **Create a new branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes:**
   - Follow the [Coding Guidelines](#coding-guidelines)
   - Write tests for new functionality
   - Update documentation as needed

3. **Run tests:**
   ```bash
   # macOS (Xcode)
   # Product → Test (Cmd+U)

   # Linux (SPM)
   swift test

   # CLI mock tests
   bash tools/mock-sbx-tests.sh
   ```

4. **Commit your changes:**
   ```bash
   git add .
   git commit -m "Brief description of changes"
   ```

   Use clear, descriptive commit messages in imperative mood:
   - ✅ "Add session persistence to SandboxStore"
   - ✅ "Fix port forwarding validation error"
   - ❌ "Updated files"
   - ❌ "Fixed bug"

5. **Push to your fork:**
   ```bash
   git push origin feature/your-feature-name
   ```

## Pull Request Process

1. **Create a Pull Request:**
   - Go to your fork on GitHub
   - Click "Compare & pull request"
   - Fill in the PR template with:
     - Clear description of changes
     - Related issue number (if applicable)
     - Testing performed
     - Screenshots (for UI changes)

2. **PR Requirements:**
   - ✅ All tests pass (CI will verify)
   - ✅ Code follows style guidelines
   - ✅ New code includes tests
   - ✅ Documentation is updated
   - ✅ No merge conflicts

3. **Review Process:**
   - Address review feedback promptly
   - Update PR with requested changes
   - Re-request review after updates
   - Maintain a clean commit history

4. **Merging:**
   - PRs are merged by maintainers after approval
   - The branch will be deleted after merge

## Coding Guidelines

### Swift Style

- Follow Swift API Design Guidelines
- Use meaningful, descriptive names
- Prefer `let` over `var` when possible
- Use Swift concurrency (`async`/`await`, actors)
- Document public APIs with doc comments

### Architecture Patterns

**Service Layer:**
- All sandbox operations go through `SbxServiceProtocol`
- Use `RealSbxService` for production, stubs for testing

**Store Layer (macOS):**
- Stores are `@MainActor @Observable`
- Access from test context: `await store.property`
- No direct view access to services

**View Layer (macOS):**
- SwiftUI views organized by feature
- Use accessibility identifiers for UI testing
- Follow "The Technical Monolith" design system

**CLI Layer (Linux):**
- Swift ArgumentParser commands
- Call SBXCore services directly
- ANSI colored table output

### Key Constraints

- **Main Actor Isolation**: Project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
  - Explicit inits on `Sendable` types must be `nonisolated`
- **Cross-platform**: SBXCore code must work on both macOS and Linux
  - Use `#if canImport(os)` for platform-specific code
  - Use `SBX_SPM` flag for SPM-only code

### Common Patterns

**Accessing MainActor properties in tests:**
```swift
let count = await store.sandboxes.count  // Not: store.sandboxes.count
```

**Error handling:**
```swift
do {
    try await service.createSandbox(...)
} catch let error as SbxServiceError {
    // Handle specific error
}
```

## Testing Requirements

### Test Coverage

All code changes must include appropriate tests:
- **New features**: Unit tests + UI/E2E tests (if UI-related)
- **Bug fixes**: Regression test demonstrating the fix
- **Refactoring**: Ensure existing tests pass

### Test Structure

**Unit Tests** (`sbx-uiTests/sbx_uiTests.swift`):
- Swift Testing framework (`@Test`, `#expect`)
- Test stores and service logic
- Use `StubSbxService` and `FailingSbxService`

**UI/E2E Tests** (`sbx-uiUITests/sbx_uiUITests.swift`):
- XCTest framework
- Full user flow testing with CLI mock
- Set `SBX_CLI_MOCK=1` in environment

**SPM Tests** (`Tests/SBXCoreTests/SBXCoreTests.swift`):
- Swift Testing framework
- Cross-platform (macOS + Linux)
- Tests models, parsers, service integration

### Running Tests

**All tests (macOS):**
```bash
# Xcode: Product → Test (Cmd+U)
# Runs all 73 unit + UI tests
```

**SPM tests (Linux/macOS):**
```bash
swift test
# Runs 25 tests
```

**CLI mock tests:**
```bash
bash tools/mock-sbx-tests.sh
# Runs 32 bash tests
```

### Writing Good Tests

1. **Descriptive names**: `testCreateSandboxRefreshesStore()`
2. **Single responsibility**: One assertion per test when possible
3. **Use mocks**: CLI mock for integration, stubs for unit tests
4. **Async patterns**: Use `await` for MainActor access
5. **Timeouts**: Generous timeouts (5-10s) for UI tests

See `CLAUDE.md` → Testing Guide for detailed patterns and examples.

## Documentation

### When to Update Documentation

Update relevant documentation when you:
- Add a new feature
- Change existing behavior
- Add new CLI commands
- Modify architecture
- Add dependencies

### Documentation Files

- **README.md**: High-level overview, getting started, architecture
- **CLAUDE.md**: AI development workflow, testing patterns (for Claude Code)
- **CONTRIBUTING.md**: This file
- **docs/linux-cli.md**: Linux CLI reference
- **docs/mock-sbx.md**: CLI mock documentation
- **docs/plugin-development.md**: Plugin development guide
- **docs/sbx-cli-reference.md**: Docker Sandbox CLI reference

### Code Documentation

Use Swift doc comments for public APIs:
```swift
/// Creates a new sandbox with the specified configuration.
/// - Parameters:
///   - workspace: The workspace path to mount
///   - name: The sandbox name (lowercase alphanumeric with hyphens)
/// - Returns: The created sandbox
/// - Throws: `SbxServiceError` if creation fails
func createSandbox(workspace: String, name: String) async throws -> Sandbox
```

## Getting Help

- **Questions?** Open a GitHub Discussion
- **Bug reports?** Open a GitHub Issue with:
  - Steps to reproduce
  - Expected vs actual behavior
  - Environment (macOS version, Xcode version, etc.)
  - Error messages/logs
- **Feature requests?** Open a GitHub Issue describing the use case

## License

By contributing to sbx-ui, you agree that your contributions will be licensed under the same license as the project.

---

Thank you for contributing to sbx-ui! 🚀
