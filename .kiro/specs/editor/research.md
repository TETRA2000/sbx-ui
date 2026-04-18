# Research & Design Decisions — `editor`

## Summary
- **Feature**: `editor`
- **Discovery Scope**: Extension with moderate integration (brownfield — net-new UI surface, net-new store, but leverages existing `FileManager` persistence pattern and requires no service-protocol or mock-CLI changes). The earlier iteration of this document was a Complex Integration around `sbx exec`; the requirements pivot to direct host-filesystem I/O against `Sandbox.workspace` removed that complexity wholesale.
- **Key Findings**:
  - `Sandbox.workspace` is already an absolute host path that refers to a Docker bind-mount ([sbx-cli-reference.md:34](docs/sbx-cli-reference.md:34): `"workspaces": ["/Users/dev/project"]`; [RealSbxService.swift:23](sbx-ui/Services/RealSbxService.swift:23) maps `workspaces?.first ?? ""`). The editor can read and write it with `FileManager` directly; no container round-trip, no CLI parsing, no mock-sbx extension.
  - The project already has the **exact pattern** the editor needs: [KanbanPersistence.swift](sbx-ui/Services/KanbanPersistence.swift) is a 47-line `Sendable` struct with `nonisolated` methods that use `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:)`, `Data(contentsOf:)`, and `data.write(to:options: [.atomic])`. `EditorDocumentProvider` is a near-clone parameterized by workspace root instead of app-support directory.
  - The project has **no existing file-system watching code** (grep for `DispatchSource`, `NSFilePresenter`, `FSEventStream`, `kqueue` returns zero files). Requirement 10.4's external-change detection is poll-on-next-read per the spec; watching is deferred and would be a future extension.
  - `ENABLE_APP_SANDBOX = NO` in the Xcode project ([tech.md § App Sandbox](.kiro/steering/tech.md)) — the app already has unrestricted filesystem access and does not need a new entitlement. TCC prompts are not triggered for user-chosen paths.
  - The existing E2E test harness at [sbx-uiUITests/sbx_uiUITests.swift:18-42](sbx-uiUITests/sbx_uiUITests.swift:18) already seeds per-test temp directories for plugins and kanban via `NSTemporaryDirectory() + UUID()`. Editor E2E tests can clone the pattern for workspace fixtures, but the mock sandbox creation flow hard-codes the workspace path at [CreateProjectSheet.swift:184](sbx-ui/Views/Dashboard/CreateProjectSheet.swift:184) (`/tmp/mock-project`) — this will need a small extension to accept a per-test override so editor tests can point at their temp fixtures.
  - Widget, splitter, design-system, and store-pattern findings from the earlier iteration of this document remain accurate and are preserved below.

## Research Log

### `Sandbox.workspace` semantics and host-path access
- **Context**: The entire data layer of the feature depends on whether `Sandbox.workspace` is an absolute host path and whether reading/writing it from the app is correct for both real and mock modes.
- **Sources Consulted**:
  - [sbx-cli-reference.md](docs/sbx-cli-reference.md) — confirms `workspaces` is a JSON array of absolute host paths; line 61 confirms "direct mount" semantics
  - [RealSbxService.swift:17-29](sbx-ui/Services/RealSbxService.swift:17) — `workspace: json.workspaces?.first ?? ""`
  - [CreateProjectSheet.swift:183-184](sbx-ui/Views/Dashboard/CreateProjectSheet.swift:183) — mock-mode workspace hard-coded to `/tmp/mock-project`
  - [tools/mock-sbx:96+](tools/mock-sbx:96) — `cmd_ls` emits whatever workspace path was captured at sandbox-create time
- **Findings**:
  - Real mode: `Sandbox.workspace` is the user-chosen absolute path (e.g., `/Users/dev/project`). Docker Sandbox bind-mounts it into the container at `/workspace`; agent writes land on the host in real time.
  - Mock mode: Workspace is `/tmp/mock-project` by default. For editor E2E tests, this must become overridable per test run to avoid cross-test pollution and to provide deterministic fixtures.
  - Sandbox may have `workspace == ""` if `workspaces` is absent/empty in the CLI JSON (defensive null-handling in service layer). R2.8 handles this with a placeholder view.
- **Implications**:
  - The editor can use `FileManager.default` methods against `URL(fileURLWithPath: sandbox.workspace)` directly — no service-protocol changes.
  - E2E test infrastructure needs one small change: `CreateProjectSheet.swift:184` should check for a new env var (e.g., `SBX_CLI_MOCK_WORKSPACE`) and fall back to `/tmp/mock-project`. Each editor E2E test creates a temp dir, seeds it, and sets the env var before `app.launch()`.
  - No data crosses the container boundary; no seccomp/uid/gid concerns for the editor's writes. The agent continues to see host-side writes immediately because the workspace is a bind-mount, not a copy.

### Existing `FileManager` pattern — `KanbanPersistence` as the reference implementation
- **Context**: R13.1/R13.3 ask for an `EditorDocumentProvider` protocol with a `FileManager`-backed default implementation. A nearby idiomatic reference accelerates both implementation and code review.
- **Sources Consulted**:
  - [KanbanPersistence.swift](sbx-ui/Services/KanbanPersistence.swift) — complete class, 47 lines
  - [PluginApiHandler.swift:271-317](sbx-ui/Plugins/PluginApiHandler.swift:271) — existing path-scope validation pattern (plugin directory)
  - [.kiro/steering/tech.md § Concurrency & Isolation](.kiro/steering/tech.md) — `Sendable`/`nonisolated` rules
- **Findings**:
  - `KanbanPersistence` is a `struct: Sendable` with `nonisolated` methods. It uses `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:)`, `Data(contentsOf:)`, and `data.write(to:options: [.atomic])` — exactly the calls the editor needs.
  - `PluginApiHandler.validatePathScope(_:id:)` (inside the `PluginApiHandler` actor) demonstrates the project's path-traversal guard: standardize the URL, check `hasPrefix(pluginDirectory + "/")` before any file op. This is the pattern R3.7 calls for, parameterized by `Sandbox.workspace` instead of plugin dir.
  - No existing code uses `@FileManager(.default)` from inside `@Observable @MainActor` stores — Kanban delegates to the `Sendable` persistence struct. `EditorStore` will follow the same layering: `EditorStore` (store) → `EditorDocumentProvider` (Sendable protocol) → `DefaultEditorDocumentProvider` (Sendable struct wrapping `FileManager`).
- **Implications**:
  - `DefaultEditorDocumentProvider` is roughly a 60–80 line struct modeled on `KanbanPersistence`, parameterized by `workspaceRoot: URL`.
  - Path validation code is a one-to-one lift from `validatePathScope`; rewrite it as a free function or static method on `EditorPath` for reuse between listing and opening.
  - Byte-exact round-trip (R5.7) is achieved "for free" by `Data.write(to:options: [.atomic])` — no transformations happen between decode and encode.

### Path-traversal and scope enforcement
- **Context**: R3.7 requires rejection of paths outside `Sandbox.workspace`, including via `..` traversal.
- **Sources Consulted**:
  - [PluginApiHandler.swift:259-268](sbx-ui/Plugins/PluginApiHandler.swift:259) — `validatePathScope`
  - `URL.standardizedFileURL` Apple documentation (resolves `..`, `.`, and symlinks)
- **Findings**:
  - The existing pattern resolves to canonical path via `URL(fileURLWithPath: path).standardizedFileURL.path`, then checks `hasPrefix(scopeDirectory + "/") || == scopeDirectory`. This catches `../../etc/passwd`, `workspace/../../etc/passwd`, and direct absolute paths outside the scope.
  - `.standardizedFileURL` does not follow symlinks (`URL.resolvingSymlinksInPath` does). For a workspace that legitimately contains symlinks to outside the tree, the editor must decide whether to follow them. Conservative MVP: do *not* resolve symlinks in the scope check; if a workspace symlinks to outside, treat the symlink target as in-scope only if `standardizedFileURL` stays inside.
- **Implications**:
  - Reuse the exact `validatePathScope` logic; adapt to `workspaceRoot` instead of `pluginDirectory`.
  - Don't call `resolvingSymlinksInPath` in MVP. Document this as a conservative default; a future spec can add an "allow symlink escape" option if anyone complains.

### Widget choice — `CodeEditorView` vs `NSTextView` vs alternatives
- **Context**: Text-editing widget decision from the previous iteration remains in force. This section is unchanged from the prior `research.md`.
- **Sources Consulted**:
  - [CodeEditorView (mchakravarty) on GitHub](https://github.com/mchakravarty/CodeEditorView) — Apache 2.0, TextKit 2, SwiftUI
  - [CodeEditTextView (CodeEditApp) on GitHub](https://github.com/CodeEditApp/CodeEditTextView) — AppKit NSTextView replacement
  - [Sourceful](https://github.com/twostraws/Sourceful), [HighlightedTextEditor](https://github.com/kyle-n/HighlightedTextEditor), [ZeeZide/CodeEditor](https://github.com/ZeeZide/CodeEditor), [Runestone](https://github.com/simonbs/Runestone)

| Option | Syntax hl | Line numbers | Find-bar | Deps | Effort |
|---|---|---|---|---|---|
| `NSTextView` via `NSViewRepresentable` | Manual | Manual gutter | Native `NSTextFinder` | 0 | M–L |
| `SwiftUI.TextEditor` | None | None | None | 0 | S + L (most of R4/R7/R8 from scratch) |
| `CodeEditorView` (mchakravarty, Apache 2.0) | Built-in, themable | Built-in | Partial | +1 SPM dep | S–M |
| `CodeEditTextView` (CodeEditApp) | Via tree-sitter + language pack | Built-in | Partial | +1–2 SPM deps | M |
| `Sourceful` | Built-in Swift/Python | Built-in | Native | +1 dep | M |
| `WKWebView` + Monaco | Best parity | Built-in | Built-in | Bundled assets | L–XL + brittle XCUITest |

- **Findings**:
  - `CodeEditorView` remains the highest-leverage MVP choice; `NSTextView`-wrapped is the zero-dep fallback. The removal of `sbx exec` transport does not change this calculus — the widget sees bytes regardless of where they came from.
  - Apache 2.0 license is compatible with the project's MIT/unspecified policy for dependencies.
  - Minimum macOS deployment target for `CodeEditorView` is not visible from the package page and must be verified during implementation. If it exceeds macOS 14, fall back to `NSTextView`-wrapped (single-file swap in `EditorBufferView`).
- **Implications**:
  - Design phase commits to `CodeEditorView` primary with `NSTextView`-wrapped fallback, isolated to `EditorBufferView.swift`.
  - No widget-selection change is driven by the host-FS pivot.

### Splitter, design system, store pattern, cross-store comms
- **Context**: These findings from the prior research iteration are unchanged; the data-layer pivot does not touch them. Restated briefly for self-containment.
- **Findings**:
  - **Splitter**: `HSplitView` + `GeometryReader` writing back to `EditorStore.layoutRatio`, or `HStack`+`DragGesture` as a fallback. Feedback-loop risk requires gesture-bounded writes (commit ratio only on drag end).
  - **Design system**: All tokens referenced in R12 already exist at [DesignSystem/](sbx-ui/DesignSystem/). Zero new tokens.
  - **Store pattern**: `@Observable @MainActor final class`, injected via `.environment(...)` in [sbx_uiApp.swift:43-54](sbx-ui/sbx_uiApp.swift:43). `EditorStore` slots in alongside `SandboxStore`, `TerminalSessionStore`, `KanbanStore`.
  - **Cross-store comms**: `EditorStore` must not hold references to other stores. `ShellView.onChange(of: runningSandboxNames)` — already fanning to `sessionStore.cleanupStaleSessions` and `kanbanStore.syncSandboxStatus` — fans one more call to `editorStore.syncSandboxStatus(sandboxes:)`. Matches the established pattern verbatim.

### File-system watching — confirmed deferred
- **Context**: R10.4's external-change detection is poll-on-next-read in the spec, but a native watching layer is attractive for agent-driven edits.
- **Sources Consulted**:
  - Apple documentation for `DispatchSource.makeFileSystemObjectSource`, `NSFilePresenter`, `FSEventStream`
  - Project-wide grep for these APIs returns zero files
- **Findings**:
  - The project has never implemented file-system watching. Adding it is a net-new capability with its own design considerations (coalescing, recursive vs. flat, debouncing against rapid-fire writes).
  - `DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask:.rename union .delete union .write, queue:)` is the lightest-weight option for per-file watching; `FSEventStream` (C API with Swift wrappers) is needed for recursive workspace monitoring.
  - Cost to add: one dedicated actor (`FileWatchStore` or similar) plus events into `EditorStore.onExternalChange(path:)`. Probably a small follow-up spec — not MVP.
- **Implications**:
  - MVP ships with poll-on-next-read per R10.4, which is cheap with native `FileManager.attributesOfItem(atPath:)`.
  - A future spec (`editor-live-watch` or similar) adds FSEvents for real-time notification. The `EditorDocumentProvider` seam accommodates this without rework.

### E2E test isolation for workspace fixtures
- **Context**: R14.3 and R14.6 require per-test temp workspaces. Current `CreateProjectSheet` hard-codes the mock workspace path.
- **Sources Consulted**:
  - [sbx-uiUITests/sbx_uiUITests.swift:18-42](sbx-uiUITests/sbx_uiUITests.swift:18) — `setUpWithError` pattern for plugin and kanban dirs
  - [CreateProjectSheet.swift:183-184](sbx-ui/Views/Dashboard/CreateProjectSheet.swift:183) — `if SBX_CLI_MOCK == 1 { selectedPath = /tmp/mock-project }`
- **Findings**:
  - The existing pattern (set an env var in `launchEnvironment`, app reads it at runtime) works cleanly. Adding `SBX_CLI_MOCK_WORKSPACE` mirrors `SBX_KANBAN_DIR` and `SBX_PLUGIN_DIR`.
  - The mock CLI (`tools/mock-sbx`) does not care about the workspace path — it just stores and returns whatever string was passed at sandbox-create time. So a per-test temp path works end-to-end with zero mock-sbx changes.
- **Implications**:
  - Implementation task: small edit to `CreateProjectSheet.swift` to honor `SBX_CLI_MOCK_WORKSPACE`. Ten lines.
  - E2E test helper (new `setUpWorkspace(fixtures:)` in test base class) creates the temp dir, seeds fixture files via `FileManager`, sets the env var. Similar to how `kanbanDir` is set up today.

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| **A. Extend existing components** | Add `EditorStore` and editor views; extend `SessionPanelView` to host a split pane; reuse `KanbanPersistence`-style `FileManager` calls inline | Fastest; natural fit for the `@Observable @MainActor` store pattern | `SessionPanelView` grows in responsibility; harder to slot future pane types in | Viable but doesn't satisfy R13.4's N-pane container well |
| **B. Create new components** | New `SandboxWorkspaceView` wrapping terminal + editor; new `EditorStore`; new `EditorDocumentProvider` protocol with `DefaultEditorDocumentProvider` (FileManager-backed) and `FakeEditorDocumentProvider` (in-memory for tests) | Clean separation; R13.4 N-pane container lands naturally; testability is trivial via the provider protocol | More files, more wiring | **Recommended.** Aligns with how `KanbanPersistence` is separated from `KanbanStore` and `KanbanBoardView`. |
| **C. Hybrid** | Extend `SessionPanelView` for the split pane (A-style) but introduce the provider protocol for file I/O (B-style) | Middle ground | Slightly anemic — the protocol only has one prod impl for MVP | Acceptable if `SandboxWorkspaceView` separation is deemed premature |

## Design Decisions

### Decision: File I/O transport
- **Context**: R3, R5, R10.4 specify the mechanism for reading, writing, and stat-ing files.
- **Alternatives Considered**:
  1. `sbx exec cat / tee / stat` — container-scoped I/O (previous iteration)
  2. `FileManager` against `Sandbox.workspace` — direct host access
  3. Hybrid: read via `FileManager` (fast path), write via `sbx exec tee` (container ownership)
- **Selected Approach**: Option 2 — direct host `FileManager` access against `Sandbox.workspace`.
- **Rationale**: The editor is a first-party surface that does not process untrusted prompts, so the container boundary adds no security value. The workspace is already a bind-mount the user edits with other host tools. Option 2 yields native performance, byte-exact round-trips (fixes validation Issue 1), eliminates stat portability concerns (fixes validation Issue 3), and removes the need for `tools/mock-sbx` extensions (removes ~100 lines of bash and 8 new bash tests).
- **Trade-offs**: Editor writes bypass any future in-container hooks (seccomp, tmpfs, virtualization) that a downstream sandbox product might introduce. Acceptable because those hooks do not exist today and would require deliberate opt-in at that time.
- **Follow-up**: Revisit if Docker Sandbox gains writable-overlay semantics that break the bidirectional bind-mount assumption.

### Decision: Provider protocol vs direct `FileManager` calls in store
- **Context**: Should `EditorStore` call `FileManager` directly (simpler) or go through an `EditorDocumentProvider` seam (testable, extensible)?
- **Alternatives Considered**:
  1. Direct `FileManager` calls in `EditorStore`
  2. `EditorDocumentProvider` protocol with a `DefaultEditorDocumentProvider` (FileManager) and a `FakeEditorDocumentProvider` (in-memory) for unit tests
- **Selected Approach**: Option 2.
- **Rationale**: Matches R13.1 (seam for future providers) and R13.3 (allow alternative providers to register without changing `EditorStore`). Unit tests can seed a dictionary instead of a temp directory, making them fast and hermetic. Mirrors the `KanbanPersistence` factoring (store-agnostic, `Sendable`, injectable).
- **Trade-offs**: Slight indirection; one extra protocol file. Cheap.
- **Follow-up**: A future "remote sandbox" provider (SSH, gRPC, or WebSocket) can slot in without `EditorStore` changes.

### Decision: Byte-exact round-trip via `Data.write(to:options: [.atomic])`
- **Context**: R5.7 requires byte-for-byte round-trips (no trailing-newline insertion, no line-ending rewrite, no BOM changes).
- **Alternatives Considered**:
  1. `Data.write(to:options: [.atomic])` — atomic, byte-exact, native
  2. `String.write(toFile:atomically:encoding:)` — inserts platform newlines on some code paths
  3. `FileHandle.write(_:)` without options — not atomic, risks partial writes on crash
- **Selected Approach**: Option 1.
- **Rationale**: Atomic (writes to `<path>.tmp`, then `rename`) and byte-exact. No encoding transforms. Standard in the codebase — `KanbanPersistence.saveBoard` uses the same.
- **Trade-offs**: Requires buffering the full file in memory before write. Bounded by R11.2's 20 MB hard cap.
- **Follow-up**: None.

### Decision: Dirty detection via content fingerprint
- **Context**: R4.3 (revert clears dirty), R11.7 (O(1) dirty-compare). Validation Issue 2.
- **Alternatives Considered**:
  1. Full `Data == Data` compare per keystroke — O(n), unacceptable at the 2 MB soft cap
  2. Fingerprint (xxHash64 or SHA256) of last-saved contents; compare current buffer fingerprint to the saved one
  3. "Dirty latch" — once dirty, never clear via content compare; only save clears it
- **Selected Approach**: Option 2 (fingerprint). Prefer `xxHash64` via Apple's `CryptoKit.SHA256` if a fast non-crypto hash is not trivially available; benchmarks during implementation will decide.
- **Rationale**: Preserves R4.3's "reverting clears dirty" semantic at O(buffer-size) once-per-edit rather than O(n) per keystroke. Fingerprints rebuild cheaply on save.
- **Trade-offs**: Hash collisions are effectively impossible for realistic document sizes; even SHA256 adds < 100 µs for 2 MB.
- **Follow-up**: Measure and pick the specific hash in implementation phase; freeze the choice in `EditorStore` docs.

### Decision: Pull-based debounced fingerprint for dirty detection
- **Context**: Validation round 2 Issue 1. R11.7 demands O(1) dirty-compare per keystroke. A `onBufferEdit(newContents: Data)` push model is O(n) per keystroke in both the copy and the hash.
- **Alternatives Considered**:
  1. Full-buffer push on every edit + SHA-256 hash per keystroke — O(n) per keystroke, violates R11.7
  2. Signal-only `onBufferMutated()` + store-registered `pull: () -> Data` + 500 ms idle debounce; fingerprint computed at most once per idle window, synchronously on save
  3. "Dirty latch" — once dirty, never clear via content compare; user must manually mark clean. Drops R4.3 revert-to-clean.
  4. Incremental / rolling hash against widget's text-storage change delegate — complex, widget-specific
- **Selected Approach**: Option 2.
- **Rationale**: Keeps per-keystroke cost O(1) while preserving R4.3's revert-to-clean exactly. Save path still pulls and fingerprints synchronously so Cmd+S is not affected by debounce timing. The design's Requirements Traceability row for R4.1 now references `onBufferMutated` + `registerBufferPull` — both are tiny surface-area additions.
- **Trade-offs**: UI shows the dirty glyph promptly via `tentativelyDirty` (no visible delay), but the glyph may flicker off 500 ms after the user types back to the original contents. Acceptable given how rarely that specific revert pattern occurs.
- **Follow-up**: Measure fingerprint cost at 2 MB on an M-series chip during implementation. If > 16 ms even in the debounced window, move hashing to a detached `Task` with cancellation on subsequent keystrokes.

### Decision: Stateless `DefaultEditorDocumentProvider` (no `workspaceRoot`)
- **Context**: Validation round 2 Issue 2. Previous design had the provider accept `workspaceRoot: URL` at construction, implying per-sandbox re-instantiation — incompatible with the single-injection `EditorStore.init(provider:…)` signature.
- **Alternatives Considered**:
  1. Provider accepts `workspaceRoot: URL` at construction; `EditorStore` takes a factory `(URL) -> any EditorDocumentProvider` and keeps a dict of providers per sandbox
  2. Stateless provider; single instance shared across all sandboxes; all scope validation lives in `EditorStore` + `EditorPath.validate`
  3. Provider methods take both `workspaceRoot` and target `URL`; validate per-call
- **Selected Approach**: Option 2.
- **Rationale**: Matches `KanbanPersistence` construction (single shared instance, callers pass paths), simplifies `EditorStore.init`, and collapses the scope-guard responsibility to exactly one layer. Eliminates the design inconsistency flagged in validation.
- **Trade-offs**: Loses the provider's defense-in-depth re-check. Mitigated by keeping `EditorPath.validate` as the single, testable scope guard invoked before every provider call. Path validation is covered by dedicated unit tests.
- **Follow-up**: None.

### Decision: `EditorStore.shared` singleton accessor for `AppDelegateAdapter`
- **Context**: Validation round 2 Issue 3. R10.7 wires an `NSApplicationDelegate.applicationShouldTerminate(_:)` hook, but `@NSApplicationDelegateAdaptor` instantiates the adapter before the SwiftUI environment exists. [CLAUDE.md](CLAUDE.md) forbids storing `@Observable` references in other objects.
- **Alternatives Considered**:
  1. `EditorStore.shared` lazy singleton, populated in `sbx_uiApp.init()` with the same instance that is `.environment(...)`-injected. Mirrors the existing [LogStore.swift:63-71](sbx-ui/Stores/LogStore.swift:63) pattern.
  2. Closure-based: `AppDelegateAdapter` stores `var dirtyTabsSummaryProvider: (@MainActor () -> [DirtyTabSummary])?` set at app startup
  3. Weak reference on the adapter — forbidden by CLAUDE.md
- **Selected Approach**: Option 1.
- **Rationale**: Consistent with the existing `LogStore.shared` pattern already used across the project; thread-safe for the single-reader-at-terminate-time use case; reads the singleton at terminate time rather than storing it, so there is no persistent `@Observable` embedding.
- **Trade-offs**: Adds one static access pattern to the store layer. Justified by the precedent.
- **Follow-up**: None.

### Decision: `dirtyTabsSummary()` synchronously reconciles `tentativelyDirty` tabs
- **Context**: Validation round 3 Issue 1. The pull-based debounced fingerprint introduces a 500 ms window in which a tab is `tentativelyDirty == true` but `fingerprint == savedFingerprint`. Without reconciliation, a user who edits and hits Cmd+Q within 500 ms would bypass the quit-with-dirty prompt (R10.7) and lose the edit.
- **Alternatives Considered**:
  1. Keep `dirtyTabsSummary()` as-is (fingerprint-only); accept silent data loss in the debounce window
  2. Count `tentativelyDirty` as dirty without reconciliation (false positives when user reverted within the window)
  3. On every `dirtyTabsSummary()` call, synchronously pull + fingerprint any `tentativelyDirty` tabs, clearing `tentativelyDirty` when the fingerprint matches and leaving it set when it does not
- **Selected Approach**: Option 3.
- **Rationale**: Eliminates both silent data loss and false positives. Cost is at most one SHA-256 per in-edit tab on quit (ms-scale even at the 2 MB cap). Matches the precision the rest of the design targets and keeps the dirty-state predicate consistent across quit, Save All, and close-with-dirty paths.
- **Trade-offs**: `dirtyTabsSummary()` is no longer a pure read — it has a side effect (fingerprint update, `tentativelyDirty` clear). Acceptable because the call is rare (only on quit / explicit close flows) and the side effects are exactly the state those flows need.
- **Follow-up**: Ensure the new unit test `dirtyTabsSummary_synchronouslyReconcilesTentativelyDirty` actually exercises the in-flight-debounce scenario; one integration assertion via XCUITest (dirty edit → Cmd+Q → prompt appears) is also worth adding to the E2E suite if the harness allows.

### Decision: Deferred file-system watching
- **Context**: R10.4 external-change detection can be poll-on-next-read (polled via `FileManager.attributesOfItem`) or push-based (FSEvents/DispatchSource).
- **Alternatives Considered**:
  1. Poll on next read/save attempt — cheap, stateless, covers the three-way-prompt flow
  2. `DispatchSource.makeFileSystemObjectSource` per open file — push, complex for many tabs
  3. `FSEventStream` recursive on workspace — push, complex debouncing
- **Selected Approach**: Option 1 for MVP; defer push-based to a follow-up spec.
- **Rationale**: R10.4 is already satisfied by polling. Push-based notifications are a usability improvement, not a correctness requirement. The project has no existing FS-watch code, so Option 2/3 is a net-new capability better scoped as its own spec.
- **Trade-offs**: Agent-side edits are noticed only on the user's next read or save, not in real time.
- **Follow-up**: Create a follow-up spec `editor-live-watch` that adds an `FSEventStore` and pushes `EditorStore.onExternalChange(path:)` events.

## Requirement-to-Asset Map

| # | Requirement area | Existing assets (reuse) | Gaps | Constraints |
|---|---|---|---|---|
| R1 | Editor surface & navigation | `SessionPanelView`, `ShellView` running-sandbox gate, `DesignSystem` tokens | No split-pane primitive; no collapse controls; no per-sandbox layout persistence state | Nested inside existing `NavigationSplitView`; must not break `.id(sessionID)` teardown semantics |
| R2 | Workspace file tree | `Sandbox.workspace` host path; `ToastManager`; `KanbanPersistence` pattern for `FileManager.contentsOfDirectory` | No file tree view; no lazy-load state model | Watch out for large node_modules — default filters in R2.6 |
| R3 | File read and open | `Data(contentsOf:)`, `String(data:encoding:.utf8)`; `validatePathScope` pattern for R3.7 | No tab system; no large-file/binary classification | Scope-guard must use `standardizedFileURL`, not `resolvingSymlinksInPath` |
| R4 | Editing & dirty state | macOS shortcuts come from the widget; `CryptoKit` for SHA256 fingerprint | No `EditorStore`; no fingerprint pipeline | Widget choice decides a chunk of R4.2 |
| R5 | Save semantics | `Data.write(to:options: [.atomic])` pattern from `KanbanPersistence` | No tab-level save UX (spinner, flash, toasts) | `NSError.localizedDescription` is the toast payload (not CLI stderr) |
| R6 | Multi-tab management | `@Observable @MainActor` store pattern | No tab component; no per-sandbox tab persistence | Keyed by sandbox name, session-scoped |
| R7 | Syntax highlighting (Phase-2) | Color tokens | No highlighter; no feature-flag plumbing | Widget choice determines extent |
| R8 | Find within file | `Font.code` | No find-bar component; no match-highlight primitive | Widget may provide native find; if not, custom regex scan |
| R9 | Terminal integration | `TerminalViewWrapper`, `TerminalSessionStore.disconnect` | No focus arbitration between panes; no dirty-aware disconnect prompt | File I/O path is independent of PTY — no contention |
| R10 | Error handling & edge states | `ToastManager`; `NSError`; existing confirmation-dialog pattern | No unsaved-close dialog; no external-change check; no quit-with-dirty prompt; no banner | `NSApplicationShouldTerminate` hook required for R10.7 |
| R11 | Performance & large files | `stat` via `FileManager.attributesOfItem`; CryptoKit hashing | No size thresholds; no pending indicator throttle; no fingerprint cache | 2 MB soft / 20 MB hard caps per R11.1/R11.2 |
| R12 | Design system consistency | **All tokens exist.** Zero work. | — | `.preferredColorScheme(.dark)` already applied |
| R13 | Extensibility hooks | `@Observable @MainActor` pattern; `PluginApiHandler` + `PluginPermission` precedent | No `EditorDocumentProvider`; no `EditorPluginApi`; no N-pane container | `editor.readState`/`editor.mutateState` permissions distinct from existing `file.read`/`file.write` |
| R14 | Testing coverage | `StubSbxService`, `FailingSbxService`, XCUITest identifier convention, per-test temp-dir pattern | `SBX_CLI_MOCK_WORKSPACE` env var wiring; `FakeEditorDocumentProvider` fixture | Must not break the existing bash tests or unit tests |

## Implementation Approach Options (trade-off summary)

- **Option A — Extend existing components**: Add views and store inline; reuse `FileManager` directly. Fastest but grows `SessionPanelView` responsibility and makes R13.4 awkward.
- **Option B — Create new components (recommended)**: `SandboxWorkspaceView` wraps terminal + editor; `EditorStore` is a leaf; `EditorDocumentProvider` protocol with `DefaultEditorDocumentProvider` (FileManager) and `FakeEditorDocumentProvider` (in-memory). Matches the Kanban persistence/store factoring; natural fit for the N-pane container and future alternative providers.
- **Option C — Hybrid**: Extend `SessionPanelView` (Option A) but introduce the provider protocol (Option B). Viable if full separation is deemed premature.

## Effort & Risk

| Scope | Effort | Risk | One-line justification |
|---|---|---|---|
| `EditorDocumentProvider` protocol + `DefaultEditorDocumentProvider` (FileManager) + `FakeEditorDocumentProvider` (in-memory) + path-scope validator | S | Low | Direct lift from `KanbanPersistence` + `validatePathScope` |
| `EditorStore` (@Observable @MainActor) with tab state, dirty tracking, fingerprint cache, save orchestration, sandbox-status reactivity | M | Medium | New reactive state but modest domain; main risk is widget-specific text-change notifications |
| Split-pane container + collapse controls + per-sandbox ratio persistence | M | Low–Medium | First splitter in the app; `HSplitView` vs custom is the main unknown |
| File tree view with lazy loading + ignore filters + hidden toggle | S–M | Low | Straightforward `OutlineGroup`-style SwiftUI; `FileManager.contentsOfDirectory` provides clean data |
| Editor widget integration (`CodeEditorView` primary / `NSTextView`-wrapped fallback) + gutter + Cmd+S | M | Medium | Widget choice decides; both paths documented |
| Find bar (R8) | S–M | Low | `NSTextFinder` bridge or custom regex highlight pass |
| Syntax highlighting (R7) | S | Low | No-op in MVP (Phase-2 flag off) |
| Error handling + external-change polling detection (R10) + quit-with-dirty (R10.7) | M | Medium | `NSApp.terminate(_:)` hook + NSAlert plumbing |
| Unit tests (R14.1, R14.4) + XCUITest E2E (R14.2, R14.3, R14.5) + `SBX_CLI_MOCK_WORKSPACE` env var wiring | M | Low | Existing test harness + small env-var addition |
| **Total** | **M–L (1 week)** | **Low–Medium** | Net-new surface, but every step rides existing patterns; data layer dramatically simpler than the `sbx exec` alternative |

## Risks & Mitigations

- **Risk**: `Sandbox.workspace` is `""` when the sandbox was created without a workspace path (e.g., bare `sbx run claude` with no directory). **Mitigation**: R2.8 renders a "No workspace available" placeholder; `EditorStore.open(sandbox:)` early-returns without mounting views.
- **Risk**: Agent writes to a file while the user is editing → silent data loss if the user saves first. **Mitigation**: R10.4's three-way prompt triggered by stat-mismatch on read or save. Future spec adds FSEvents for real-time notification.
- **Risk**: `HSplitView` + `GeometryReader` feedback loop (ratio writes triggering layout triggering more writes). **Mitigation**: commit the ratio to `EditorStore` only on drag-end, not on every layout pass. Fallback is a custom `HStack`+`DragGesture` splitter.
- **Risk**: Widget dep (`CodeEditorView`) raises minimum macOS deployment target above the project's floor. **Mitigation**: verify before merging the SPM addition; fall back to `NSTextView`-wrapped if incompatible.
- **Risk**: Path-scope validator misses an exotic traversal (e.g., a symlink inside the workspace pointing outward). **Mitigation**: conservative — do not call `resolvingSymlinksInPath`; if `standardizedFileURL` produces an in-scope path, trust it. Document this behavior.
- **Risk**: Fingerprint hash bug causes spurious dirty state. **Mitigation**: Unit tests in R14.1 cover revert-to-clean for realistic file sizes; snapshot-based golden tests for the fingerprint function.
- **Risk**: Mock workspace path (`/tmp/mock-project`) collisions between concurrent test runs. **Mitigation**: introduce `SBX_CLI_MOCK_WORKSPACE` env var; E2E tests set per-test temp dirs via the existing UUID pattern.

## Research Needed (carry into design phase)

- Confirm `CodeEditorView`'s minimum macOS deployment target and dependency graph before adding to `Package.swift`; if > macOS 14, commit to `NSTextView`-wrapped from the start.
- Benchmark `NSTextView` change notifications vs `CodeEditorView` change notifications for the fingerprint pipeline — which emits the tightest signal for "buffer mutated since fingerprint"?
- Confirm that `NSApplicationShouldTerminate` delegate path is usable in a SwiftUI lifecycle on macOS 14 for R10.7 (may require a small `NSApplicationDelegate` adapter attached via `@NSApplicationDelegateAdaptor`).
- Decide whether the workspace is auto-refreshed when the sandbox is re-created with a different workspace (e.g., user removes and re-creates sandbox with a new path). MVP: re-scope editor state on `syncSandboxStatus(sandboxes:)` when the sandbox name disappears.

## References

- [KanbanPersistence.swift](sbx-ui/Services/KanbanPersistence.swift) — reference implementation for `FileManager`-backed persistence struct
- [PluginApiHandler.swift](sbx-ui/Plugins/PluginApiHandler.swift) — reference implementation for `validatePathScope`
- [CodeEditorView on GitHub](https://github.com/mchakravarty/CodeEditorView) — primary widget candidate (Apache 2.0)
- [CodeEditTextView on GitHub](https://github.com/CodeEditApp/CodeEditTextView) — fallback widget candidate
- [Sourceful](https://github.com/twostraws/Sourceful), [HighlightedTextEditor](https://github.com/kyle-n/HighlightedTextEditor), [CodeEditor (ZeeZide)](https://github.com/ZeeZide/CodeEditor), [Runestone](https://github.com/simonbs/Runestone) — alternatives evaluated and rejected
- [docs/sbx-cli-reference.md](docs/sbx-cli-reference.md) — confirms `workspaces` is an array of absolute host paths; "direct mount" semantics
- [.kiro/steering/tech.md](.kiro/steering/tech.md) — concurrency rules; `ENABLE_APP_SANDBOX = NO`
- [CLAUDE.md](CLAUDE.md) — project instructions; closure-based cross-store pattern; `FileHandle.availableData` prohibition
- Apple documentation for [`FileManager`](https://developer.apple.com/documentation/foundation/filemanager), [`DispatchSource.makeFileSystemObjectSource`](https://developer.apple.com/documentation/dispatch/dispatchsource/2300038), and [`FSEventStream`](https://developer.apple.com/documentation/coreservices/file_system_events) — for current and future change-detection strategies
