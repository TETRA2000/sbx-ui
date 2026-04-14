# Product Overview

sbx-ui is a dual-surface developer tool that wraps the Docker Sandbox (`sbx`) CLI: a native **macOS SwiftUI desktop GUI** and a cross-platform **Linux CLI** (`sbx-ui-cli`). It lets developers manage secure, containerized AI coding environments — including Claude Code agent sessions — without memorizing `sbx` subcommands.

## Core Capabilities

- **Sandbox lifecycle** — create, resume, stop, terminate Docker Sandbox containers tied to a workspace directory
- **Agent & shell sessions** — embedded terminal sessions (Claude Code agent or bash) with multi-session sidebar switching and live dashboard thumbnails
- **Kanban task orchestration** — drag-and-drop boards with dependency chaining and auto-execution that drive agent prompts into sandbox terminals
- **Network policies & port forwarding** — global allow/deny rules with activity log; per-sandbox host-to-sandbox port mappings
- **Environment variables** — per-sandbox persistent vars written to `/etc/sandbox-persistent.sh` with managed-section markers that preserve user edits

## Target Use Cases

- Developers running multiple isolated Claude Code agents in parallel, each scoped to a separate workspace
- Teams that need auditable network egress controls and port exposure for AI-driven development
- Security-conscious "vibe coding through enterprise-class" workflows where agents must run in sandboxed containers rather than on the host

## Value Proposition

- **GUI-first for a CLI-native tool.** Exposes the full `sbx` surface area (lifecycle, policies, ports, env, exec) through a discoverable UI — no terminal memorization required.
- **Shared core across surfaces.** The GUI and Linux CLI share the same domain types, service protocol, and CLI executor, so behavior stays consistent wherever the tool runs.
- **Test without Docker.** A bash mock of the `sbx` CLI (`tools/mock-sbx`) exercises the full code path end-to-end, so unit, integration, and UI tests all run without Docker Desktop.
- **Persistent-but-preserving.** Managed-section markers in generated sandbox files let the product own its config without overwriting user edits.

---
_Focus on patterns and purpose, not exhaustive feature lists_
