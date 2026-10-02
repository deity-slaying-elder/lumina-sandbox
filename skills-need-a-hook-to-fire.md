---
name: skills-need-a-hook-to-fire
description: Skills in ~/.claude/skills do not fire on their own; James wants a UserPromptSubmit router, and I cannot install it myself.
metadata:
  type: feedback
---

On 2026-10-01 I built a demo video from scratch without ever checking
`~/.claude/skills/`, which holds `building-demo-walkthrough-videos` plus a kit, a
reference set and a settled stack. Everything I produced was wrong in a way the skill
already answers.

**Why:** James's own CLAUDE.md measured it — mandatory skills fire at 1.5% and 6.8% of the
sessions that need them, because noticing mid-work that a rule applies does not survive
context saturation. The same session proved the contrast: his `validate-bash.sh`
PreToolUse hook blocked an `sf` call missing `--json` every single time.

**How to apply:** check the skills directory at the start of any task that smells like a
house process (video, HTML deliverable, Jira ticket, LWC/SLDS work, a draft to a person),
not when it occurs to you. Read `SKILL.md` directly if the Skill tool does not list it.

James asked for a `UserPromptSubmit` hook routing intent to the right skill. **The harness
denies me writes to `~/.claude/hooks/` and `~/.claude/skills/` as self-modification**, so
he applies those himself; I hand him the exact prompt or patch instead. Two other gaps
worth naming: `remind-slds-ui.sh` matches only Edit|Write, so edits made through `python3`
heredocs in Bash walk straight past it, and there is no guard stopping an ffmpeg encode
outside a Remotion project.

Related: [[lmna-630-demo-video-state]], [[video-skill-needs-nine-fixes]].
