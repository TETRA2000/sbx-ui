# sbx-ui - Original Project Vision

> **Note**: This document contains the original project vision and requirements. For current project status, see [README.md](README.md).

Docker Sandbox(sbx) based agentic coding environment

## Concept

Secure AI coding environment that suitable from vibe coding to enterprise class


## Requirements

- Grid UI to manager running sandboxes
- Use repository root as project
- Allow all features of sbx from GUI
- Only support Claude Code coding agent for now
- Create a detailed mock of sbx or other external dependencies such as terminals, by examining documents.
	- Use this mock for E2E
- Use stored Claude Code credentials to launch
- Start tasks by sending a message like ChatGPT/Claude like chat UI
	- File embedding support
- Worktree support
- Shared workspaces within projects from different coding agents
- Allow users to customize sbx templates for each projects.
- Allow users to customize sbx templates
- Open iTerm with both attaching current Claude Code session or running terminal(bash)
- Open VSCode or user selected IDEs(Xcode, IntelliJ IDEA)
- Port forwarding
- Notification management
	- Users can view a list of notifications or any requests from sbx in one place
- Initial login flow
  - Sbx can't pass credentials when I use subscriptons


## UI mockup

early mockup is located under ui/



## Timeline


Phase 1: Create minimal MVP

- Users can create a project by selecting the repo root.
- Users can launch sbx from UI
- Users can stop or destory sbx from UI
- Users can manage network policies
- Users can manage port worwarding
- Users can send messages within attached claude code session within the app
- Docker Sandbox and other dependency mocks are available for E2E tests
