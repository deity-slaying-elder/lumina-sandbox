---
name: atlassian-mcp-is-connected
description: Jira/Confluence ARE reachable via the "claude.ai Atlassian" MCP server; the separate "claude.ai Atlassian Rovo" server's auth warning does not mean Jira is unavailable.
metadata:
  type: feedback
---

Two Atlassian MCP servers are configured. `claude.ai Atlassian` (tools `mcp__claude_ai_Atlassian__*`)
is **connected and working**. `claude.ai Atlassian Rovo` is a *separate* server that shows
"Needs Auth". The session-start warning naming "claude.ai Atlassian Rovo" is routinely
misread as meaning all Jira access is down.

Never tell the user Jira is unreachable based on that warning. Just call the tool.

Site: `propela-tech.atlassian.net`, cloudId `2f8270bb-4fcc-45d5-b13a-9ab240817ad7`.

**Why:** James has hit this repeatedly — Claude refuses to fetch a ticket, claims the MCP needs
auth, and stalls a task that could have started immediately.

**How to apply:** When a ticket key is mentioned, load
`mcp__claude_ai_Atlassian__getJiraIssue` via ToolSearch and fetch it. Only report an auth problem
if that specific call actually returns an auth error. See [[propela-jira-project-keys]].
