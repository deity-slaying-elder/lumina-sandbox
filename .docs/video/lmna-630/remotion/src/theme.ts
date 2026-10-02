// Values come from ~/.claude/brand/BRAND.md (the brand source of truth), not memory.
export const BRAND = {
  techYellow: "#f5fd7e",
  deepSlate: "#24323f",
  deepNavy: "#0C263B",
  digitalBlue: "#b9d8f5",
  modernSand: "#bdb193",
  white: "#FFFFFF",
  nearBlack: "#1a1a1a",
};

export const FONT_DISPLAY = "'Antonia H3 Light', Georgia, 'Times New Roman', serif";
export const FONT_BODY = "'DM Sans', Tahoma, Helvetica, Arial, sans-serif";

// The paper-beige base of the house look (style-direction.md), and the white the
// rebuilt Salesforce screens sit on.
export const PAPER = "#f6f2ea";
export const SCREEN = "#ffffff";

// Films render at 60fps (skill: "keep time in seconds and never hardcode 30").
// This is the ONE place the rate is declared; ui.tsx imports it rather than
// carrying its own copy, which is what made 30 leak into kit springs before.
export const FPS = 60;
export const sec = (s: number) => Math.round(s * FPS);

/** One narration line: what burns on screen and how long its wav actually is. */
export type Line = { id: string; caption: string; secs: number };
