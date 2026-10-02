import React from "react";
import { AbsoluteFill, Audio, Img, Sequence, staticFile } from "remotion";
import { BRAND, FONT_BODY, FONT_DISPLAY, Line, PAPER, sec } from "./theme";
import {
  Caption,
  ChapterPill,
  IntroLockup,
  SignOff,
  Swoosh,
  Sfx,
  signOffLength,
  useKitFonts,
} from "./uikit/slackkit";
import { BrandOutro } from "./uikit/brand";
import { useT, u, ease, enterStyle } from "./uikit/ui";
import { AppFrame, Worklist, Calendar, BookingModal, T } from "./screens/Scheduling";
import { Driven, Beat, Note } from "./Driven";
import SCRIPT from "./script.json";

// Scene order is the spine from the skill: hook/problem, what we built, how it works,
// in Salesforce, guardrails, what's next. Each chapter's length IS its narration, so
// nothing is hand-timed and nothing drifts.
const CHAPTERS: {
  id: string;
  pill: string;
  slam: string;
  title: string;
  tint: string;
}[] = [
  { id: "01-problem", pill: "01 · THE PROBLEM", slam: "BY HAND", title: "Tracked by hand", tint: "#e7dfcb" },
  { id: "02-built", pill: "02 · WHAT WE BUILT", slam: "ONE SCREEN", title: "One screen", tint: PAPER },
  { id: "03-programs", pill: "03 · PROGRAMS", slam: "PROGRAMS", title: "Programs", tint: PAPER },
  { id: "04-providers", pill: "04 · WHO CAN GO", slam: "WHO CAN GO", title: "Eligibility", tint: "#cfe3f6" },
  { id: "05-counts", pill: "05 · THE NUMBERS", slam: "THE NUMBERS", title: "Patient counts", tint: PAPER },
  { id: "06-guardrails", pill: "06 · GUARDRAILS", slam: "GUARDRAILS", title: "Notifications", tint: "#e7dfcb" },
];

const GAP = 0.28; // breath between lines
const TAIL = 0.6; // held beat at the end of a chapter
const SLAM = 0.9; // the chapter word lands before the body starts talking

type Scene = { scene: string; lines: Line[] };
const SCENES = SCRIPT as Scene[];

/** Seconds a chapter runs: the slam, its narration plus gaps, and the tail. */
export const chapterSecs = (s: Scene) =>
  SLAM + s.lines.reduce((a, l) => a + l.secs + GAP, 0) + TAIL;

export const POSTER = 1.7; // frame one is the Teams thumbnail, per the skill
export const LOCKUP = 5.0; // the box types, morphs into the mark, holds
export const INTRO = POSTER + LOCKUP;
export const SIGN_OFF = signOffLength("Built by Propela Tech");
export const OUTRO = SIGN_OFF + 4.0;

export const chapterStart = (i: number) =>
  INTRO + SCENES.slice(0, i).reduce((a, s) => a + chapterSecs(s), 0);

export const FILM_SECS =
  INTRO + SCENES.reduce((a, s) => a + chapterSecs(s), 0) + OUTRO;

// ---------------------------------------------------------------- backdrop
const Paper: React.FC<{ tint?: string }> = ({ tint = PAPER }) => {
  const t = useT();
  const dx = Math.sin(t * 0.18) * 14;
  const dy = Math.cos(t * 0.13) * 10;
  return (
    <AbsoluteFill style={{ background: tint }}>
      <AbsoluteFill
        style={{
          backgroundImage: `radial-gradient(${BRAND.deepSlate}22 1.6px, transparent 1.6px)`,
          backgroundSize: "46px 46px",
          transform: `translate(${dx}px, ${dy}px)`,
          opacity: 0.5,
        }}
      />
      <AbsoluteFill
        style={{
          background:
            "radial-gradient(1200px 700px at 22% 12%, #ffffff 0%, transparent 70%)",
        }}
      />
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------- poster
/** Frame one. Teams uses it as the thumbnail, so it has to read as a still. */
const Poster: React.FC = () => {
  const t = useT();
  const k = u(t, 0, 0.5, ease.out);
  const ring = u(t, 0.5, 0.7);
  return (
    <AbsoluteFill style={{ background: PAPER }}>
      <div style={{ position: "absolute", left: 96, top: 300, width: 740, opacity: k }}>
        <div
          style={{
            fontFamily: FONT_BODY,
            fontSize: 21,
            letterSpacing: "0.22em",
            textTransform: "uppercase",
            color: BRAND.deepSlate,
            opacity: 0.7,
          }}
        >
          Feature walkthrough · for Lumina
        </div>
        <div
          style={{
            fontFamily: FONT_DISPLAY,
            fontSize: 104,
            lineHeight: 1.03,
            color: BRAND.deepNavy,
            marginTop: 16,
          }}
        >
          Facility Scheduling
        </div>
        <div
          style={{
            height: 9,
            width: 300,
            background: BRAND.techYellow,
            borderRadius: 5,
            margin: "26px 0",
          }}
        />
        <div style={{ fontFamily: FONT_BODY, fontSize: 30, lineHeight: 1.4, color: BRAND.deepSlate }}>
          Book an onboarding visit, and know who can actually go.
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 900,
          top: 150,
          width: 950,
          height: 780,
          borderRadius: 18,
          overflow: "hidden",
          boxShadow: "0 40px 90px rgba(18,50,76,.28)",
          transform: `scale(${0.98 + 0.02 * k})`,
        }}
      >
        <Img src={staticFile("shots/04-provider-filter.png")} style={{ width: 1500, marginLeft: -300 }} />
      </div>
      {/* The result, circled: two providers out of three hundred and twenty three. */}
      <svg style={{ position: "absolute", left: 980, top: 640 }} width="620" height="170">
        <ellipse
          cx="300"
          cy="85"
          rx="268"
          ry="56"
          fill="none"
          stroke={BRAND.deepNavy}
          strokeWidth="6"
          strokeDasharray="1700"
          strokeDashoffset={1700 * (1 - ring)}
        />
      </svg>
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------- chapter
/** Yellow band, one big word, a shake as it lands. */
const Slam: React.FC<{ word: string }> = ({ word }) => {
  const t = useT();
  if (t > SLAM) return null;
  const k = u(t, 0, 0.4, ease.snap);
  const out = u(t, SLAM - 0.3, 0.3);
  const shake = t < 0.5 ? Math.sin(t * 60) * (1 - t / 0.5) * 7 : 0;
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", opacity: 1 - out }}>
      <div
        style={{
          background: BRAND.techYellow,
          padding: "26px 60px",
          transform: `translate(${shake}px, ${(1 - k) * 40}px) scale(${0.9 + 0.1 * k})`,
          clipPath: `inset(0 ${(1 - k) * 100}% 0 0)`,
        }}
      >
        <div style={{ fontFamily: FONT_DISPLAY, fontSize: 190, lineHeight: 1, color: BRAND.deepNavy }}>
          {word}
        </div>
      </div>
    </AbsoluteFill>
  );
};

/**
 * Each chapter drives the rebuilt screen: a cursor travels and clicks, the camera
 * follows it, and marker notes name what just changed. Beats are in app pixels.
 */
const ChapterBody: React.FC<{ id: string }> = ({ id }) => {
  const t = useT() - SLAM;
  if (t < -0.25) return null;

  if (id === "01-problem") {
    const beats: Beat[] = [
      { at: 0, x: 720, y: 405, z: 1 },
      { at: 2.4, x: 345, y: 95, z: 1.55 },
      { at: 6.4, x: 345, y: 95, z: 1.55 },
      { at: 8.4, x: 720, y: 405, z: 1 },
    ];
    const notes: Note[] = [
      { at: 3.2, x: 790, y: 300, text: "nothing booked", box: T.tileNoEvent, until: 8.0 },
    ];
return (
      <Driven beats={beats} notes={notes}>
        <AppFrame>
          <Worklist t={t} rowsFrom={0.35} countsFrom={0.5} />
        </AppFrame>
      </Driven>
    );
  }

  if (id === "02-built") {
    const beats: Beat[] = [
      { at: 0, x: 720, y: 405, z: 1 },
      { at: 2.2, x: 720, y: 405, z: 1 },
      { at: 4.6, x: 1120, y: 130, z: 1.5, click: true },
      { at: 7.4, x: 720, y: 405, z: 1 },
    ];
    const notes: Note[] = [
      { at: 4.8, x: 700, y: 300, text: "one screen", box: T.viewToggle, until: 9.5 },
    ];
return (
      <Driven beats={beats} notes={notes}>
        <AppFrame>
          <Worklist t={t} rowsFrom={0.2} countsFrom={0.1} />
        </AppFrame>
      </Driven>
    );
  }

  if (id === "03-programs") {
    const SWITCH = 5.0;
    const beats: Beat[] = [
      { at: 0, x: 720, y: 430, z: 1 },
      { at: 1.8, x: 480, y: 330, z: 1.3 },
      { at: 4.6, x: 480, y: 330, z: 1.4, click: true },
      { at: 6.4, x: 700, y: 300, z: 1.2 },
      { at: 10.0, x: 700, y: 320, z: 1.2 },
    ];
    // Modal geometry in app pixels: it starts at x 210, the left rail is 268 wide, so the
    // programme column begins near x 505. Notes sit on the empty band under the helper
    // text, which clears both the controls and the caption zone.
    const notes: Note[] = [
      { at: 7.4, x: 620, y: 300, text: "ticked from\nthe facility", box: T.modalPrograms, until: 12 },
    ];
    return (
      <Driven beats={beats} notes={notes}>
        <AppFrame>
          {t < SWITCH ? <Calendar t={t} chipsFrom={0.35} /> : null}
          {t >= SWITCH ? (
            <>
              <Calendar t={SWITCH} chipsFrom={0.35} />
              <BookingModal t={t - SWITCH} ticks={[1.0, undefined, 1.5]} />
            </>
          ) : null}
        </AppFrame>
      </Driven>
    );
  }

  if (id === "04-providers") {
    const beats: Beat[] = [
      { at: 0, x: 720, y: 400, z: 1.1 },
      { at: 2.0, x: 700, y: 520, z: 1.45 },
      { at: 4.6, x: 700, y: 520, z: 1.6, click: true },
      { at: 8.0, x: 700, y: 560, z: 1.55 },
      { at: 12.0, x: 700, y: 600, z: 1.4 },
    ];
    const notes: Note[] = [
      { at: 6.0, x: 1010, y: 430, text: "two of three\nhundred", box: T.modalPickerList, until: 11 },
      { at: 12.0, x: 620, y: 560, text: "every program,\nnot just one", box: T.modalHelper, until: 17 },
    ];
    return (
      <Driven beats={beats} notes={notes}>
        <AppFrame>
          <Calendar t={6} chipsFrom={0} />
          <BookingModal t={t} ticks={[0, undefined, 0]} showPicker={4.8} />
        </AppFrame>
      </Driven>
    );
  }

  if (id === "05-counts") {
    const beats: Beat[] = [
      { at: 0, x: 720, y: 405, z: 1 },
      { at: 2.0, x: 430, y: 300, z: 1.5 },
      { at: 5.6, x: 430, y: 380, z: 1.5 },
      { at: 8.0, x: 720, y: 405, z: 1 },
    ];
    const notes: Note[] = [
      { at: 2.6, x: 800, y: 380, text: "census, seen,\nconsented", box: T.firstRowBar, until: 8 },
    ];
return (
      <Driven beats={beats} notes={notes}>
        <AppFrame>
          <Worklist t={t} rowsFrom={0.15} countsFrom={0.1} />
        </AppFrame>
      </Driven>
    );
  }

  if (id === "06-guardrails") {
    const beats: Beat[] = [
      { at: 0, x: 700, y: 300, z: 1.2 },
      { at: 2.2, x: 700, y: 250, z: 1.5 },
      { at: 6.0, x: 420, y: 430, z: 1.45 },
      { at: 10.0, x: 700, y: 400, z: 1.2 },
    ];
    const notes: Note[] = [
      { at: 3.0, x: 1010, y: 300, text: "everyone on\nthe visit", box: T.modalPicker, until: 9 },
    ];
    return (
      <Driven beats={beats} notes={notes}>
        <AppFrame>
          <Calendar t={6} chipsFrom={0} />
          <BookingModal t={t} ticks={[0, undefined, 0]} />
        </AppFrame>
      </Driven>
    );
  }

  const beats: Beat[] = [
    { at: 0, x: 720, y: 400, z: 1 },
    { at: 2.0, x: 600, y: 330, z: 1.28 },
    { at: 6.0, x: 720, y: 400, z: 1.1 },
  ];
  return (
    <Driven beats={beats}>
      <AppFrame>
        <Worklist t={t} rowsFrom={0.15} countsFrom={0.1} />
      </AppFrame>
    </Driven>
  );
};

const Pill: React.FC<{ label: string }> = ({ label }) => {
  const t = useT();
  return <ChapterPill t={t} at={SLAM} label={label} />;
};

const SwooshIn: React.FC<{ from: string; to: string }> = ({ from, to }) => {
  const t = useT();
  if (t > 0.75) return null;
  return <Swoosh t={t} at={0} from={from} to={to} />;
};

const Lockup: React.FC = () => {
  const t = useT();
  return (
    <IntroLockup
      t={t}
      query="Facility Scheduling"
      title="Facility Scheduling"
      subtitle="FEATURE WALKTHROUGH · FOR LUMINA"
      end={LOCKUP}
    />
  );
};

const Outro: React.FC = () => {
  const t = useT();
  return (
    <AbsoluteFill>
      {t < SIGN_OFF ? <SignOff t={t} at={0.3} text="Built by Propela Tech" /> : null}
      {t >= SIGN_OFF ? (
        <Sequence from={sec(SIGN_OFF)}>
          <BrandOutro
            line="Facility Scheduling"
            credit="Salesforce Lightning Design System icons, CC BY-ND 4.0"
          />
        </Sequence>
      ) : null}
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------- film
export const Film: React.FC = () => {
  useKitFonts();
  const flat: { line: Line; at: number }[] = [];
  SCENES.forEach((s, i) => {
    let at = chapterStart(i) + SLAM;
    s.lines.forEach((l) => {
      flat.push({ line: l, at });
      at += l.secs + GAP;
    });
  });

  return (
    <AbsoluteFill>
      <Paper />

      <Sequence durationInFrames={sec(POSTER)}>
        <Poster />
      </Sequence>

      <Sequence from={sec(POSTER)} durationInFrames={sec(LOCKUP)}>
        <Lockup />
      </Sequence>

      {SCENES.map((s, i) => {
        const meta = CHAPTERS.find((c) => c.id === s.scene)!;
        const prev =
          i === 0 ? PAPER : CHAPTERS.find((c) => c.id === SCENES[i - 1].scene)!.tint;
        return (
          <Sequence
            key={s.scene}
            from={sec(chapterStart(i))}
            durationInFrames={sec(chapterSecs(s))}
          >
            <Paper tint={meta.tint} />
            <SwooshIn from={prev} to={meta.tint} />
            <Slam word={meta.slam} />
            <ChapterBody id={meta.id} />
            <Pill label={meta.pill} />
          </Sequence>
        );
      })}

      <Sequence from={sec(FILM_SECS - OUTRO)} durationInFrames={sec(OUTRO)}>
        <Outro />
      </Sequence>

      {/* One wav per line, placed at the line's own start. */}
      {flat.map(({ line, at }) => (
        <Sequence key={line.id} from={sec(at)} durationInFrames={sec(line.secs) + 2}>
          <Audio src={staticFile(`vo/${line.id}.wav`)} />
        </Sequence>
      ))}

      {/* One swoosh per chapter, low-passed so it does not read as a hiss. */}
      {SCENES.map((s, i) => (
        <Sfx key={`sw-${s.scene}`} at={chapterStart(i)} src="swoosh-soft-3115.wav" v={0.35} />
      ))}
      <Sfx at={POSTER} src="pop-light-3005.wav" v={0.3} />
      <Sfx at={FILM_SECS - OUTRO} src="confirm-2867.wav" v={0.3} />

      <Caption lines={flat.map((f) => f.line)} L={(i) => flat[i].at} />

      <div
        style={{
          position: "absolute",
          right: 26,
          bottom: 20,
          fontFamily: FONT_BODY,
          fontSize: 17,
          color: "#8a7f66",
          zIndex: 80,
        }}
      >
        Screens recreated from the sandbox · sample data
      </div>
    </AbsoluteFill>
  );
};
