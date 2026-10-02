import React from "react";
import { AbsoluteFill } from "remotion";
import { BRAND } from "./theme";
import { useT, u, ease, lerp, Cursor } from "./uikit/ui";
import { Ink, Stroke, ellipse, curve, heads, line, Pt } from "./uikit/ink";
import { Highlight } from "@remotion/rough-notation";
import { APP_W, APP_H } from "./screens/Scheduling";

// Makes a rebuilt screen read as something being driven rather than something playing:
// a cursor travels and clicks, the camera follows it and zooms into whatever it just
// touched, and marker notes with leader arrows name the thing on screen.
//
// Beats are written in APP pixels (1440x810), because that is the geometry the screens
// are built at, and projected to the 1920x1080 frame here.

const S = 1920 / APP_W; // app pixel -> frame pixel
const W = 1920;
const H = 1080;

export type Beat = {
  at: number;
  x: number;
  y: number;
  z?: number;
  click?: boolean;
};

export type Note = {
  at: number;
  x: number; // where the words sit
  y: number;
  text: string;
  to?: [number, number]; // the thing the words are about; gets a leader arrow
  ring?: [number, number, number, number]; // cx, cy, rx, ry — only for round targets
  /** x, y, w, h in app pixels. A marker box: the right shape for a panel, tile or field. */
  box?: [number, number, number, number];
  until?: number;
};

/** Camera: lags the cursor, zooms in when it settles, and never reveals past the edge. */
const camera = (beats: Beat[], t: number) => {
  if (!beats.length) return { x: W / 2, y: H / 2, z: 1 };
  let i = 0;
  while (i < beats.length - 1 && t >= beats[i + 1].at) i++;
  const a = beats[i];
  const b = beats[Math.min(i + 1, beats.length - 1)];
  // Move over 0.75s, arriving at the beat, so the camera trails rather than snaps.
  const k = b === a ? 1 : u(t, b.at - 0.75, 0.75, ease.glide);
  const x = lerp(a.x, b.x, k) * S;
  const y = lerp(a.y, b.y, k) * S;
  const z = lerp(a.z ?? 1, b.z ?? 1, k);
  return { x, y, z };
};


/** Marker box round a rect: four overshooting sides, drawn in order. */
const boxPath = (x: number, y: number, w: number, h: number): Pt[] => {
  const o = 7; // overshoot past each corner, so it reads as drawn not plotted
  return [
    ...line([x - o, y], [x + w + o, y], 12),
    ...line([x + w, y - o * 0.4], [x + w, y + h + o * 0.4], 10),
    ...line([x + w + o, y + h], [x - o, y + h], 12),
    ...line([x, y + h + o * 0.4], [x, y - o * 0.4], 10),
  ];
};

const clampT = (v: number, span: number, z: number) => Math.min(0, Math.max(span - span * z, v));

export const Driven: React.FC<{
  beats: Beat[];
  notes?: Note[];
  children: React.ReactNode;
  /** Seconds offset: beats are written relative to the chapter body, not the sequence. */
  t0?: number;
}> = ({ beats, notes = [], children, t0 = 0 }) => {
  const t = useT() - t0;
  const cam = camera(beats, t);
  const tx = clampT(W / 2 - cam.x * cam.z, W, cam.z);
  const ty = clampT(H / 2 - cam.y * cam.z, H, cam.z);

  // World -> screen, so the cursor and the ink never scale with the zoom.
  const px = (ax: number) => tx + ax * S * cam.z;
  const py = (ay: number) => ty + ay * S * cam.z;

  // Two bands belong to other things: the caption owns everything below 830, and the
  // chapter pill owns the top left. A note that drifts into either reads as a collision,
  // so notes are clamped into the free area rather than trusted to hand-picked numbers.
  const NOTE_L = 60, NOTE_R = 1430, NOTE_T = 150, NOTE_B = 760;
  const nx = (ax: number) => Math.min(NOTE_R, Math.max(NOTE_L, px(ax)));
  const ny = (ay: number) => Math.min(NOTE_B, Math.max(NOTE_T, py(ay)));

  const path = beats.map((b) => ({ t: b.at, x: px(b.x), y: py(b.y), click: b.click }));

  const strokes: Stroke[] = [];
  notes.forEach((n, i) => {
    const p = u(t, n.at, 0.55);
    const gone = n.until ? u(t, n.until, 0.3) : 0;
    if (p <= 0 || gone >= 1) return;
    if (n.ring) {
      const [cx, cy, rx, ry] = n.ring;
      strokes.push({
        pts: ellipse(px(cx), py(cy), rx * S * cam.z, ry * S * cam.z, `ring${i}`),
        p,
        color: BRAND.deepNavy,
        width: 5,
        seed: `ring${i}`,
        halo: "#fff",
      });
    }
    if (n.box) {
      const [bx, by, bw, bh] = n.box;
      strokes.push({
        pts: boxPath(px(bx), py(by), bw * S * cam.z, bh * S * cam.z),
        p,
        color: BRAND.deepNavy,
        width: 5,
        seed: `box${i}`,
        halo: "#fff",
      });
    }
    if (n.to) {
      // Start the leader at whichever edge of the note faces the target, so the arrow is
      // the short hop a person would draw rather than a diagonal across the screen.
      const tx2 = px(n.to[0]);
      const ty2 = py(n.to[1]);
      const left = nx(n.x);
      const top = ny(n.y);
      const fromX = tx2 < left ? left - 8 : left + 150;
      const fromY = ty2 < top ? top - 6 : top + 44;
      const from: Pt = [fromX, fromY];
      const to: Pt = [tx2, ty2];
      const dist = Math.hypot(to[0] - from[0], to[1] - from[1]);
      const pts = curve(from, to, Math.min(38, dist * 0.2));
      strokes.push({
        pts,
        p,
        color: BRAND.deepNavy,
        width: 5,
        seed: `arr${i}`,
        halo: "#fff",
        heads: heads(pts, 26),
        hp: u(t, n.at + 0.45, 0.25),
      });
    }
  });

  return (
    <AbsoluteFill>
      <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
        <div
          style={{
            position: "absolute",
            left: 0,
            top: 0,
            width: W,
            height: H,
            transformOrigin: "0 0",
            transform: `translate(${tx}px, ${ty}px) scale(${cam.z})`,
          }}
        >
          {children}
        </div>
      </div>

      <Ink strokes={strokes} />

      {/* Marker notes sit at screen size so they stay legible at any zoom. */}
      {notes.map((n, i) => {
        const p = u(t, n.at + 0.1, 0.45);
        const gone = n.until ? u(t, n.until, 0.3) : 0;
        if (p <= 0 || gone >= 1) return null;
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: nx(n.x),
              top: ny(n.y),
              opacity: 1 - gone,
              transform: `rotate(-1.6deg)`,
            }}
          >
            {/* A highlighter swipe BEHIND the words, not an outline around each letter.
                The outline version filled the letter holes and read as a glow; a marker
                pass behind solid navy text is how annotation is actually drawn. */}
            <Highlight
              progress={p}
              color="rgba(245,253,126,0.85)"
              iterations={2}
              padding={{ left: 14, right: 14, top: 6, bottom: 4 }}
            >
              <span
                style={{
                  fontFamily: "'Permanent Marker', cursive",
                  fontSize: 38,
                  lineHeight: 1.12,
                  color: BRAND.deepNavy,
                  whiteSpace: "pre",
                  display: "inline-block",
                }}
              >
                {n.text}
              </span>
            </Highlight>
          </div>
        );
      })}

      <Cursor path={path} />
    </AbsoluteFill>
  );
};
