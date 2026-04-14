# Development Guide

This guide covers detailed setup and development workflows for sbx-ui.

## Table of Contents

- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Development Setup](#development-setup)
- [Building and Running](#building-and-running)
- [Testing](#testing)
- [Debugging](#debugging)
- [Common Development Tasks](#common-development-tasks)
- [Troubleshooting](#troubleshooting)

## Quick Start

**macOS GUI Development:**
```bash
git clone https://github.com/TETRA2000/sbx-ui.git
cd sbx-ui
open sbx-ui.xcodeproj
# Configure mock CLI in scheme (see Development Setup)
# Product → Run (Cmd+R)
```

**Linux CLI Development:**
```bash
git clone https://github.com/TETRA2000/sbx-ui.git
cd sbx-ui
swift build
swift test
swift run sbx-ui-cli ls
```

## Project Structure

```
sbx-ui/
├── sbx-ui/                          # macOS GUI application
│   ├── sbx_uiApp.swift              # App entry point
│   ├── Models/                      # Domain models (shared with SPM)
│   │   └── DomainTypes.swift        # Sandbox, PolicyRule, PortMapping, etc.
│   ├── Services/                    # Service layer (shared with SPM)
│   │   ├── SbxServiceProtocol.swift # Service protocol
│   │   ├── RealSbxService.swift     # CLI-backed implementation
│   │   ├── CliExecutor.swift        # Process spawning
│   │   ├── SbxOutputParser.swift    # CLI output parsing
│   │   ├── ServiceFactory.swift     # Service creation
│   │   └── LinuxShims.swift         # Linux compatibility stubs
│   ├── Stores/                      # SwiftUI state management (macOS only)
│   │   ├── SandboxStore.swift       # Sandbox lifecycle
│   │   ├── PolicyStore.swift        # Network policies
│   │   ├── EnvVarStore.swift        # Environment variables
│   │   ├── TerminalSessionStore.swift # Terminal sessions
│   │   └── SettingsStore.swift      # User settings
│   ├── Views/                       # SwiftUI views (macOS only)
│   │   ├── Dashboard/               # Sandbox grid, creation
│   │   ├── Policies/                # Policy management
│   │   ├── Ports/                   # Port forwarding
│   │   ├── EnvVars/                 # Environment variables
│   │   ├── Session/                 # Terminal sessions
│   │   └── Error/                   # Error states, debug log
│   ├── DesignSystem/                # UI theme (macOS only)
│   └── Plugins/                     # Plugin system (macOS only)
│
├── Sources/                         # SPM source root
│   └── sbx-ui-cli/                  # Linux CLI executable
│       ├── CLI.swift                # Entry point
│       ├── Commands.swift           # Sandbox commands
│       ├── PolicyCommands.swift     # Policy commands
│       ├── PortsCommands.swift      # Port commands
│       ├── EnvCommands.swift        # Environment variable commands
│       └── Formatting.swift         # ANSI table output
│
├── Tests/                           # SPM tests
│   └── SBXCoreTests/
│       └── SBXCoreTests.swift       # 25 tests (models, parsers, integration)
│
├── sbx-uiTests/                     # Xcode unit tests
│   └── sbx_uiTests.swift            # Swift Testing tests
│
├── sbx-uiUITests/                   # Xcode UI/E2E tests
│   └── sbx_uiUITests.swift          # XCTest UI tests
│
├── tools/                           # Development tools
│   ├── mock-sbx                     # CLI mock (bash)
│   └── mock-sbx-tests.sh            # CLI mock test suite (32 tests)
│
├── docs/                            # Documentation
│   ├── sbx-cli-reference.md         # Docker Sandbox CLI reference
│   ├── mock-sbx.md                  # CLI mock documentation
│   ├── linux-cli.md                 # Linux CLI reference
│   └── plugin-development.md        # Plugin development guide
│
├── Package.swift                    # SPM manifest
└── sbx-ui.xcodeproj                 # Xcode project
```

### Architecture Layers

1. **Models** (`sbx-ui/Models/`)
   - Domain types: `Sandbox`, `PolicyRule`, `PortMapping`, `EnvVar`
   - Shared between macOS GUI and Linux CLI (part of SBXCore)

2. **Services** (`sbx-ui/Services/`)
   - `SbxServiceProtocol`: Contract for all operations
   - `RealSbxService`: Production implementation (calls `sbx` CLI)
   - `CliExecutor`: Process spawning and output capture
   - `SbxOutputParser`: JSON/text output parsing
   - Part of SBXCore, shared with Linux CLI

3. **Stores** (`sbx-ui/Stores/`)
   - `@MainActor @Observable` classes
   - Bridge between Services and Views
   - macOS GUI only

4. **Views** (`sbx-ui/Views/`)
   - SwiftUI views organized by feature
   - macOS GUI only

5. **CLI** (`Sources/sbx-ui-cli/`)
   - ArgumentParser commands
   - Calls SBXCore directly
   - Linux CLI only

## Development Setup

### macOS GUI Setup

1. **Open the project:**
   ```bash
   open sbx-ui.xcodeproj
   ```

2. **Configure the scheme for development without Docker:**
   - Product → Scheme → Edit Scheme (or Cmd+<)
   - Select "Run" in the left sidebar
   - Go to "Arguments" tab
   - Under "Environment Variables", add:
     - **Name**: `SBX_CLI_MOCK`
       **Value**: `1`
     - **Name**: `PATH`
       **Value**: `/path/to/sbx-ui/tools:$PATH`
       (Replace `/path/to/sbx-ui` with your actual project path)

3. **Verify the configuration:**
   - Product → Run (Cmd+R)
   - The app should launch and you should be able to create sandboxes
   - Sandboxes will be managed by the mock CLI (no Docker required)

### Linux CLI Setup

1. **Install Swift 6.0+ on Linux:**

   **Ubuntu 22.04:**
   ```bash
   wget https://download.swift.org/swift-6.0-release/ubuntu2204/swift-6.0-RELEASE/swift-6.0-RELEASE-ubuntu22.04.tar.gz
   tar xzf swift-6.0-RELEASE-ubuntu22.04.tar.gz
   sudo mv swift-6.0-RELEASE-ubuntu22.04 /usr/share/swift
   echo 'export PATH=/usr/share/swift/usr/bin:$PATH' >> ~/.bashrc
   source ~/.bashrc
   ```

2. **Build the CLI:**
   ```bash
   swift build
   ```

3. **Run the CLI:**
   ```bash
   swift run sbx-ui-cli ls
   ```

4. **Install (optional):**
   ```bash
   swift build -c release
   cp .build/release/sbx-ui-cli /usr/local/bin/sbx-ui
   ```

### Using the CLI Mock

The CLI mock (`tools/mock-sbx`) emulates the Docker Sandbox CLI for development and testing without Docker.

**Standalone use:**
```bash
export SBX_MOCK_STATE_DIR=$(mktemp -d)
export PATH="$(pwd)/tools:$PATH"
sbx ls
sbx run claude /tmp/test-project --name test
```

**With the Linux CLI:**
```bash
export SBX_MOCK_STATE_DIR=$(mktemp -d)
export PATH="$(pwd)/tools:$PATH"
swift run sbx-ui-cli ls
swift run sbx-ui-cli create /tmp/project --name test
```

See `docs/mock-sbx.md` for full documentation.

## Building and Running

### macOS GUI

**Build:**
```bash
# In Xcode: Product → Build (Cmd+B)
```

**Run:**
```bash
# In Xcode: Product → Run (Cmd+R)
```

**Clean build:**
```bash
# In Xcode: Product → Clean Build Folder (Shift+Cmd+K)
```

### Linux CLI

**Debug build:**
```bash
swift build
.build/debug/sbx-ui-cli --help
```

**Release build:**
```bash
swift build -c release
.build/release/sbx-ui-cli --help
```

**Run without building:**
```bash
swift run sbx-ui-cli ls
```

## Testing

### Running All Tests

**macOS (Xcode):**
```bash
# Product → Test (Cmd+U)
# Runs all 73 unit + UI tests
```

**Linux (SPM):**
```bash
swift test
# Runs 25 SBXCore tests
```

**CLI Mock:**
```bash
bash tools/mock-sbx-tests.sh
# Runs 32 bash tests
```

### Running Specific Tests

**Xcode (macOS):**
- Click the diamond icon next to a test in the source file
- Or: Product → Test (Cmd+U) with a test file open

**SPM:**
```bash
swift test --filter SandboxValidationTests
```

### Test Structure

**Unit Tests** (`sbx-uiTests/sbx_uiTests.swift`):
- Swift Testing framework (`@Test`, `#expect`)
- Test stores and service logic
- Pattern: Create test struct, inject `StubSbxService`

**UI/E2E Tests** (`sbx-uiUITests/sbx_uiUITests.swift`):
- XCTest framework
- Launch app with `SBX_CLI_MOCK=1`
- Test full user flows

**SPM Tests** (`Tests/SBXCoreTests/SBXCoreTests.swift`):
- Swift Testing framework
- Test models, parsers, service layer
- Integration tests with `mock-sbx`

See `CLAUDE.md` → Testing Guide for detailed patterns and examples.

## Debugging

### macOS GUI Debugging

**Xcode Debugger:**
- Set breakpoints by clicking the line number gutter
- Product → Run (Cmd+R) with breakpoints set
- Use `po` (print object) in the debugger console

**View Hierarchy:**
- Debug → View Debugging → Capture View Hierarchy (while app is running)

**Debug Log:**
- The app includes a built-in debug log panel
- Open from the sidebar to see CLI commands and output

**Console Logs:**
- Window → Devices and Simulators → Your Mac → Console
- Filter by "sbx-ui" to see app logs

### Linux CLI Debugging

**Print debugging:**
```swift
print("Debug: \(value)", to: &standardError)
```

**LLDB:**
```bash
swift build
lldb .build/debug/sbx-ui-cli
(lldb) run ls
```

**Verbose output:**
```bash
# Add logging to CliExecutor.swift
swift run sbx-ui-cli ls 2>&1 | cat
```

### Common Debugging Scenarios

**"Sandbox not found" errors:**
- Check `$SBX_MOCK_STATE_DIR` if using mock
- Inspect `$SBX_MOCK_STATE_DIR/sandboxes/*.json`

**Tests timing out:**
- Increase timeout in UI tests (default: 5-10s for mock CLI)
- Check that `PATH` includes `tools/` directory

**Port conflicts:**
- Check for existing port mappings: `sbx ports <name> --json`
- Or inspect `$SBX_MOCK_STATE_DIR/ports/<name>.json`

## Common Development Tasks

### Adding a New View Feature (macOS)

1. **Create the view file:**
   ```bash
   touch sbx-ui/Views/MyFeature/MyFeatureView.swift
   ```

2. **Add to Xcode project:**
   - Right-click on `Views/` in Xcode
   - Add Files to "sbx-ui"
   - Select your new file

3. **Create the view:**
   ```swift
   import SwiftUI

   struct MyFeatureView: View {
       @Environment(SandboxStore.self) private var sandboxStore

       var body: some View {
           Text("My Feature")
       }
   }
   ```

4. **Add accessibility identifiers:**
   ```swift
   Button("Action") { }
       .accessibilityIdentifier("myFeatureButton")
   ```

5. **Write UI tests:**
   ```swift
   func testMyFeature() {
       app.buttons["myFeatureButton"].tap()
       XCTAssertTrue(app.staticTexts["Expected Text"].exists)
   }
   ```

### Adding a New Service Method

1. **Add to protocol:**
   ```swift
   // sbx-ui/Services/SbxServiceProtocol.swift
   protocol SbxServiceProtocol {
       func myNewOperation(name: String) async throws -> MyResult
   }
   ```

2. **Implement in RealSbxService:**
   ```swift
   // sbx-ui/Services/RealSbxService.swift
   func myNewOperation(name: String) async throws -> MyResult {
       let output = try await executor.execute(
           args: ["my-command", name]
       )
       return try parser.parseMyResult(output)
   }
   ```

3. **Add parsing logic:**
   ```swift
   // sbx-ui/Services/SbxOutputParser.swift
   func parseMyResult(_ output: String) throws -> MyResult {
       // Parse output
   }
   ```

4. **Add to StubSbxService for tests:**
   ```swift
   // sbx-uiTests/sbx_uiTests.swift
   actor StubSbxService: SbxServiceProtocol {
       func myNewOperation(name: String) async throws -> MyResult {
           MyResult(...)
       }
   }
   ```

5. **Write tests:**
   ```swift
   @Test func myNewOperationSucceeds() async throws {
       let service = StubSbxService()
       let result = try await service.myNewOperation(name: "test")
       #expect(result.isValid)
   }
   ```

### Adding a New CLI Command (Linux)

1. **Create command struct:**
   ```swift
   // Sources/sbx-ui-cli/MyCommands.swift
   import ArgumentParser

   struct MyCommand: AsyncParsableCommand {
       static let configuration = CommandConfiguration(
           commandName: "my-command",
           abstract: "Description of command"
       )

       @Argument(help: "Required argument")
       var name: String

       @Flag(help: "Optional flag")
       var verbose = false

       func run() async throws {
           let service = await ServiceFactory.createService()
           let result = try await service.myOperation(name: name)
           print(result)
       }
   }
   ```

2. **Register in CLI.swift:**
   ```swift
   @main
   struct CLI: AsyncParsableCommand {
       static let configuration = CommandConfiguration(
           subcommands: [
               // ... existing commands
               MyCommand.self,
           ]
       )
   }
   ```

3. **Add formatting (optional):**
   ```swift
   // Sources/sbx-ui-cli/Formatting.swift
   func formatMyResult(_ result: MyResult) -> String {
       // ANSI colored output
   }
   ```

4. **Test:**
   ```bash
   swift run sbx-ui-cli my-command test-name
   ```

### Updating Dependencies

**SPM dependencies** (Package.swift):
```bash
swift package update
swift build
```

**Xcode dependencies** (SwiftTerm, etc.):
- File → Packages → Update to Latest Package Versions

## Troubleshooting

### Build Errors

**"No such module 'SwiftTerm'"**
- File → Packages → Resolve Package Versions

**"MainActor isolation" errors**
- Remember: Project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- Mark explicit inits on `Sendable` types as `nonisolated`

**SPM build fails on macOS**
- Ensure `SBXCore` doesn't include View/Store code
- Check `#if canImport(os)` guards for platform-specific code

### Test Failures

**UI tests can't find elements**
- Check accessibility identifiers are set
- Use `app.buttons["id"]`, not `app.groups["id"]` for VStacks
- Increase timeout for CLI mock: `waitForExistence(timeout: 10)`

**Tests pass locally but fail in CI**
- Check environment variables are set in GitHub Actions workflow
- Ensure `tools/mock-sbx` has execute permissions

**Flaky tests**
- See `CLAUDE.md` → Development Rules for common causes
- Never delete flaky tests - find and fix the root cause

### Runtime Issues

**"Command not found: sbx"**
- Check `PATH` includes `tools/` for mock CLI
- Or install real Docker Sandbox CLI

**App hangs on sandbox creation**
- Check that `SBX_CLI_MOCK=1` is set
- Verify `tools/mock-sbx` is executable: `chmod +x tools/mock-sbx`

**Port already in use**
- Check existing port mappings: `sbx ports <name> --json`
- Stop other processes using the port: `lsof -i :8080`

### Getting Help

- Check existing issues: https://github.com/TETRA2000/sbx-ui/issues
- Open a new issue with:
  - Environment details (OS, Xcode/Swift version)
  - Steps to reproduce
  - Expected vs actual behavior
  - Relevant logs/errors

---

Happy coding! 🚀
