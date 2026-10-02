---
name: plan-mode-trial-started
description: "James started trialling Claude Code plan mode on 2026-09-01; measured adoption before that date was zero across 2,111 sessions"
metadata: 
  node_type: memory
  type: project
  originSessionId: 31bb5c03-4ce5-4545-8dad-6836d1b3d5b0
  modified: 2026-09-01T18:41:57.176Z
---

James began using **plan mode** on **2026-09-01**, in the M&D Capital Local session
(`ad7ff818`) and the LUMINA `lumDev` session (`00cf129d`). His own words: "I'm now using plan
mode in here I'm trying it now for the first since we were starting to spec everything but
didn't use this."

Measured baseline before that date, over 2,111 sessions / 3 months (2026-06-01 → 2026-09-01):
- **0** genuine `ExitPlanMode` / `EnterPlanMode` tool calls in the windowed corpus
- **1** genuine `ExitPlanMode` in the entire 3,747-file archive, all-time — and it is the
  2026-09-01 trial itself

Raw-grepping transcripts for `ExitPlanMode` returns ~623 files. That is **contamination**, not
adoption: both tool names appear in the deferred-tool list of every system prompt. Only
`tool_use` blocks with `.name == "ExitPlanMode"` count.

**Why:** this matters for any future harness-review question about whether planning helps. There
is no plan-mode bucket to compare against yet, so any claim that plan mode reduces rework would
be invented. The nearest proxy — sessions invoking `superpowers:writing-plans` / `brainstorming`
— is confounded: those sessions run a 242-turn median versus 68 for straight-in work, because
the plan skills get selected onto the hard tasks.

**How to apply:** if asked whether plan mode is working, re-measure adoption first
(`tool_use` names only, never raw grep), and say plainly that n is too small rather than
reading a trend into it. Related: [[docs-live-in-project-not-claude-dir]] covers where the
plan-mode output file should actually be written.
