# Technology Stack

## Architecture

Electron desktop app with a clear main/renderer split. The main process owns all `sbx` CLI interaction through a service interface (`SbxService`) with real and mock implementations. The renderer is a React SPA communicating via Electron IPC (`contextBridge`). Terminal sessions use `node-pty` in main and `xterm.js` in renderer.

## Core Technologies

- **Language**: TypeScript (strict)
- **Shell**: Electron 36+
- **Frontend**: React 19
- **Styling**: Tailwind CSS 4
- **State**: Zustand
- **Terminal**: xterm.js 5 + node-pty
- **IPC**: Electron contextBridge (typed `window.sbx` API)
- **Build**: electron-vite (ESM-native, fast HMR)
- **Package**: electron-builder (macOS DMG + Windows NSIS)

## Key Libraries

- **xterm.js** — renders Claude Code PTY output with full ANSI support
- **node-pty** — spawns and manages PTY sessions per sandbox
- **Zustand** — lightweight stores for sandbox list, policies, and session state

## Development Standards

### Type Safety
TypeScript strict mode. The `SbxService` interface is the compile-time contract between real and mock implementations.

### Testing
- **Unit**: Vitest — MockSbxService, output parsers, stores
- **E2E**: Playwright with Electron support — forces mock mode via `SBX_MOCK=1`

### Design System
"The Technical Monolith" — dark-surface editorial aesthetic. See `ui/stitch_claude_ai_sandbox_dashboard/DESIGN.md` for full spec. Key rules:
- No 1px borders — use background tonal shifts for boundaries
- Fonts: Inter (UI), JetBrains Mono (code/metrics), Space Grotesk (labels)
- Max border-radius: 0.5rem
- Surface hierarchy: `#131313` → `#1C1B1B` → `#2A2A2A` → `#353534`

## Development Environment

### Common Commands
```bash
# Dev:   npm run dev         (electron-vite HMR)
# Build: npm run build       (production bundle)
# Test:  npm run test        (vitest unit)
# E2E:   npm run test:e2e    (playwright, mock mode)
```

### Mock Mode
Set `SBX_MOCK=1` to use `MockSbxService` instead of real CLI. The mock seeds Balanced policy defaults and simulates sandbox lifecycle transitions with realistic delays.

## Key Technical Decisions

- **Electron over Tauri** — `xterm.js + node-pty` is proven for terminal emulation; Tauri would require native PTY bridging
- **Service interface pattern** — `SbxService` abstraction makes mock indistinguishable from real at call sites; eases future SDK migration
- **Polling `sbx ls` at 3s** — `sbx` CLI has no event API; matches TUI behavior. FS watchers on `.sbx/` state dirs possible optimization later
- **Chat writes to PTY stdin** — Claude Code is a terminal app; the chat UI wraps terminal input, xterm.js shows actual agent output

---
_Document standards and patterns, not every dependency_
