# Project Structure

## Organization Philosophy

Layer-first within Electron's main/renderer split. Each layer has clear responsibilities and the service interface is the boundary between main process (Node.js) and renderer (React).

## Directory Patterns

### Main Process (`src/main/`)
**Purpose**: Electron main process — app lifecycle, IPC handlers, sbx CLI interaction, PTY management  
**Key subdirectories**:
- `services/` — `SbxService` interface + real/mock implementations + factory
- `pty/` — PTY session management (`PtyManager`) and mock emitter
- `utils/` — CLI executor and output parsers for `sbx` command output

### Preload (`src/preload/`)
**Purpose**: Electron contextBridge — exposes typed `window.sbx` API to renderer  
**Single file**: `index.ts` — maps each IPC channel to a typed function

### Renderer (`src/renderer/`)
**Purpose**: React SPA — all UI components, state, and hooks  
**Subdirectories**:
- `components/` — organized by domain: `layout/`, `dashboard/`, `policies/`, `ports/`, `session/`
- `stores/` — Zustand stores: `sandbox-store.ts`, `policy-store.ts`, `session-store.ts`
- `hooks/` — custom hooks per domain: `useSandboxes`, `usePolicies`, `usePorts`, `useSession`
- `styles/` — Tailwind CSS entry point

### Tests (`tests/`)
**Purpose**: All test files, separated by type  
- `unit/` — Vitest tests for services, parsers, stores
- `e2e/` — Playwright specs with mock-mode setup

## Naming Conventions

- **Files**: kebab-case (`sandbox-store.ts`, `mock-sbx-service.ts`)
- **React Components**: PascalCase files and exports (`SandboxCard.tsx`)
- **Interfaces/Types**: PascalCase (`SbxService`, `Sandbox`, `PolicyRule`)
- **Stores**: camelCase function (`useSandboxStore`)

## Import Organization

```typescript
// External packages
import { app, BrowserWindow } from 'electron'
import { create } from 'zustand'

// Internal absolute (from src root)
import { SbxService } from '../services/sbx-service'

// Relative
import { StatusChip } from './StatusChip'
```

## Code Organization Principles

- **Service interface is the contract**: Both `RealSbxService` and `MockSbxService` implement the same `SbxService` interface. `service-factory.ts` selects based on `SBX_MOCK` env var.
- **Components by domain**: UI components grouped by feature area (dashboard, policies, ports, session), not by component type.
- **One store per domain**: Each Zustand store owns a single slice of state. Stores call IPC through `window.sbx`.
- **Hooks wrap stores**: Custom hooks provide the public API for components to consume store data and trigger actions.

---
_Document patterns, not file trees. New files following patterns shouldn't require updates_
