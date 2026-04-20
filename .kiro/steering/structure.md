# Project Structure

## Organization Philosophy

**Layered + feature-first, with a cross-platform core.** The codebase separates concerns by layer (Models → Services → Stores → Views), and within each layer groups files by feature (Dashboard, Kanban, Policies, Ports, EnvVars, Session). A single shared core (`SBXCore`) is compiled by both Xcode (macOS) and Swift Package Manager (Linux) — platform-specific code lives outside the core and is excluded from the SPM target.

## Directory Patterns

### Shared Core — `SBXCore`
**Location**: `sbx-ui/Models/`, `sbx-ui/Services/`
**Purpose**: Domain types and service layer usable from both macOS and Linux. No SwiftUI, no `@Observable`, no platform-specific imports without `#if canImport(...)` guards.
**Example**: `Models/DomainTypes.swift` (Sandbox, PolicyRule, PortMapping, EnvVar), `Services/SbxServiceProtocol.swift`, `Services/CliExecutor.swift`.

### macOS App — `sbx-ui/`
**Location**: `sbx-ui/Stores/`, `sbx-ui/Views/`, `sbx-ui/DesignSystem/`, `sbx-ui/Plugins/`, `sbx-ui/sbx_uiApp.swift`
**Purpose**: Everything that only runs on macOS. These directories are not part of the SPM `SBXCore` target (which only compiles `Models/` and `Services/` via symlinks from `cli/SBXCore/`).
**Example**: `Stores/SandboxStore.swift` is `@MainActor @Observable`; `Views/Dashboard/SandboxCardView.swift` is SwiftUI.

### Linux CLI — `cli/`
**Location**: `cli/Package.swift`, `cli/Sources/sbx-ui-cli/`, `cli/SBXCore/` (symlinks), `cli/Tests/`
**Purpose**: Everything the Linux CLI needs, isolated under `cli/` so Xcode's sibling auto-discovery doesn't pull SPM dependencies (notably `swift-argument-parser`) into the macOS workspace. Swift ArgumentParser entry point and subcommand definitions that call into `SBXCore`. One file per command family.
**Example**: `CLI.swift` (`@main`), `Commands.swift` (lifecycle), `PolicyCommands.swift`, `PortsCommands.swift`, `EnvCommands.swift`, `Formatting.swift`.

### Tests
**Location**:
- `sbx-uiTests/` — Xcode unit tests (Swift Testing, in-memory stubs)
- `sbx-uiUITests/` — Xcode UI/E2E tests (XCTest + XCUITest, real mock CLI)
- `cli/Tests/SBXCoreTests/` — SPM unit + integration tests (Swift Testing)
- `cli/Tests/CLIE2ETests/` — SPM end-to-end tests against the compiled `sbx-ui-cli`
- `tools/mock-sbx-tests.sh` — bash tests for the CLI mock itself

**Purpose**: Stores and pure logic → unit tests with `StubSbxService` / `FailingSbxService`. Full user flows → UI tests launched with `SBX_CLI_MOCK=1`.

### Tools & Docs
**Location**: `tools/`, `docs/`
**Purpose**: `tools/mock-sbx` is the bash emulator of the real `sbx` CLI, used by every test tier. `docs/` holds CLI references (`sbx-cli-reference.md`, `linux-cli.md`, `mock-sbx.md`) and feature design docs (e.g. `kanban-design.md`).

### Build Configuration
**Location**: `Configuration/`
**Purpose**: Xcode `.xcconfig` files per release channel (`Canary`, `Beta`, `Stable`).

## Naming Conventions

- **Swift files**: PascalCase matching the primary type (`SandboxStore.swift`, `CreateProjectSheet.swift`)
- **Types**: PascalCase; stores end in `Store`, sheets in `Sheet`, panels in `PanelView`, cards in `CardView`
- **Sandbox names (user-facing)**: lowercase alphanumeric with hyphens — validated in the UI
- **Accessibility identifiers** (UI tests): camelCase with hyphen-separated dynamic suffixes — `sandboxCard-{name}`, `statusChip-{status}`, `removePolicy-{resources}`, `sidebarSession-{label}`. Keep this pattern stable; UI tests depend on it.
- **Env var keys**: must match `[A-Za-z_][A-Za-z0-9_]*` (enforced in the UI)

## Import Organization

Swift has no path aliases — imports are module-level. Conventions:

```swift
import Foundation              // always first
import SwiftUI                 // macOS-only code
import ArgumentParser          // Linux CLI only
#if canImport(os)
import os                      // guard Apple-only frameworks
#endif
```

**Platform guards**:
- `#if SBX_SPM` — code that only compiles under the SPM target (enables `LinuxShims.swift`)
- `#if canImport(os)` / `#if canImport(AppKit)` — guard macOS-only framework usage inside shared files

## Code Organization Principles

- **Views never talk to services.** The dependency direction is `View → Store → Service → CliExecutor`. Views read and mutate store properties; stores own async calls.
- **Services are stateless and `Sendable`.** State lives in stores (UI reactive state) or on disk (e.g. Kanban persistence, sandbox persistent env). Services only wrap the CLI.
- **One store per domain.** `SandboxStore`, `PolicyStore`, `EnvVarStore`, `TerminalSessionStore`, `KanbanStore`, `SettingsStore`, `LogStore`, `PluginStore`. Stores communicate via closures, never by holding references to each other.
- **Feature-grouped views.** `Views/<Feature>/` contains the panel, sheets, and subviews for that feature. Shared primitives live at the `Views/` root (`SidebarView`, `ShellView`).
- **CLI output parsing is isolated.** `SbxOutputParser` is the single place that understands `sbx` CLI output shapes, so the mock and real CLI can evolve in lockstep.
- **Shared core stays UI-free.** Anything importing `SwiftUI`, `AppKit`, or using `@Observable` must live outside `Models/` and `Services/`, or the SPM/Linux build breaks.

---
_Document patterns, not file trees. New files following patterns shouldn't require updates_
