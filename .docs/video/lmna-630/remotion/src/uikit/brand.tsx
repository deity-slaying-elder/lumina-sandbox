import React from "react";
import { AbsoluteFill, Audio, Img, Sequence, interpolate, spring, staticFile, useCurrentFrame, Easing } from "remotion";
import { BRAND, FONT_BODY, FONT_DISPLAY, FPS, sec } from "../theme";

// Propela intro and outro, reused on EVERY film (James, 2026-09-24).
// Brand source: ~/.claude/brand/BRAND.md. Light = paper + Deep Navy logo;
// dark = Deep Slate + yellow-white logo. The mark's two swooshes are the real
// logo paths (logos/mark), animated; the wordmark is the official lockup SVG.

export const INTRO_FRAMES = sec(3.5);
export const OUTRO_FRAMES = sec(4.0);
const F = FPS;

const MARK_A = "M98.3332,77.5363c-15.3952,25.3151-45.3348,38.9091-66.8476,30.3621-8.9535-3.582-15.0711-10.4193-18.0286-19.0069,1.7421,1.1802,3.6868,2.1977,5.753,3.0117,20.743,8.2622,49.7103-5.0874,64.7408-29.792,9.7233-15.9949,11.1818-32.8446,5.3884-44.973,19.7304,9.483,23.9034,35.9377,9.0345,60.3981h-.0405Z";
const MARK_B = "M89.299,17.1384c-.6888-.3256-1.3775-.6512-2.1067-.936-21.5533-8.5469-51.4929,5.006-66.8881,30.3618-8.9536,14.7739-11.0198,30.2804-6.8469,42.3275-15.7598-10.5819-18.1501-34.4318-4.659-56.6537C23.8289,7.5333,52.7961-5.8161,73.5391,2.4459c7.2925,2.8897,12.5998,8.0992,15.7599,14.6925Z";

/** The propeller mark: two swooshes spin in from opposite sides and lock together. */
export const Mark: React.FC<{ size: number; at?: number; color?: string; accent?: string }> = ({ size, at = 0, color = BRAND.deepNavy, accent }) => {
  const f = useCurrentFrame() - at;
  const sp = (d: number) => spring({ frame: f - d, fps: F, config: { damping: 13, stiffness: 120, mass: 0.8 } });
  const a = sp(0), b = sp(4);
  return (
    <svg width={size} height={size * (110.45 / 107.3)} viewBox="0 0 107.3 110.45" style={{ overflow: "visible" }}>
      <g transform={`rotate(${(1 - a) * -160} 53.6 55.2) translate(${(1 - a) * 30} ${(1 - a) * 20})`} opacity={Math.min(1, a * 2)}><path d={MARK_A} fill={accent ?? color} /></g>
      <g transform={`rotate(${(1 - b) * 160} 53.6 55.2) translate(${(1 - b) * -30} ${(1 - b) * -20})`} opacity={Math.min(1, b * 2)}><path d={MARK_B} fill={color} /></g>
    </svg>
  );
};

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
/** Opening card: mark spins in, wordmark wipes on, then the film's title and client. */
export const BrandIntro: React.FC<{ title: string; subtitle?: string; dark?: boolean }> = ({ title, subtitle, dark }) => {
  const f = useCurrentFrame();
  const bg = dark ? BRAND.deepSlate : "#f6f2ea", ink = dark ? "#fff" : BRAND.deepNavy, muted = dark ? BRAND.digitalBlue : "#6c7a88";
  const wipe = interpolate(f, [14, 34], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
  const slide = interpolate(f, [8, 30], [0, 1], { ...clamp, easing: Easing.inOut(Easing.cubic) });
  const tIn = spring({ frame: f - 34, fps: F, config: { damping: 18, stiffness: 120 } });
  const out = interpolate(f, [INTRO_FRAMES - 12, INTRO_FRAMES], [0, 1], clamp);
  return (
    <AbsoluteFill style={{ background: bg, alignItems: "center", justifyContent: "center", fontFamily: FONT_BODY, opacity: 1 - out }}>
      <Sequence from={0} durationInFrames={30}><Audio src={staticFile("sfx/mixkit/swoosh-3115.wav")} volume={0.35} /></Sequence>
      <Sequence from={30} durationInFrames={40}><Audio src={staticFile("sfx/mixkit/pop-light-3005.wav")} volume={0.3} /></Sequence>
      <div style={{ display: "flex", alignItems: "center", gap: 28, transform: `translateX(${(1 - slide) * 150}px) translateY(${-tIn * 40}px)` }}>
        <Mark size={120} color={dark ? "#fff" : BRAND.deepNavy} accent={dark ? BRAND.techYellow : undefined} />
        <div style={{ clipPath: `inset(0 ${(1 - wipe) * 100}% 0 0)`, fontFamily: FONT_DISPLAY, fontSize: 124, color: ink, lineHeight: 1, letterSpacing: -1 }}>Propela</div>
      </div>
      <div style={{ position: "absolute", top: "58%", textAlign: "center", opacity: Math.min(1, tIn * 1.5), transform: `translateY(${(1 - tIn) * 24}px)` }}>
        <div style={{ width: 80 * tIn, height: 5, background: BRAND.techYellow, margin: "0 auto 22px", borderRadius: 3, boxShadow: dark ? "none" : `0 0 0 1px ${BRAND.deepNavy}22` }} />
        <div style={{ fontFamily: FONT_DISPLAY, fontSize: 52, color: ink }}>{title}</div>
        {subtitle ? <div style={{ fontSize: 24, color: muted, fontWeight: 700, letterSpacing: 2, marginTop: 12 }}>{subtitle}</div> : null}
      </div>
    </AbsoluteFill>
  );
};

/** Closing card: lockup, a thank-you line, the domain. */
export const BrandOutro: React.FC<{ line?: string; dark?: boolean; credit?: string }> = ({ line = "Built by Propela Tech", dark, credit }) => {
  const f = useCurrentFrame();
  const bg = dark ? BRAND.deepSlate : "#f6f2ea", ink = dark ? "#fff" : BRAND.deepNavy, muted = dark ? BRAND.digitalBlue : "#6c7a88";
  const inn = interpolate(f, [0, 12], [0, 1], clamp);
  const t2 = spring({ frame: f - 22, fps: F, config: { damping: 18, stiffness: 110 } });
  return (
    <AbsoluteFill style={{ background: bg, alignItems: "center", justifyContent: "center", fontFamily: FONT_BODY, opacity: inn }}>
      <Sequence from={4} durationInFrames={50}><Audio src={staticFile("sfx/mixkit/confirm-2867.wav")} volume={0.25} /></Sequence>
      <Img src={staticFile(dark ? "brand/propela-main-yellow-white.svg" : "brand/propela-main-deep-blue.svg")} style={{ width: 460, transform: `scale(${0.94 + 0.06 * spring({ frame: f - 4, fps: F, config: { damping: 16 } })})` }} />
      <div style={{ marginTop: 40, textAlign: "center", opacity: Math.min(1, t2 * 1.5), transform: `translateY(${(1 - t2) * 20}px)` }}>
        <div style={{ fontSize: 30, color: ink, fontWeight: 700 }}>{line}</div>
        <div style={{ fontSize: 22, color: muted, fontWeight: 700, letterSpacing: 3, marginTop: 10 }}>PROPELA.TECH</div>
      </div>
      {credit ? <div style={{ position: "absolute", bottom: 40, left: 0, right: 0, textAlign: "center", fontSize: 16, color: muted, opacity: Math.min(1, t2) }}>{credit}</div> : null}
    </AbsoluteFill>
  );
};
