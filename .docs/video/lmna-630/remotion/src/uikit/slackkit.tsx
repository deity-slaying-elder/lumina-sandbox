import React, { useEffect, useState } from "react";
import { AbsoluteFill, Audio, Sequence, continueRender, delayRender, staticFile, useCurrentFrame } from "remotion";
import { BRAND, FONT_BODY, FONT_DISPLAY, FPS, sec } from "../theme";
import { pagesOf } from "../vox/words";
import { Mark } from "./brand";
import { ease, lerp, u } from "./ui";

// Shared pieces for the Slack quick-start style in Propela beige (James, 2026-09-24).
// Intro and outro are the ones James approved: a search box types, sends, and in the
// SAME shot becomes the Propela lockup with the title rising under it.

// The rate comes from theme, which is the single place it is declared. A local copy
// here is what made captions and sound cues land at half their intended time.
export const F = FPS;
export { sec };
export const PAPER = "#f6f2ea", NAVY = BRAND.deepNavy, YEL = BRAND.techYellow, INK_C = "#12324c", MUTED = "#6c7a88";
export const BLOCK = { paper: PAPER, sand: "#e7dfcb", blue: "#cfe3f6", yellow: "#f8fbb8" };

export type NLine = { id: string; caption: string; start: number; secs: number; words: { t: string; s: number; e: number }[] };

export const useKitFonts = () => {
  const [h] = useState(() => delayRender("kit fonts"));
  useEffect(() => {
    const add = (f: FontFace) => (document.fonts as unknown as { add: (f: FontFace) => void }).add(f);
    Promise.all([
      new FontFace("Caveat", `url('${staticFile("fonts/Caveat.woff2")}') format('woff2')`, { weight: "600" }).load().then(add),
      new FontFace("Permanent Marker", `url('${staticFile("fonts/PermanentMarker.woff2")}') format('woff2')`).load().then(add),
      new FontFace("Antonia H3 Light", `url('${staticFile("fonts/AntoniaH3Light.woff2")}') format('woff2')`).load().then(add),
    ]).then(() => continueRender(h)).catch(() => continueRender(h));
  }, [h]);
};

export const Sfx: React.FC<{ at: number; src: string; v?: number; dur?: number }> = ({ at, src, v = 0.5, dur = 1.2 }) => <Sequence from={Math.max(0, sec(at))} durationInFrames={sec(dur)}><Audio src={staticFile(`sfx/mixkit/${src}`)} volume={v} /></Sequence>;

/** Big SLDS-style search box that types `text` at `cps`, then "sends". */
export const SearchBox: React.FC<{ t: number; at: number; text: string; send: number; cps?: number; w?: number }> = ({ t, at, text, send, cps = 16, w = 960 }) => {
  const n = Math.max(0, Math.min(text.length, Math.floor((t - at) * cps)));
  const grow = u(t, at - 0.5, 0.45, ease.snap), press = t > send && t < send + 0.15 ? 0.96 : 1;
  const caret = n < text.length && Math.floor(t * 2.4) % 2 === 0;
  return (
    <div style={{ width: w * grow, scale: `${press}`, height: 100, borderRadius: 50, background: "#fff", boxShadow: "0 20px 50px rgba(18,50,76,.16), 0 0 0 1px rgba(18,50,76,.08)", display: "flex", alignItems: "center", padding: "0 38px", gap: 22, overflow: "hidden", fontFamily: FONT_BODY }}>
      <svg width="36" height="36" viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="7" stroke="#747474" strokeWidth="2.4" fill="none" /><line x1="15.8" y1="15.8" x2="21" y2="21" stroke="#747474" strokeWidth="2.4" strokeLinecap="round" /></svg>
      <div style={{ flex: 1, fontSize: 42, color: n ? "#181818" : "#939393", whiteSpace: "nowrap" }}>{n ? text.slice(0, n) : "Search Salesforce"}{caret ? <span style={{ borderRight: "3px solid #0176d3", marginLeft: 2 }} /> : null}</div>
      <div style={{ width: 58, height: 58, borderRadius: 29, background: t > send ? "#0176d3" : "#e5e5e5", display: "flex", alignItems: "center", justifyContent: "center" }}><svg width="26" height="26" viewBox="0 0 24 24"><path d="M5 12h12M12 6l6 6-6 6" stroke="#fff" strokeWidth="2.6" fill="none" strokeLinecap="round" strokeLinejoin="round" /></svg></div>
    </div>
  );
};

/** Intro in ONE shot: the box types the feature name, sends, shrinks into the Propela lockup,
 *  and the yellow rule, title and subtitle rise underneath. Returns null after `end`. */
export const IntroLockup: React.FC<{ t: number; query: string; title: string; subtitle: string; start?: number; end: number }> = ({ t, query, title, subtitle, start = 0.5, end }) => {
  if (t > end) return null;
  const send = start + query.length / 16 + 0.5;
  const shrink = u(t, send + 0.1, 0.45, ease.glide);
  const lock = t > send + 0.25;
  const rise = u(t, send + 0.55, 0.5, ease.out), out = u(t, end - 0.35, 0.35);
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", opacity: 1 - out }}>
      <div style={{ position: "absolute", top: 490, opacity: 1 - shrink, scale: `${1 - shrink * 0.7}`, translate: `0 ${-shrink * 170}px` }}><SearchBox t={t} at={start} text={query} send={send} /></div>
      {lock ? (
        <div style={{ position: "absolute", top: 300, display: "flex", flexDirection: "column", alignItems: "center" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 26 }}>
            <Mark size={116} color={NAVY} accent={YEL} at={sec(send + 0.25)} />
            <div style={{ fontFamily: FONT_DISPLAY, fontSize: 118, color: NAVY, lineHeight: 1, clipPath: `inset(0 ${(1 - u(t, send + 0.4, 0.45)) * 100}% 0 0)` }}>Propela</div>
          </div>
          <div style={{ width: 96 * rise, height: 6, background: YEL, borderRadius: 3, margin: "40px 0 26px", boxShadow: `0 0 0 1px ${NAVY}22` }} />
          <div style={{ fontFamily: FONT_DISPLAY, fontSize: 64, color: NAVY, opacity: rise, translate: `0 ${(1 - rise) * 24}px` }}>{title}</div>
          <div style={{ fontFamily: FONT_BODY, fontSize: 26, fontWeight: 800, letterSpacing: 3, color: MUTED, marginTop: 16, opacity: u(t, send + 0.8, 0.4), translate: `0 ${(1 - u(t, send + 0.8, 0.4)) * 18}px` }}>{subtitle}</div>
        </div>
      ) : null}
    </AbsoluteFill>
  );
};

/** Sign-off, slow: the box types `text`, holds, then becomes the mark. */
export const SignOff: React.FC<{ t: number; at: number; text: string }> = ({ t, at, text }) => {
  const send = at + text.length / 11 + 1.1;
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <div style={{ opacity: 1 - u(t, send + 0.1, 0.3), scale: `${1 - u(t, send + 0.1, 0.35, ease.anticipate) * 0.6}` }}><SearchBox t={t} at={at} text={text} send={send} cps={11} /></div>
      {t > send + 0.2 ? <div style={{ position: "absolute" }}><Mark size={200} color={NAVY} accent={YEL} at={sec(send + 0.2)} /></div> : null}
    </AbsoluteFill>
  );
};
export const signOffLength = (text: string) => text.length / 11 + 1.1 + 1.6;

/** Chapter colour change: the Propela swooshes sweep across while the new block irises open. */
export const Swoosh: React.FC<{ t: number; at: number; from: string; to: string }> = ({ t, at, from, to }) => {
  const k = u(t, at, 0.6, ease.glide);
  return (
    <AbsoluteFill style={{ background: from }}>
      {k > 0 ? <AbsoluteFill style={{ background: to, clipPath: `circle(${k * 130}% at 50% 50%)` }} /> : null}
      {k > 0 && k < 1 ? <div style={{ position: "absolute", left: lerp(-1400, 1900, k), top: -300, rotate: `${lerp(-40, 20, k)}deg`, opacity: 0.9 }}><Mark size={1500} color={NAVY} accent={YEL} at={-999} /></div> : null}
    </AbsoluteFill>
  );
};

export const ChapterPill: React.FC<{ t: number; at: number; label: string }> = ({ t, at, label }) => {
  const p = u(t, at, 0.35, ease.snap);
  return (
    <div style={{ position: "absolute", left: 44, top: 28, padding: "8px 16px", borderRadius: 10, background: "rgba(255,255,255,.92)", boxShadow: "0 6px 18px rgba(18,50,76,.12)", fontFamily: FONT_BODY, fontSize: 20, fontWeight: 800, letterSpacing: 3, color: INK_C, display: "flex", gap: 12, alignItems: "center", opacity: p, translate: `${(1 - p) * -20}px 0` }}>
      <span style={{ width: 16, height: 16, borderRadius: 4, background: YEL, boxShadow: `inset 0 0 0 2px ${INK_C}` }} />{label}
    </div>
  );
};

export const Sparkles: React.FC<{ t: number; at: number; cx?: number; cy?: number }> = ({ t, at, cx = 960, cy = 500 }) => {
  if (t < at) return null;
  const k = Math.min(1, (t - at) / 0.6);
  return (<>{Array.from({ length: 8 }, (_, i) => { const a = (i / 8) * Math.PI * 2, d = 120 + 170 * k; return (
    <svg key={i} width="42" height="42" viewBox="0 0 24 24" style={{ position: "absolute", left: cx + Math.cos(a) * d - 21, top: cy + Math.sin(a) * d - 21, opacity: 1 - k, scale: `${0.6 + 0.6 * (1 - k)}` }}><path d="M12 0 L14 10 L24 12 L14 14 L12 24 L10 14 L0 12 L10 10 Z" fill={i % 2 ? NAVY : "#fff"} stroke={NAVY} strokeWidth="0.8" /></svg>
  ); })}</>);
};

const svgCache: Record<string, string> = {};
/** Open Peeps character (CC0), linework recoloured to Deep Navy. Local files only. */
export const Peep: React.FC<{ file: string; h: number }> = ({ file, h }) => {
  const [svg, setSvg] = useState(svgCache[file] ?? "");
  const [hd] = useState(() => (svgCache[file] ? null : delayRender(`peep ${file}`)));
  useEffect(() => { if (svgCache[file]) return; fetch(staticFile(`peeps/${file}`)).then((r) => r.text()).then((t) => { svgCache[file] = t.replace(/#000000/gi, NAVY).replace(/<svg /, `<svg style="height:${h}px;width:auto;display:block" `); setSvg(svgCache[file]); if (hd !== null) continueRender(hd); }).catch(() => { if (hd !== null) continueRender(hd); }); }, [file, h, hd]);
  return <div dangerouslySetInnerHTML={{ __html: svg }} />;
};

/** Word-pop caption pill for a narration timeline; `L(i)` gives line i's film start. */
export const Caption: React.FC<{ lines: NLine[]; L: (i: number) => number }> = ({ lines, L }) => {
  const frame = useCurrentFrame();
  const i = lines.findIndex((l, k) => frame >= sec(L(k)) && frame < sec(L(k) + l.secs));
  if (i < 0) return null;
  const local = frame - sec(L(i)); const pages = pagesOf(lines[i], 4);
  const page = pages.find((p) => local >= p.from && local < p.from + p.dur) ?? pages[pages.length - 1];
  return (
    <div style={{ position: "absolute", left: 0, right: 0, top: 972, display: "flex", justifyContent: "center" }}>
      <div style={{ display: "flex", gap: 12, padding: "8px 20px", borderRadius: 14, background: "rgba(255,255,255,.93)", boxShadow: "0 8px 24px rgba(18,50,76,.12)" }}>
        {page.words.map((w, k) => { const live = local >= w.from && local < w.from + w.dur; return <span key={k} style={{ fontFamily: FONT_BODY, fontWeight: 800, fontSize: 40, padding: "0 6px", borderRadius: 6, color: live ? NAVY : INK_C, background: live ? YEL : "transparent", opacity: live ? 1 : 0.8 }}>{w.text}</span>; })}
      </div>
    </div>
  );
};

/** Swap the content of a stationary window with a page-turn wipe (never a cross-fade). */
export const wipeClip = (k: number) => `inset(0 0 0 ${(1 - k) * 100}%)`;
