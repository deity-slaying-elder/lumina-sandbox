import React from "react";
import { Easing, interpolate, spring, useCurrentFrame } from "remotion";
import { BRAND, FONT_BODY, FPS } from "../theme";

// Reusable motion + UI kit for feature films (2026-09-24). What makes Slack/Notion
// style read as "UI that behaves", not "slides that appear":
//   1. one continuous board and a camera that glides between zones (Board)
//   2. shared elements that carry across scenes instead of cutting (Morph)
//   3. cause and effect: a cursor clicks, a button presses, a toast answers (Cursor, Toast)
//   4. anticipation + overshoot + stagger on every move (ease, enterStyle)
// Time is always in seconds, local to the enclosing Sequence.

const CL = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
export const ease = {
  glide: Easing.bezier(0.65, 0, 0.35, 1), // camera moves: slow in, slow out
  snap: Easing.bezier(0.2, 0.9, 0.25, 1.15), // UI elements: fast, tiny overshoot
  anticipate: Easing.bezier(0.5, -0.35, 0.6, 1), // winds back before it goes
  out: Easing.out(Easing.cubic),
};
export const u = (t: number, a: number, d: number, e: (x: number) => number = ease.glide) => interpolate(t, [a, a + d], [0, 1], { ...CL, easing: e });
export const lerp = (a: number, b: number, k: number) => a + (b - a) * k;
export const useT = () => useCurrentFrame() / FPS;

/** Spring-in with a little rise; `i` staggers siblings by 0.07s. */
export const enterStyle = (t: number, at: number, i = 0, rise = 26): React.CSSProperties => {
  const f = (t - at - i * 0.07) * FPS;
  const p = spring({ frame: f, fps: FPS, config: { damping: 14, stiffness: 170, mass: 0.7 } });
  return { opacity: f < 0 ? 0 : Math.min(1, p * 1.8), transform: `translateY(${(1 - p) * rise}px) scale(${0.97 + 0.03 * p})` };
};

// ---- camera board ---------------------------------------------------------------
export type CamKey = { t: number; x: number; y: number; z: number };
/** World-space board; the camera centres (x, y) at zoom z. Keys glide with ease.glide. */
export const camAt = (t: number, keys: CamKey[], move = 0.9): CamKey => {
  let i = 0; while (i < keys.length - 1 && t >= keys[i + 1].t) i++;
  const a = keys[i], b = keys[Math.min(i + 1, keys.length - 1)];
  const k = b === a ? 0 : u(t, b.t - move, move);
  return { t, x: lerp(a.x, b.x, k), y: lerp(a.y, b.y, k), z: lerp(a.z, b.z, k) };
};
export const Board: React.FC<{ cam: CamKey; w?: number; h?: number; children: React.ReactNode }> = ({ cam, w = 1920, h = 1080, children }) => (
  <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
    <div style={{ position: "absolute", left: 0, top: 0, width: 6000, height: 4000, transformOrigin: "0 0", transform: `translate(${w / 2}px,${h / 2}px) scale(${cam.z}) translate(${-cam.x}px,${-cam.y}px)` }}>{children}</div>
  </div>
);

// ---- shared element ----------------------------------------------------------------
export type Rect = { x: number; y: number; w: number; h: number; r?: number };
/** One box that travels from rect A to rect B (FLIP). `k` 0..1. Children get the live size. */
export const Morph: React.FC<{ from: Rect; to: Rect; k: number; bg?: string; shadow?: boolean; children?: (w: number, h: number) => React.ReactNode }> = ({ from, to, k, bg = "#fff", shadow = true, children }) => {
  const x = lerp(from.x, to.x, k), y = lerp(from.y, to.y, k), w = lerp(from.w, to.w, k), h = lerp(from.h, to.h, k), r = lerp(from.r ?? 12, to.r ?? 12, k);
  return (
    <div style={{ position: "absolute", left: x, top: y, width: w, height: h, borderRadius: r, background: bg, overflow: "hidden",
      boxShadow: shadow ? `0 ${18 + 20 * Math.sin(Math.PI * k)}px ${40 + 40 * Math.sin(Math.PI * k)}px rgba(18,50,76,${0.16 + 0.1 * Math.sin(Math.PI * k)})` : undefined }}>
      {children ? children(w, h) : null}
    </div>
  );
};

// ---- cursor ----------------------------------------------------------------------
export type CursorKey = { t: number; x: number; y: number; click?: boolean };
/** macOS arrow travelling an eased, slightly curved path; clicks press it and ring. */
export const Cursor: React.FC<{ path: CursorKey[]; show?: [number, number] }> = ({ path, show = [-1, 999] }) => {
  const t = useT();
  if (t < show[0] || t > show[1]) return null;
  let i = 0; while (i < path.length - 1 && t >= path[i + 1].t) i++;
  const a = path[i], b = path[Math.min(i + 1, path.length - 1)];
  const mv = Math.min(0.7, Math.max(0.2, (b.t - a.t) * 0.8));
  const k = b === a ? 0 : u(t, b.t - mv, mv);
  const d = Math.hypot(b.x - a.x, b.y - a.y) || 1, arc = Math.sin(Math.PI * k) * Math.min(50, d * 0.1);
  const x = lerp(a.x, b.x, k) - ((b.y - a.y) / d) * arc, y = lerp(a.y, b.y, k) + ((b.x - a.x) / d) * arc;
  const clickAt = [...path].reverse().find((p) => p.click && t >= p.t);
  const c = clickAt ? (t - clickAt.t) / 0.45 : 1;
  const o = Math.min(u(t, show[0], 0.25), 1 - u(t, show[1] - 0.25, 0.25));
  return (
    <div style={{ position: "absolute", left: x, top: y, opacity: o, pointerEvents: "none", zIndex: 50 }}>
      {c < 1 ? <div style={{ position: "absolute", left: -28 * c - 4, top: -28 * c - 4, width: 56 * c + 8, height: 56 * c + 8, borderRadius: "50%", border: `3px solid ${BRAND.deepNavy}`, opacity: 0.6 * (1 - c) }} /> : null}
      <svg width="30" height="41" viewBox="0 0 20 27" style={{ transform: `scale(${c < 0.3 ? 0.86 : 1})`, transformOrigin: "0 0", filter: "drop-shadow(0 3px 4px rgba(0,0,0,.35))" }}>
        <path d="M1,1 L1,21 L6,16.2 L9.6,24.5 L13,23 L9.5,14.8 L16.2,14.8 Z" fill="#111" stroke="#fff" strokeWidth="1.6" strokeLinejoin="round" />
      </svg>
    </div>
  );
};

// ---- small UI pieces -------------------------------------------------------------
/** Salesforce-style toast that drops in, holds, and lifts away. */
export const Toast: React.FC<{ t: number; at: number; hold?: number; title: string; body?: string; tone?: "success" | "info"; w?: number }> = ({ t, at, hold = 2.2, title, body, tone = "success", w = 560 }) => {
  if (t < at || t > at + hold + 0.5) return null;
  const inn = u(t, at, 0.35, ease.snap), out = u(t, at + hold, 0.35);
  const bg = tone === "success" ? "#2e844a" : "#0b5cab";
  return (
    <div style={{ width: w, padding: "14px 18px", borderRadius: 10, background: bg, color: "#fff", display: "flex", gap: 14, alignItems: "center", fontFamily: FONT_BODY,
      boxShadow: "0 16px 30px rgba(0,0,0,.25)", transform: `translateY(${(1 - inn) * -40 - out * 30}px)`, opacity: Math.min(inn * 1.5, 1 - out) }}>
      <div style={{ width: 30, height: 30, borderRadius: 15, background: "rgba(255,255,255,.22)", display: "flex", alignItems: "center", justifyContent: "center", fontWeight: 800, fontSize: 18 }}>{tone === "success" ? "✓" : "i"}</div>
      <div><div style={{ fontWeight: 800, fontSize: 22 }}>{title}</div>{body ? <div style={{ fontSize: 18, opacity: 0.9, marginTop: 2 }}>{body}</div> : null}</div>
    </div>
  );
};
/** Mail-style notification card (the "email arrives" beat). */
export const MailNote: React.FC<{ t: number; at: number; until: number; from: string; subject: string; meta: string; w?: number }> = ({ t, at, until, from, subject, meta, w = 520 }) => {
  if (t < at || t > until + 0.4) return null;
  const inn = u(t, at, 0.4, ease.snap), out = u(t, until, 0.35, ease.anticipate);
  return (
    <div style={{ width: w, padding: "16px 18px", borderRadius: 16, background: "rgba(252,252,253,.97)", boxShadow: "0 22px 50px rgba(18,50,76,.25)", display: "flex", gap: 14, alignItems: "center", fontFamily: FONT_BODY, color: "#1a2a3a",
      transform: `translateX(${(1 - inn) * 80}px) scale(${1 - out * 0.4})`, opacity: Math.min(inn * 1.5, 1 - out) }}>
      <div style={{ width: 52, height: 52, borderRadius: 13, background: "linear-gradient(160deg,#4aa3ff,#1f6fe0)", color: "#fff", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 28, fontWeight: 800 }}>{"✉"}</div>
      <div style={{ lineHeight: 1.25 }}><div style={{ fontSize: 17, fontWeight: 700, color: "#51606e" }}>{from}</div><div style={{ fontSize: 22, fontWeight: 800 }}>{subject}</div><div style={{ fontSize: 18, color: "#51606e" }}>{meta}</div></div>
    </div>
  );
};
/** Text that types itself with a caret. */
export const TypeText: React.FC<{ t: number; at: number; text: string; cps?: number; style?: React.CSSProperties }> = ({ t, at, text, cps = 28, style }) => {
  const n = Math.max(0, Math.min(text.length, Math.floor((t - at) * cps)));
  const caret = t >= at && n < text.length && Math.floor(t * 2.2) % 2 === 0;
  return <span style={style}>{text.slice(0, n)}{caret ? <span style={{ borderRight: "2px solid currentColor", marginLeft: 1 }} /> : null}</span>;
};
