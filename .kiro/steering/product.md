# Product Overview

**sbx-ui** is a desktop GUI for Docker Sandbox (`sbx`) — a secure, container-based environment for AI coding agents. It replaces the CLI workflow with a visual dashboard where developers can manage sandboxes, network policies, port forwarding, and interact with Claude Code sessions through a chat-style interface.

## Core Capabilities

1. **Sandbox lifecycle management** — Create, launch, stop, and destroy sandboxes from a grid dashboard tied to local Git repositories
2. **Network policy control** — Allow/deny domain-level network access rules with activity logging
3. **Port forwarding** — Publish and manage host↔sandbox port mappings per sandbox
4. **Claude Code session interaction** — Chat-style message input with embedded terminal view showing real Claude Code output
5. **Mock-driven development** — Full in-memory mock of the `sbx` CLI enables development and E2E testing without Docker Desktop

## Target Use Cases

- Developers who use Docker Sandbox for AI-assisted coding but prefer a GUI over CLI
- Teams that need visibility into sandbox network activity and resource usage
- CI/E2E testing of sandbox workflows without requiring Docker infrastructure

## Value Proposition

A single-pane-of-glass for sandbox management that makes the `sbx` CLI accessible to non-terminal users while preserving full control over security policies and agent interactions. The mock-first architecture ensures fast iteration and testability.

## Phased Delivery

- **Phase 1 (current)**: Minimal MVP — project creation, sandbox CRUD, policies, ports, chat session, mocks for E2E
- **Phase 2+**: Worktree/branch UI, multi-agent support, IDE integrations, notification center, template customization, shared workspaces

---
_Focus on patterns and purpose, not exhaustive feature lists_
