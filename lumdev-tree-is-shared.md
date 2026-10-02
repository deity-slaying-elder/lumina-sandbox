---
name: lumdev-tree-is-shared
description: Several Claude sessions drive the one lumDev working tree, so another session's checkout moves your HEAD mid-task; use a worktree.
metadata:
  type: project
---

Multiple Claude sessions operate on the **same** lumDev working tree at once. On
2026-10-02 a third session checked out `main` partway through a commit here, so work
intended for `LMNA-630-scheduling-ui` landed on `main` instead. Nothing broke, but the
branch had to be repointed afterwards.

So: before committing, check `git branch --show-current` again rather than trusting where
you were earlier in the session. And for anything longer than a couple of commands, use
`git worktree add` instead of sharing the tree.

Coordinate before pushing `main` — peers are reachable with SendMessage and will hold.
Also check `origin/main..main` first: local main carried three unpushed commits, so a push
meant for one commit published three.

Related: [[lmna-630-scheduling-state]].
