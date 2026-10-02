---
name: lmna-630-demo-video-state
description: "The LMNA-630 Remotion film: where it lives, how far it got, and the kit bugs that will bite the next film too."
metadata:
  node_type: memory
  type: project
  originSessionId: d4042fdb-61a6-4491-ab0c-3030f035df26
  modified: 2026-10-02T12:10:48.137Z
---

The Facility Scheduling walkthrough film. Working copy is a sibling of the repo at
`LUMINA/LMNA-630-demo-video/`; the source is vendored into the repo at
`.docs/video/lmna-630/` (node_modules, the SLDS copy and Open Peeps left out, 1.0GB down
to 5.3MB). Its README records state at hand-off.

Six chapters, about two minutes, 1920x1080 at 60fps. Narrated with **local Kokoro
`af_heart`** — James, 2026-10-01: Kokoro for every preview and review take, Gemini only
for the final, and ask first, because the free tier is about ten a day. The skill still
says the opposite; see [[video-skill-needs-nine-fixes]].

Review happens in Remotion Studio, not by rendering:
`PATH="$HOME/.nvm/versions/node/v22.23.2/bin:$PATH" npx remotion studio --no-open --port=3123`.
Node 22 is required. Render the MP4 only when James says "render".

**Unfinished:** chapters one, two and five all open on the same worklist screen; marker
boxes can clip at frame edges when the camera is zoomed; no sound on individual UI
actions; the ship gates (cut rate, dead air, loudness, type floor) were never run.

**Things that cost hours and will again:**
- `kit/setup-assets.sh` dies on its Open Peeps step and so never reaches the step that
  copies `src/uikit` and installs the creative packages. Fonts are missing too.
- The kit hardcodes 30fps in `ui.tsx`, `brand.tsx` and `slackkit.tsx`. The slackkit one is
  the damaging one: `Caption` and `Sfx` use its `sec()`, so in a 60fps film every caption
  and sound cue lands at half its intended time.
- Fonts must load through `useKitFonts` (delayRender). A bare `@font-face` renders before
  the file arrives and Permanent Marker falls back to a thin script.
- Annotations: box rectangular targets, circle only round things, one mark per beat, and
  anchor to a map of real element rects. Free-floating arrows placed by eye end up
  pointing at empty space.

Related: [[lmna-630-scheduling-state]], [[local-html-never-artifacts]].
