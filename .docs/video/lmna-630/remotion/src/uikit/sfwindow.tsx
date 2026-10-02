import React from "react";
import { Img, staticFile, spring, useCurrentFrame } from "remotion";
import { BRAND } from "../theme";

// A real Salesforce capture in a plain Mac window, with the Salesforce header
// PINNED while the page below zooms (James, 2026-09-24: "at least still show
// that it's still in Salesforce"). Overlays passed as children are positioned in
// IMAGE pixels inside the same transform, so they stay locked to the field at any
// zoom. `sfToWorld` gives the same mapping for things drawn outside (the cursor).

export type Focus = { x: number; y: number; z: number };
export type SfSpec = { x: number; y: number; w: number; h: number; imgW?: number; imgH: number; headerH: number; bar?: number };

const layout = (s: SfSpec, f?: Focus) => {
  const imgW = s.imgW ?? 1600, bar = s.bar ?? 38, k = s.w / imgW, hdr = s.headerH * k, vh = s.h - bar - hdr;
  const z = f?.z ?? 1, fx = f?.x ?? imgW / 2, fy = f?.y ?? s.headerH + vh / k / 2;
  const sc = k * z;
  let tx = s.w / 2 - fx * sc, ty = vh / 2 - fy * sc;
  tx = Math.min(0, Math.max(s.w - imgW * sc, tx));
  ty = Math.min(-s.headerH * sc, Math.max(vh - s.imgH * sc, ty));
  return { k, bar, hdr, vh, sc, tx, ty, imgW };
};
/** World position of an image point, for overlays drawn outside the window (cursor, leader lines). */
export const sfToWorld = (s: SfSpec, f: Focus | undefined, ix: number, iy: number): [number, number] => {
  const L = layout(s, f);
  return [s.x + L.tx + ix * L.sc, s.y + L.bar + L.hdr + L.ty + iy * L.sc];
};

export const SfWindow: React.FC<{ spec: SfSpec; src: string; title: string; focus?: Focus; children?: React.ReactNode; shine?: number; pinHeader?: boolean }> = ({ spec, src, title, focus, children, shine, pinHeader = true }) => {
  const L = layout(pinHeader ? spec : { ...spec, headerH: 0 }, focus);
  return (
    <div style={{ position: "absolute", left: spec.x, top: spec.y, width: spec.w, height: spec.h, borderRadius: 14, overflow: "hidden", background: "#fff", boxShadow: "0 40px 90px rgba(18,50,76,.28), 0 0 0 1px rgba(0,0,0,.18)" }}>
      <div style={{ height: L.bar, background: "linear-gradient(#eeeef0,#e2e2e5)", borderBottom: "1px solid #cfcfd3", display: "flex", alignItems: "center", gap: 8, padding: "0 14px", position: "relative" }}>
        {["#ff5f57", "#febc2e", "#28c840"].map((c) => <div key={c} style={{ width: 13, height: 13, borderRadius: 7, background: c }} />)}
        <div style={{ position: "absolute", left: 80, right: 80, textAlign: "center", fontFamily: "system-ui,-apple-system,sans-serif", fontSize: 16, fontWeight: 600, color: "#4a4a4f", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{title}</div>
      </div>
      {pinHeader && spec.headerH > 0 ? (
        <div style={{ position: "absolute", left: 0, top: L.bar, width: spec.w, height: L.hdr, overflow: "hidden", zIndex: 2, boxShadow: "0 3px 8px rgba(0,0,0,.08)" }}>
          <Img src={staticFile(src)} style={{ position: "absolute", left: 0, top: 0, width: spec.w }} />
        </div>
      ) : null}
      <div style={{ position: "absolute", left: 0, top: L.bar + (pinHeader ? L.hdr : 0), width: spec.w, height: L.vh, overflow: "hidden" }}>
        <div style={{ position: "absolute", left: 0, top: 0, width: L.imgW, height: spec.imgH, transformOrigin: "0 0", transform: `translate(${L.tx}px,${L.ty}px) scale(${L.sc})` }}>
          <Img src={staticFile(src)} style={{ position: "absolute", left: 0, top: 0, width: L.imgW }} />
          {children}
        </div>
      </div>
      {shine !== undefined && shine > 0 && shine < 1 ? <div style={{ position: "absolute", top: 0, bottom: 0, width: 260, left: -300 + shine * (spec.w + 600), background: "linear-gradient(100deg, transparent, rgba(255,255,255,.55), transparent)", mixBlendMode: "screen", pointerEvents: "none", zIndex: 3 }} /> : null}
    </div>
  );
};

/** Lock-on highlight in image pixels: springs in slightly large, settles, breathes. */
export const Glow: React.FC<{ r: [number, number, number, number]; at: number; until?: number; color?: string; label?: string; labelSide?: "top" | "bottom" }> = ({ r, at, until = 999, color = BRAND.techYellow, label, labelSide = "top" }) => {
  const frame = useCurrentFrame(); const t = frame / 30;
  if (t < at || t > until) return null;
  const p = spring({ frame: frame - Math.round(at * 30), fps: 30, config: { damping: 13, stiffness: 190, mass: 0.6 } });
  const out = until < 999 ? Math.min(1, Math.max(0, (until - t) / 0.25)) : 1;
  const pad = 6 + (1 - p) * 18, breathe = 0.5 + 0.5 * Math.sin(t * 5);
  return (
    <div style={{ position: "absolute", left: r[0] - pad, top: r[1] - pad, width: r[2] + pad * 2, height: r[3] + pad * 2, borderRadius: 8, border: `3px solid ${color}`, background: `${color}22`, opacity: Math.min(1, p * 2) * out,
      boxShadow: `0 0 ${10 + 12 * breathe}px ${color}, inset 0 0 0 1px ${BRAND.deepNavy}33` }}>
      {label ? <div style={{ position: "absolute", left: -3, [labelSide === "top" ? "bottom" : "top"]: "100%", marginBottom: labelSide === "top" ? 6 : 0, marginTop: labelSide === "bottom" ? 6 : 0, padding: "3px 10px", borderRadius: 6, background: BRAND.deepNavy, color, fontFamily: "'DM Sans', Tahoma, sans-serif", fontSize: 18, fontWeight: 800, letterSpacing: 1.5, whiteSpace: "nowrap" }}>{label}</div> : null}
    </div>
  );
};
