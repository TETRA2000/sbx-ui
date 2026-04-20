# Technology Stack

## Architecture

Layered architecture with a shared core. SwiftUI views (macOS) and ArgumentParser commands (Linux) both sit on top of `SBXCore`, which exposes a `SbxServiceProtocol` backed by a subprocess invocation of the `sbx` CLI (or the bash mock in tests).

```
SwiftUI Views (macOS)     CLI Commands (Linux)
       |                          |
   Stores (@MainActor @Observable)
       |                          |
       +--------- SBXCore --------+
                    |
             SbxServiceProtocol
                    |
       RealSbxService -> CliExecutor -> sbx (or mock-sbx)
```

Stores are the only reactive layer; services are `Sendable` protocol-based and CLI-backed.

## Core Technologies

- **Language**: Swift 6 (strict concurrency)
- **macOS GUI**: SwiftUI, `@Observable` (Swift 5.9 Observation), SwiftTerm 1.13+ for terminal rendering
- **Linux CLI**: Swift ArgumentParser 1.5+
- **Build systems**: Xcode (macOS app) + Swift Package Manager (cross-platform `SBXCore` library + `sbx-ui-cli` executable)
- **Target platforms**: macOS 14+ (GUI), Linux / Ubuntu 22.04+ (CLI)

## Key Libraries

- **swift-argument-parser** — declarative subcommand tree for the Linux CLI
- **SwiftTerm** — embedded terminal emulator for agent/shell sessions (macOS only)
- **Swift Testing** (`@Test`, `#expect`) — unit and SPM integration tests
- **XCTest / XCUITest** — UI/E2E tests that launch the macOS app and drive it through accessibility identifiers

## Development Standards

### Concurrency & Isolation

- Xcode project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — types are `@MainActor` unless opted out
- Explicit inits on `Sendable` types **must** be marked `nonisolated`, otherwise macOS builds break under the default-MainActor setting
- Stores are `@MainActor @Observable final class`; tests access their properties via `await store.property`
- Services are `Sendable` protocols; mocks used in tests are `actor` types (e.g. `StubSbxService`, `FailingSbxService`)
- Avoid storing `@Observable` class references (even `weak var`) inside other `@Observable` classes — it breaks SwiftUI rendering. Use closures for cross-store communication.
- Use `FileHandle.readabilityHandler` rather than `FileHandle.availableData` — the latter blocks the Swift cooperative thread pool and can't be unblocked reliably

### Platform Portability

- `SBX_SPM` compilation flag is set on the SPM `SBXCore` target and enables `Services/LinuxShims.swift` (provides `appLog` stub, etc.)
- `#if canImport(os)` guards `os.Logger` usage so Linux builds don't try to import Apple frameworks
- `SBXCore` deliberately excludes `Views/`, `Stores/`, `Plugins/`, `DesignSystem/`, and `sbx_uiApp.swift` — anything Linux-bound lives under `Models/` or `Services/`

### App Sandbox

- `ENABLE_APP_SANDBOX = NO` in Xcode — required to spawn the `sbx` / `docker` CLI as subprocesses

### Testing

- **Always write and run tests after any code change** (unit + UI/E2E as appropriate). Non-negotiable per `CLAUDE.md`.
- All tests use the bash mock (`tools/mock-sbx`). No Docker Desktop required.
- Mock is injected via env vars: `SBX_CLI_MOCK=1`, `SBX_MOCK_STATE_DIR=<temp>`, and PATH prepended with `tools/`
- UI tests inject env through `app.launchEnvironment`; SPM integration tests set process env directly
- Use `waitForExistence(timeout:)` generously (5–10s) in UI tests — the mock spawns real processes
- Fix flaky tests at the root cause; don't skip or delete them

## Development Environment

### Required Tools

- Xcode 16+ (macOS GUI)
- Swift 6.0+ (Linux CLI / SPM)
- Docker Desktop with `sbx` CLI v0.23.0+ (only for real sandboxes; not needed for tests)

### Common Commands

```bash
# macOS GUI build/test — prefer the Xcode MCP tools (BuildProject, RunAllTests)
#                        over the xcodebuild CLI

# Linux CLI (Package.swift lives under cli/ so Xcode doesn't auto-discover it)
swift build --package-path cli                  # build SBXCore + sbx-ui-cli (debug)
swift build --package-path cli -c release       # optimized release build
swift run --package-path cli sbx-ui-cli --help  # run the CLI
swift test --package-path cli                   # run 25 SBXCore tests

# CLI mock
bash tools/mock-sbx-tests.sh  # 32 bash tests for the mock itself
```

## Key Technical Decisions

- **Single shared core, two surfaces.** `SBXCore` (Models + Services) is compiled by both Xcode and SPM from the same source files. This is why Views/Stores/Plugins/DesignSystem are explicitly excluded from the SPM target rather than moved — the Xcode project keeps them in-tree alongside the shared code.
- **CLI subprocess over library binding.** `RealSbxService` shells out to `sbx` through `CliExecutor` and parses stdout via `SbxOutputParser`. This lets the mock (`tools/mock-sbx`) stand in for Docker without a separate code path — the service sees identical output whether the real CLI or the mock is on PATH.
- **Protocol-based service for testability.** `SbxServiceProtocol` + `ServiceFactory` lets tests substitute in-memory actors (`StubSbxService`, `FailingSbxService`) for fast unit tests, while UI/integration tests keep the real `CliExecutor` path but swap the binary.
- **Managed-section markers for persistent files.** Env var persistence writes a delimited block to `/etc/sandbox-persistent.sh` so user edits outside the managed section survive round-trips.

---
_Document standards and patterns, not every dependency_
