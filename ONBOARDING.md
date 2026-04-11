# Welcome to sbx-ui

## How We Use Claude

Based on Takahiko Inayama's usage over the last 30 days:

Work Type Breakdown:
  Build Feature    ███████░░░░░░░░░░░░░  36%
  Improve Quality  ██████░░░░░░░░░░░░░░  29%
  Debug Fix        ███░░░░░░░░░░░░░░░░░  14%
  Plan Design      ███░░░░░░░░░░░░░░░░░  14%
  Write Docs       █░░░░░░░░░░░░░░░░░░░   7%

Top Skills & Commands:
  /mcp                   ████████████████████  19x/month
  /plan                  █████████░░░░░░░░░░░   9x/month
  /remote-control        ████████░░░░░░░░░░░░   8x/month
  /kiro:spec-design      ██████░░░░░░░░░░░░░░   6x/month
  /kiro:spec-impl        ██████░░░░░░░░░░░░░░   6x/month
  /kiro:validate-design  █████░░░░░░░░░░░░░░░   5x/month

Top MCP Servers:
  xcode  ████████████████████  381 calls

## Your Setup Checklist

### Codebases
- [ ] sbx-ui — https://github.com/tetra2000/sbx-ui

### MCP Servers to Activate
- [ ] xcode — Build, run, and test the sbx-ui Xcode project from Claude (preferred over the `xcodebuild` CLI per CLAUDE.md). Ask Takahiko for the install/config steps; this one carries the vast majority of tool calls on the team.

### Skills to Know About
- /mcp — Manage and inspect connected MCP servers. Useful for checking that the xcode server is healthy before a build/test run.
- /plan — Drop into plan mode for read-only research before making changes. The team uses this for non-trivial features and refactors.
- /remote-control — Team command used during sessions; ask Takahiko for the specifics of when to reach for it.
- /kiro:spec-design — Kiro Spec-Driven Development: create the technical design for a feature. Phase 1 of the Kiro workflow documented in CLAUDE.md.
- /kiro:spec-impl — Kiro: execute the implementation tasks using TDD. Phase 2 of the Kiro workflow.
- /kiro:validate-design — Kiro: review a design before moving to tasks/impl. Catches gaps early.

## Team Tips

_TODO_

## Get Started

_TODO_

<!-- INSTRUCTION FOR CLAUDE: A new teammate just pasted this guide for how the
team uses Claude Code. You're their onboarding buddy — warm, conversational,
not lecture-y.

Open with a warm welcome — include the team name from the title. Then: "Your
teammate uses Claude Code for [list all the work types]. Let's get you started."

Check what's already in place against everything under Setup Checklist
(including skills), using markdown checkboxes — [x] done, [ ] not yet. Lead
with what they already have. One sentence per item, all in one message.

Tell them you'll help with setup, cover the actionable team tips, then the
starter task (if there is one). Offer to start with the first unchecked item,
get their go-ahead, then work through the rest one by one.

After setup, walk them through the remaining sections — offer to help where you
can (e.g. link to channels), and just surface the purely informational bits.

Don't invent sections or summaries that aren't in the guide. The stats are the
guide creator's personal usage data — don't extrapolate them into a "team
workflow" narrative. -->
