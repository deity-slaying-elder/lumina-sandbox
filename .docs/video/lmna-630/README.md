# Facility Scheduling feature walkthrough — video source

The Remotion project that produces the Facility Scheduling walkthrough film, vendored here
so a later ticket can pick it up without hunting for it.

The working copy lives **outside** this repo, at `../../LMNA-630-demo-video/`, because the
house video skill requires the video project to sit beside the client repo rather than in
it. What is committed here is the source needed to rebuild, not the working tree.

## What is here

| Path | What it is |
|---|---|
| `remotion/src/` | The film. `Film.tsx` is the timeline, `Driven.tsx` the cursor/camera/ink layer, `screens/Scheduling.tsx` the Salesforce screens rebuilt as driven components. |
| `remotion/public/vo/` | The narration, one wav per caption line. Line length drives caption and scene timing, so these are not regenerable noise — they are the film's clock. |
| `remotion/public/shots/` | Reference captures from lumDev, cropped below the workspace tab strip. |
| `remotion/public/sfx|fonts|brand/` | Mixkit sounds, Permanent Marker and Antonia, Propela marks. |
| `tts/narrate.py` | The narration script and the Kokoro run that renders it. |

## What is deliberately not here

`node_modules` (827MB), the SLDS asset copy and Open Peeps. All reinstallable, and Open
Peeps is not used at all since characters were dropped from the house style.

## Rebuilding

```sh
cd remotion
nvm use 22                 # Remotion renders need Node 22; the default here is 24
npm install
zsh ~/.claude/skills/building-demo-walkthrough-videos/kit/setup-assets.sh   # SLDS etc
npx remotion studio --no-open --port=3123
```

Note the kit script currently dies partway through on its Open Peeps step and so never
reaches the step that copies the UI kit and installs the creative packages. If `src/uikit`
ends up empty, copy it by hand from the skill's `kit/remotion/uikit/`.

## Re-narrating

```sh
cd tts
uv run narrate.py          # local Kokoro, voice af_heart
```

Local Kokoro is used for every preview and review take. Gemini is spent only on the final
cut, and only after it is asked for, because the free tier is about ten calls a day. The
model file is expected at `~/.cache/kokoro/kokoro-v1.0.onnx` with `voices-v1.0.bin` beside
`narrate.py`; neither is committed.

Writing to `remotion/src/script.json` is what ties narration to picture: each line's
measured length becomes its caption duration and its chapter's length, so nothing is
hand-timed and nothing drifts out of sync.

## State at hand-off

Six chapters, about two minutes. Intro poster and search-box lockup, chapter slams,
driven screens with a cursor and a following camera, marker boxes anchored to a target map
of real element rects, word-pop captions, swooshes.

Not done: chapters one, two and five all open on the same worklist screen and need
different framing; boxes can clip at frame edges when the camera is zoomed; no sound on
individual UI actions; and the ship gates (cut rate, dead air, loudness, type floor) have
not been run.
