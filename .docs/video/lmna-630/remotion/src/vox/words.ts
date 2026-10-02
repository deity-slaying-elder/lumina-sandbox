import { Line, sec } from "../theme";

// Kokoro returns no word timings, and the whisper route would mean a model
// download plus a Remotion major upgrade for @remotion/captions. Synthesised
// speech runs at a near-constant rate, so splitting a line's measured duration
// across its words by character length lands close enough for word-pop
// captions, where a frame or two of drift is invisible.
//
// ponytail: proportional split; swap in whisper.cpp word timings if a line ever
// visibly drifts.

export type Word = { text: string; from: number; dur: number };
export type Page = { words: Word[]; from: number; dur: number };

// Trailing punctuation buys extra time -- the synth pauses there.
const weight = (w: string) => w.length + (/[.,;:—]$/.test(w) ? 3 : 0);

export const wordsOf = (line: Line): Word[] => {
  const raw = line.caption.split(/\s+/).filter(Boolean);
  const total = raw.reduce((a, w) => a + weight(w), 0) || 1;
  const frames = sec(line.secs);
  let at = 0;
  return raw.map((text, i) => {
    const dur = i === raw.length - 1 ? frames - at : Math.max(2, Math.round((weight(text) / total) * frames));
    const from = at;
    at += dur;
    return { text, from, dur };
  });
};

// Group words into short pages so the eye reads a phrase, not a stream of
// single words. Breaks on a page maximum and after end-of-clause punctuation.
export const pagesOf = (line: Line, maxWords = 4): Page[] => {
  const words = wordsOf(line);
  const pages: Page[] = [];
  let cur: Word[] = [];
  for (const w of words) {
    cur.push(w);
    const clauseEnd = /[.,;:—]$/.test(w.text);
    if (cur.length >= maxWords || (clauseEnd && cur.length >= 2)) {
      pages.push({ words: cur, from: cur[0].from, dur: cur.reduce((a, x) => a + x.dur, 0) });
      cur = [];
    }
  }
  if (cur.length) pages.push({ words: cur, from: cur[0].from, dur: cur.reduce((a, x) => a + x.dur, 0) });
  return pages;
};
