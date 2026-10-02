import React, { useLayoutEffect, useRef } from "react";
import { noise2D } from "@remotion/noise";
import { useCurrentFrame } from "remotion";

// Hand-drawn ink on a canvas (restored 2026-09-24: James liked the collage's arrows and
// handwriting, not the collage). Points "boil" on twos like hand animation; segments taper
// like a marker. Draw-on progress p is 0..1; arrow heads draw after the body.

export type Pt = [number, number];
export type Stroke = { pts: Pt[]; p: number; color: string; width: number; seed: string; alpha?: number; boil?: number; heads?: Pt[][]; hp?: number; halo?: string };

const lerp = (a: number, b: number, k: number) => a + (b - a) * k;
export const curve = (a: Pt, b: Pt, bend: number, n = 48): Pt[] => {
  const dx = b[0] - a[0], dy = b[1] - a[1], L = Math.hypot(dx, dy) || 1;
  const c: Pt = [(a[0] + b[0]) / 2 - (dy / L) * bend, (a[1] + b[1]) / 2 + (dx / L) * bend];
  return Array.from({ length: n + 1 }, (_, k) => { const u = k / n, v = 1 - u; return [v * v * a[0] + 2 * v * u * c[0] + u * u * b[0], v * v * a[1] + 2 * v * u * c[1] + u * u * b[1]] as Pt; });
};
export const line = (a: Pt, b: Pt, n = 16): Pt[] => Array.from({ length: n + 1 }, (_, k) => [lerp(a[0], b[0], k / n), lerp(a[1], b[1], k / n)] as Pt);
export const heads = (pts: Pt[], size = 22): Pt[][] => {
  const e = pts[pts.length - 1], p = pts[Math.max(0, pts.length - 7)], ang = Math.atan2(e[1] - p[1], e[0] - p[0]);
  return [0.5, -0.5].map((d) => line(e, [e[0] - size * Math.cos(ang + d), e[1] - size * Math.sin(ang + d)], 8));
};
export const ellipse = (cx: number, cy: number, rx: number, ry: number, seed: string, turns = 1.12, start = -2.6, n = 90): Pt[] =>
  Array.from({ length: n + 1 }, (_, k) => { const u = k / n, a = start + turns * Math.PI * 2 * u, r = 1 + 0.06 * noise2D(seed, u * 3, 0) + 0.05 * u; return [cx + rx * r * Math.cos(a), cy + ry * r * Math.sin(a)] as Pt; });

const pass = (g: CanvasRenderingContext2D, pts: Pt[], upto: number, w: number, alpha: number, ox: number, oy: number) => {
  const n = pts.length - 1, last = Math.min(n, Math.ceil(upto));
  for (let i = 1; i <= last; i++) {
    let [x1, y1] = pts[i]; const [x0, y0] = pts[i - 1];
    if (i > upto) { const f = upto - (i - 1); x1 = lerp(x0, x1, f); y1 = lerp(y0, y1, f); }
    g.globalAlpha = alpha * (0.85 + 0.15 * Math.sin(i * 0.9)); g.lineWidth = w * Math.min(1, 0.35 + i / 7, 0.35 + (n - i) / 7);
    g.beginPath(); g.moveTo(x0 + ox, y0 + oy); g.lineTo(x1 + ox, y1 + oy); g.stroke();
  }
};
export const drawStroke = (g: CanvasRenderingContext2D, s: Stroke, frame: number) => {
  if (s.p <= 0) return;
  const k = Math.floor(frame / 2), b = s.boil ?? 1.4, a = s.alpha ?? 0.95;
  const jig = (pts: Pt[], tag: string) => pts.map((q, i) => [q[0] + noise2D(s.seed + tag + "x", i * 0.13, k * 0.9) * b, q[1] + noise2D(s.seed + tag + "y", i * 0.13, k * 0.9) * b] as Pt);
  const pts = jig(s.pts, ""); const upto = s.p * (pts.length - 1);
  g.save(); g.lineCap = "round"; g.lineJoin = "round";
  if (s.halo) { // white outline under the ink so it reads over any UI (James, 2026-09-25)
    g.strokeStyle = s.halo; pass(g, pts, upto, s.width + 8, 1, 0, 0);
    if (s.heads && s.p >= 1) s.heads.forEach((h, i) => { const hj = jig(h, "h" + i); pass(g, hj, (s.hp ?? 1) * (hj.length - 1), s.width + 8, 1, 0, 0); });
  }
  g.strokeStyle = s.color;
  pass(g, pts, upto, s.width, a, 0, 0); pass(g, pts, upto, s.width * 0.42, a * 0.45, 0.9, 0.7);
  if (s.heads && s.p >= 1) s.heads.forEach((h, i) => { const hj = jig(h, "h" + i); pass(g, hj, (s.hp ?? 1) * (hj.length - 1), s.width, a, 0, 0); });
  g.restore();
};

/** Full-frame canvas that draws the given strokes every frame. */
export const Ink: React.FC<{ strokes: Stroke[]; w?: number; h?: number }> = ({ strokes, w = 1920, h = 1080 }) => {
  const ref = useRef<HTMLCanvasElement>(null); const frame = useCurrentFrame();
  useLayoutEffect(() => { const c = ref.current; if (!c) return; const g = c.getContext("2d")!; g.clearRect(0, 0, w, h); strokes.forEach((s) => drawStroke(g, s, frame)); });
  return <canvas ref={ref} width={w} height={h} style={{ position: "absolute", left: 0, top: 0, pointerEvents: "none" }} />;
};

export const HAND = "'Caveat', cursive";
/** Handwriting that writes itself on left to right. */
export const Handwrite: React.FC<{ t: number; at: number; dur?: number; size?: number; color?: string; rot?: number; children: React.ReactNode }> = ({ t, at, dur = 0.7, size = 44, color = "#0C263B", rot = -2, children }) => {
  if (t < at) return null;
  const p = Math.min(1, (t - at) / dur);
  return <div style={{ fontFamily: HAND, fontSize: size, fontWeight: 600, lineHeight: 1, color, whiteSpace: "nowrap", rotate: `${rot}deg`, clipPath: `inset(-30px ${(1 - p) * 100}% -30px -30px)` }}>{children}</div>;
};
