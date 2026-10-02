import React from "react";
import { staticFile } from "remotion";
import { u, ease } from "../uikit/ui";

// The Facility Scheduling screens, rebuilt as components the film drives rather than
// screenshots it pans over (house style, 2026-09-25).
//
// Built at the capture's own geometry, 1440x810, so every number below can be read
// straight off the real screen rather than guessed, then scaled to fill 1920x1080.
// Icons are the real SLDS utility sprite. Data is synthetic: no facility, provider or
// patient here is a real record.

export const APP_W = 1440;
export const APP_H = 810;

const SF = {
  pageBg: "#f3f3f3",
  card: "#ffffff",
  border: "#e5e5e5",
  rowBorder: "#eaeaea",
  ink: "#181818",
  weak: "#444444",
  muted: "#747474",
  link: "#0176d3",
  brand: "#0176d3",
  brandDark: "#014486",
  amber: "#8c4b02",
  green: "#2e844a",
  greenBg: "#ebf7ee",
  tileLit: "#f3f8fe",
};
const FONT = "'Salesforce Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif";

/** SLDS utility sprite, used unmodified (CC BY-ND 4.0 — credit is on the end card). */
const Ico: React.FC<{ name: string; size?: number; color?: string; style?: React.CSSProperties }> = ({
  name,
  size = 14,
  color = SF.muted,
  style,
}) => (
  <svg width={size} height={size} style={{ fill: color, flex: "none", ...style }}>
    <use href={`${staticFile("slds/icons/utility-sprite/svg/symbols.svg")}#${name}`} />
  </svg>
);

const PROGRAM_COLOR: Record<string, string> = {
  TCM: "#2b6cb0",
  CCM: "#6b46c1",
  BHI: "#1a7f52",
  CoCM: "#0f766e",
  Telepsych: "#c2410c",
  AHTH: "#a16207",
  "Community FT": "#be185d",
  IPV: "#9d174d",
};

export type Facility = {
  name: string;
  parent: string;
  state: string;
  census: number;
  seen: number;
  consented: number;
  rollout: string;
  events: number;
  next: string;
};

export const FACILITIES: Facility[] = [
  { name: "Brightwater Health Care Center", parent: "Accolade Healthcare", state: "IL", census: 40, seen: 12, consented: 5, rollout: "Oct 4", events: 1, next: "Oct 18" },
  { name: "Danville Nursing & Rehabilitation", parent: "Reliant Care Management", state: "KS", census: 57, seen: 24, consented: 12, rollout: "Oct 8", events: 2, next: "Oct 7" },
  { name: "Paxton Senior Living", parent: "AOM Healthcare", state: "MO", census: 74, seen: 41, consented: 24, rollout: "Oct 12", events: 1, next: "Oct 10" },
  { name: "Easton Health Care Center", parent: "Accolade Healthcare", state: "OH", census: 91, seen: 62, consented: 40, rollout: "Oct 16", events: 2, next: "Oct 10" },
  { name: "Grand Manor Nursing & Rehab", parent: "AOM Healthcare", state: "KS", census: 125, seen: 50, consented: 40, rollout: "Oct 24", events: 2, next: "Oct 10" },
  { name: "Piketon Nursing Care Center", parent: "Accolade Healthcare", state: "IL", census: 142, seen: 75, consented: 38, rollout: "Oct 28", events: 1, next: "Oct 13" },
];

/**
 * Where things actually are, in app pixels, derived from this file's own layout rather
 * than read off a screenshot by eye. Annotations anchor to these, so a note can never
 * again point at empty space when a column width changes.
 *
 * Card: x 10..1430, y 96..800. Header 54 tall. Tiles 62 tall in four 355px columns.
 */
export const T = {
  tileAwaiting: [10, 150, 355, 62] as const,
  tileNoEvent: [365, 150, 355, 62] as const,
  tileBooked: [720, 150, 355, 62] as const,
  viewToggle: [1098, 104, 118, 32] as const,
  scheduleBtn: [1258, 104, 158, 32] as const,
  firstRowBar: [348, 292, 400, 50] as const,
  firstRowName: [26, 288, 300, 40] as const,
  // Modal at x 210, y 44, 1020x720. Left rail 268 wide, right column content from 498.
  modalPrograms: [496, 128, 250, 92] as const,
  modalCounts: [228, 232, 232, 58] as const,
  modalPicker: [496, 378, 472, 34] as const,
  modalPickerList: [496, 414, 472, 64] as const,
  modalHelper: [496, 486, 600, 40] as const,
};

// ---------------------------------------------------------------- console chrome
/** The blue banded console header and app tab bar. Without it this stops reading as Salesforce. */
const Chrome: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div style={{ position: "absolute", inset: 0, background: SF.pageBg, fontFamily: FONT, color: SF.ink, fontSize: 13 }}>
    <div style={{ height: 40, background: "#fff", borderBottom: `1px solid ${SF.border}`, display: "flex", alignItems: "center", padding: "0 16px", gap: 14 }}>
      <div style={{ width: 22, height: 22, borderRadius: 4, background: "linear-gradient(140deg,#00a1e0,#0070d2)" }} />
      <div style={{ width: 400, height: 26, borderRadius: 13, background: "#f3f3f3", border: `1px solid ${SF.border}`, display: "flex", alignItems: "center", gap: 7, padding: "0 10px", color: "#9b9b9b" }}>
        <Ico name="search" size={11} color="#9b9b9b" />
        <span style={{ fontSize: 12 }}>Search...</span>
      </div>
    </div>
    <div style={{ height: 34, background: "#fff", borderBottom: `1px solid ${SF.border}`, display: "flex", alignItems: "stretch", padding: "0 14px" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, fontWeight: 700, fontSize: 14, paddingRight: 20 }}>
        <span style={{ color: "#747474", letterSpacing: 1 }}>⠿</span> Operations
      </div>
      <div style={{ display: "flex", alignItems: "center", padding: "0 14px", borderBottom: `3px solid ${SF.brand}`, fontSize: 13, fontWeight: 600 }}>
        Facility Scheduling
      </div>
    </div>
    {/* The console's banded strip. It is the strongest "this is Salesforce" signal. */}
    <div
      style={{
        height: 14,
        background: "#1b5f9e",
        backgroundImage:
          "repeating-linear-gradient(115deg, rgba(255,255,255,.07) 0 3px, transparent 3px 7px), linear-gradient(#2a6fae,#14538d)",
      }}
    />
    <div style={{ position: "absolute", left: 10, right: 10, top: 96, bottom: 10, background: SF.card, borderRadius: 4, border: `1px solid ${SF.border}`, overflow: "hidden", boxShadow: "0 1px 2px rgba(0,0,0,.05)" }}>
      {children}
    </div>
  </div>
);

const Btn: React.FC<{
  label: string;
  icon?: string;
  primary?: boolean;
  active?: boolean;
  joinL?: boolean;
  joinR?: boolean;
  pressed?: boolean;
}> = ({ label, icon, primary, active, joinL, joinR, pressed }) => (
  <div
    style={{
      height: 30,
      padding: "0 13px",
      border: `1px solid ${primary ? SF.brand : "#c9c9c9"}`,
      background: primary ? SF.brand : active ? "#eef4ff" : "#fff",
      color: primary ? "#fff" : active ? SF.brandDark : "#0176d3",
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      gap: 6,
      fontSize: 13,
      fontWeight: 600,
      borderRadius: joinL ? "4px 0 0 4px" : joinR ? "0 4px 4px 0" : 4,
      marginLeft: joinR ? -1 : 0,
      transform: `scale(${pressed ? 0.97 : 1})`,
      boxShadow: pressed ? "inset 0 2px 4px rgba(0,0,0,.14)" : undefined,
    }}
  >
    {icon ? <Ico name={icon} size={12} color={primary ? "#fff" : active ? SF.brandDark : SF.brand} /> : null}
    {label}
  </div>
);

const IconBtn: React.FC<{ name: string }> = ({ name }) => (
  <div style={{ width: 30, height: 30, border: "1px solid #c9c9c9", borderRadius: 4, display: "flex", alignItems: "center", justifyContent: "center", background: "#fff" }}>
    <Ico name={name} size={13} color={SF.brand} />
  </div>
);

const Header: React.FC<{ title: string; sub: string; view: "list" | "calendar" }> = ({ title, sub, view }) => (
  <div style={{ display: "flex", alignItems: "center", padding: "12px 16px", gap: 12, borderBottom: `1px solid ${SF.border}` }}>
    <div style={{ width: 30, height: 30, borderRadius: 5, background: "linear-gradient(140deg,#f45e9e,#c2185b)", display: "flex", alignItems: "center", justifyContent: "center" }}>
      <Ico name="event" size={16} color="#fff" />
    </div>
    <div style={{ flex: 1 }}>
      <div style={{ fontSize: 18, fontWeight: 700 }}>{title}</div>
      <div style={{ fontSize: 13, color: SF.muted, marginTop: 1 }}>{sub}</div>
    </div>
    <Btn label="List" icon="rows" active={view === "list"} joinL />
    <Btn label="Calendar" icon="event" active={view === "calendar"} joinR />
    <div style={{ marginLeft: 8 }}>
      <IconBtn name="refresh" />
    </div>
    <div style={{ marginLeft: 8 }}>
      <Btn label="Schedule event" icon="add" primary />
    </div>
  </div>
);

const Tiles: React.FC<{ t: number; at: number }> = ({ t, at }) => {
  const count = (target: number, i: number) => Math.round(target * u(t, at + i * 0.1, 0.8, ease.out));
  const grow = u(t, at + 0.15, 0.7, ease.out);
  const tiles = [
    { label: "Awaiting onboarding", big: `${count(27, 0)}`, sub: "facilities", bar: 1.0, tone: SF.brand, lit: true, amber: false },
    { label: "No event booked", big: `${count(15, 1)}`, sub: "need scheduling", bar: 0.62, tone: "#a0632a", lit: false, amber: true },
    { label: "Booked this week", big: `${count(2, 2)}`, sub: "visits", bar: 0.1, tone: SF.brand, lit: true, amber: false },
    { label: "Next rollout", big: "Oct 4", sub: "Cedar Ridge SNF", bar: 0, tone: SF.muted, lit: false, amber: false },
  ];
  return (
    <div style={{ display: "grid", gridTemplateColumns: "repeat(4,1fr)", borderBottom: `1px solid ${SF.border}` }}>
      {tiles.map((x, i) => (
        <div key={x.label} style={{ padding: "11px 16px 0", borderRight: i < 3 ? `1px solid ${SF.border}` : undefined, background: x.lit ? SF.tileLit : "#fff", height: 62 }}>
          <div style={{ fontSize: 12.5, color: SF.weak }}>{x.label}</div>
          <div style={{ display: "flex", alignItems: "baseline", gap: 7, marginTop: 1 }}>
            <div style={{ fontSize: 25, fontWeight: 400, color: x.amber ? SF.amber : SF.ink, letterSpacing: -0.4 }}>{x.big}</div>
            <div style={{ fontSize: 12.5, color: x.amber ? SF.amber : SF.muted }}>{x.sub}</div>
          </div>
          <div style={{ height: 2.5, background: "#e8e8e8", marginTop: 9, borderRadius: 2 }}>
            <div style={{ height: 2.5, width: `${x.bar * 100 * grow}%`, background: x.tone, borderRadius: 2 }} />
          </div>
        </div>
      ))}
    </div>
  );
};

const FieldLabel: React.FC<{ children: React.ReactNode; info?: boolean }> = ({ children, info }) => (
  <div style={{ fontSize: 12, color: SF.weak, marginBottom: 3, display: "flex", alignItems: "center", gap: 5 }}>
    {children}
    {info ? <Ico name="info" size={11} color="#9b9b9b" /> : null}
  </div>
);

const Select: React.FC<{ value: string; w: number }> = ({ value, w }) => (
  <div style={{ width: w, height: 32, border: "1px solid #c9c9c9", borderRadius: 4, display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 10px", fontSize: 13 }}>
    {value}
    <Ico name="chevrondown" size={11} color={SF.brand} />
  </div>
);

const Filters: React.FC<{ typed?: string }> = ({ typed }) => (
  <div style={{ display: "flex", gap: 16, padding: "12px 16px", borderBottom: `1px solid ${SF.border}`, alignItems: "flex-end" }}>
    <div>
      <FieldLabel info>Search facilities</FieldLabel>
      <div style={{ width: 290, height: 32, border: "1px solid #c9c9c9", borderRadius: 4, display: "flex", alignItems: "center", gap: 8, padding: "0 10px", fontSize: 13, color: typed ? SF.ink : "#9b9b9b" }}>
        <Ico name="search" size={12} color="#747474" />
        {typed || "Facility or parent company"}
      </div>
    </div>
    <div>
      <FieldLabel>Date range</FieldLabel>
      <Select value="Next 30 days" w={150} />
    </div>
    <div>
      <FieldLabel>Program</FieldLabel>
      <Select value="All programs" w={145} />
    </div>
    <div>
      <FieldLabel>Sort by</FieldLabel>
      <Select value="Rollout date" w={145} />
    </div>
  </div>
);

const PatientBar: React.FC<{ f: Facility; k: number }> = ({ f, k }) => {
  const W = 400;
  return (
    <div style={{ width: W }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
        <span style={{ fontSize: 12.5, color: SF.weak }}>Patients</span>
        <span style={{ fontSize: 16, fontWeight: 400 }}>{Math.round(f.census * k)}</span>
      </div>
      <div style={{ position: "relative", height: 6, background: "#ececec", borderRadius: 3, marginTop: 4 }}>
        <div style={{ position: "absolute", height: 6, width: (f.seen / f.census) * W * k, background: "#9cc6f0", borderRadius: 3 }} />
        <div style={{ position: "absolute", height: 6, width: (f.consented / f.census) * W * k, background: SF.brand, borderRadius: 3 }} />
      </div>
      <div style={{ display: "flex", gap: 14, marginTop: 5, fontSize: 12, color: SF.weak }}>
        <span style={{ display: "flex", alignItems: "center", gap: 5 }}>
          <span style={{ width: 8, height: 8, background: "#9cc6f0", borderRadius: 1 }} /> {Math.round(f.seen * k)} seen
        </span>
        <span style={{ display: "flex", alignItems: "center", gap: 5 }}>
          <span style={{ width: 8, height: 8, background: SF.brand, borderRadius: 1 }} /> {Math.round(f.consented * k)} consented
        </span>
      </div>
    </div>
  );
};

export const Worklist: React.FC<{ t: number; rowsFrom?: number; countsFrom?: number; search?: string }> = ({
  t,
  rowsFrom = 0.3,
  countsFrom = 0.5,
  search,
}) => (
  <Chrome>
    <Header title="Onboarding worklist" sub="Facilities with status Onboarding or Opportunity" view="list" />
    <Tiles t={t} at={countsFrom} />
    <Filters typed={search} />
    <div>
      {FACILITIES.map((f, i) => {
        const k = u(t, rowsFrom + i * 0.09, 0.5, ease.out);
        const bar = u(t, rowsFrom + 0.2 + i * 0.09, 0.8, ease.out);
        return (
          <div
            key={f.name}
            style={{
              display: "flex",
              alignItems: "center",
              gap: 22,
              padding: "13px 16px",
              borderBottom: `1px solid ${SF.rowBorder}`,
              opacity: k,
              transform: `translateY(${(1 - k) * 12}px)`,
            }}
          >
            <div style={{ width: 300 }}>
              <div style={{ fontSize: 14.5, fontWeight: 700 }}>{f.name}</div>
              <div style={{ fontSize: 12.5, color: SF.muted, marginTop: 2 }}>
                {f.parent} · {f.state}
              </div>
            </div>
            <PatientBar f={f} k={bar} />
            <div style={{ width: 86 }}>
              <div style={{ fontSize: 14.5, fontWeight: 700 }}>{f.rollout}</div>
              <div style={{ fontSize: 12.5, color: SF.muted }}>rollout</div>
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ display: "inline-flex", alignItems: "center", gap: 5, padding: "2px 9px", borderRadius: 12, background: SF.greenBg, color: SF.green, fontSize: 12.5, fontWeight: 600 }}>
                <Ico name="check" size={10} color={SF.green} /> {f.events} event{f.events === 1 ? "" : "s"}
              </div>
              <div style={{ fontSize: 13, color: SF.link, marginTop: 5 }}>View on calendar</div>
              <div style={{ fontSize: 12.5, color: SF.muted, marginTop: 4 }}>next {f.next}</div>
            </div>
            <div style={{ width: 26, height: 24, border: "1px solid #c9c9c9", borderRadius: 4, display: "flex", alignItems: "center", justifyContent: "center" }}>
              <Ico name="down" size={10} color={SF.brand} />
            </div>
          </div>
        );
      })}
    </div>
    <div style={{ padding: "9px 16px", fontSize: 12.5, color: SF.weak }}>Showing all 22 facilities.</div>
  </Chrome>
);

// ---------------------------------------------------------------- calendar
export type Ev = { day: number; name: string; time: string; status: string; programs: string[]; cancelled?: boolean };
export const EVENTS: Ev[] = [
  { day: 3, name: "Maple Grove SNF", time: "4:00 PM", status: "Scheduled", programs: ["TCM", "BHI", "Community FT"] },
  { day: 4, name: "Brightwater Health Care", time: "3:00 PM", status: "Cancelled", programs: ["TCM"], cancelled: true },
  { day: 5, name: "Cedar Ridge SNF", time: "4:00 PM", status: "Scheduled", programs: ["BHI"] },
  { day: 7, name: "Cedar Hollow Skilled", time: "3:00 PM", status: "Scheduled", programs: ["TCM", "CCM"] },
  { day: 10, name: "Danville Nursing &", time: "3:00 PM", status: "Scheduled", programs: ["BHI"] },
  { day: 13, name: "Paxton Senior Living", time: "3:00 PM", status: "Scheduled", programs: ["BHI"] },
  { day: 13, name: "Easton Health Care", time: "3:00 PM", status: "Scheduled", programs: ["TCM", "BHI"] },
  { day: 13, name: "Grand Manor Nursing", time: "5:00 PM", status: "Scheduled", programs: ["CCM"] },
];

const Chip: React.FC<{ e: Ev; k: number }> = ({ e, k }) => (
  <div
    style={{
      background: e.cancelled ? "#f6f6f6" : "#edf6ef",
      borderLeft: `3px solid ${e.cancelled ? "#bdbdbd" : PROGRAM_COLOR[e.programs[0]] ?? SF.brand}`,
      borderRadius: 3,
      padding: "4px 6px",
      marginBottom: 4,
      opacity: k,
      transform: `translateY(${(1 - k) * 6}px)`,
    }}
  >
    <div style={{ fontSize: 11.5, fontWeight: 700, textDecoration: e.cancelled ? "line-through" : undefined, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
      {e.name}
    </div>
    <div style={{ display: "flex", alignItems: "center", gap: 5, marginTop: 2 }}>
      <span style={{ fontSize: 11, color: SF.muted }}>{e.time}</span>
      <span style={{ display: "inline-flex", alignItems: "center", gap: 3, fontSize: 10.5, fontWeight: 700, padding: "0 6px", borderRadius: 9, background: e.cancelled ? "#ececec" : "#e8f1fb", color: e.cancelled ? SF.muted : SF.brand }}>
        <Ico name={e.cancelled ? "dash" : "info"} size={8} color={e.cancelled ? SF.muted : SF.brand} />
        {e.status}
      </span>
    </div>
    <div style={{ display: "flex", alignItems: "center", gap: 5, marginTop: 2 }}>
      <span style={{ width: 6, height: 6, borderRadius: 3, background: PROGRAM_COLOR[e.programs[0]] ?? SF.muted }} />
      <span style={{ fontSize: 11, color: SF.muted, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{e.programs.join(", ")}</span>
    </div>
  </div>
);

export const Calendar: React.FC<{ t: number; chipsFrom?: number }> = ({ t, chipsFrom = 0.4 }) => {
  const heads = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  return (
    <Chrome>
      <Header title="October 2026" sub="Choose an event to edit it, or use the plus on a day" view="calendar" />
      <Tiles t={t} at={0.05} />
      <div style={{ display: "flex", justifyContent: "space-between", padding: "10px 16px", borderBottom: `1px solid ${SF.border}` }}>
        <div style={{ display: "flex" }}>
          <Btn label="Previous" icon="chevronleft" joinL />
          <Btn label="This month" joinR />
          <div style={{ width: 8 }} />
          <Btn label="Next" icon="chevronright" />
        </div>
        <div style={{ display: "flex" }}>
          <Btn label="Month" active joinL />
          <Btn label="Week" joinR />
          <Btn label="Day" joinR />
        </div>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(7,1fr)", background: "#f6f6f6", borderBottom: `1px solid ${SF.border}` }}>
        {heads.map((h) => (
          <div key={h} style={{ padding: "5px 8px", fontSize: 12, fontWeight: 700, color: "#3e3e3e" }}>
            {h}
          </div>
        ))}
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(7,1fr)" }}>
        {Array.from({ length: 21 }, (_, c) => {
          const dayNum = c - 2;
          const evs = EVENTS.filter((e) => e.day === c);
          const today = dayNum === 1;
          return (
            <div key={c} style={{ minHeight: 104, borderRight: "1px solid #f0f0f0", borderBottom: "1px solid #f0f0f0", padding: 5 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: 4 }}>
                <span
                  style={{
                    fontSize: 12,
                    fontWeight: 700,
                    color: dayNum < 1 ? "#b0b0b0" : today ? "#fff" : SF.ink,
                    background: today ? SF.brand : "transparent",
                    borderRadius: 3,
                    padding: today ? "1px 5px" : 0,
                  }}
                >
                  {dayNum < 1 ? 30 + dayNum : dayNum}
                </span>
                {today ? <span style={{ fontSize: 11, color: SF.link }}>Today</span> : null}
              </div>
              {evs.map((e, i) => (
                <Chip key={e.name} e={e} k={u(t, chipsFrom + i * 0.08 + c * 0.015, 0.4, ease.snap)} />
              ))}
            </div>
          );
        })}
      </div>
      <div style={{ display: "flex", gap: 14, padding: "8px 16px", fontSize: 11.5, color: SF.weak, borderTop: `1px solid ${SF.border}` }}>
        <b>Programs</b>
        {Object.entries(PROGRAM_COLOR).map(([k, c]) => (
          <span key={k} style={{ display: "flex", alignItems: "center", gap: 4 }}>
            <span style={{ width: 6, height: 6, borderRadius: 3, background: c }} />
            {k}
          </span>
        ))}
      </div>
    </Chrome>
  );
};

// ---------------------------------------------------------------- booking modal
const Check: React.FC<{ label: string; note?: string; on: boolean; pop: number }> = ({ label, note, on, pop }) => (
  <div style={{ display: "flex", gap: 9, alignItems: "flex-start", marginBottom: 11 }}>
    <div
      style={{
        width: 15,
        height: 15,
        borderRadius: 3,
        border: `1.5px solid ${on ? SF.brand : "#c9c9c9"}`,
        background: on ? SF.brand : "#fff",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        transform: `scale(${1 + 0.3 * pop})`,
        marginTop: 1,
      }}
    >
      {on ? <Ico name="check" size={9} color="#fff" /> : null}
    </div>
    <div>
      <div style={{ fontSize: 13.5 }}>{label}</div>
      {note ? <div style={{ fontSize: 11.5, color: SF.muted, marginTop: 1 }}>{note}</div> : null}
    </div>
  </div>
);

export const BookingModal: React.FC<{ t: number; ticks?: (number | undefined)[]; showPicker?: number }> = ({
  t,
  ticks = [],
  showPicker,
}) => {
  const on = (i: number) => ticks[i] !== undefined && t >= (ticks[i] as number);
  const pop = (i: number) => (ticks[i] === undefined ? 0 : Math.max(0, 1 - Math.abs(t - (ticks[i] as number)) / 0.25));
  const picker = showPicker !== undefined && t >= showPicker;
  const progs: [string, string | undefined][] = [
    ["TCM", undefined],
    ["CCM", "Not active at this facility."],
    ["BHI", undefined],
    ["CoCM", "Not active at this facility."],
    ["Telepsych", "Not active at this facility."],
    ["After Hours Telehealth", "Not active at this facility."],
    ["Community Full-Time", "Not tracked on the facility record."],
    ["IPV Onboarding", "Not tracked on the facility record."],
  ];
  const chosen = progs.filter((_, i) => on(i)).map((p) => p[0]);

  return (
    <div style={{ position: "absolute", inset: 0, fontFamily: FONT, color: SF.ink }}>
      <div style={{ position: "absolute", inset: 0, background: "rgba(8,22,38,.42)" }} />
      <div style={{ position: "absolute", left: 210, top: 44, width: 1020, height: 720, background: "#fff", borderRadius: 7, overflow: "hidden", boxShadow: "0 34px 80px rgba(0,0,0,.42)" }}>
        <div style={{ padding: "13px 0", textAlign: "center", fontSize: 19, fontWeight: 400, borderBottom: `1px solid ${SF.border}` }}>
          Edit facility onboarding
        </div>
        <div style={{ display: "flex", height: 616 }}>
          <div style={{ width: 268, padding: "16px 18px", borderRight: `1px solid ${SF.border}` }}>
            <div style={{ fontSize: 14.5, fontWeight: 700 }}>Easton Health Care Center</div>
            <div style={{ fontSize: 12, color: SF.muted, marginTop: 3 }}>Accolade Healthcare · OH · rollout Oct 16</div>
            <div style={{ fontSize: 13, color: SF.link, marginTop: 8 }}>Change facility</div>
            <div style={{ fontSize: 13, fontWeight: 700, marginTop: 20, marginBottom: 8 }}>Patients</div>
            <div style={{ display: "flex", gap: 8 }}>
              {[["Census", 91], ["Seen", 62], ["Consented", 40]].map(([l, v]) => (
                <div key={l as string} style={{ flex: 1, border: `1px solid ${SF.border}`, borderRadius: 4, padding: "7px 4px", textAlign: "center" }}>
                  <div style={{ fontSize: 11, color: SF.muted }}>{l}</div>
                  <div style={{ fontSize: 20 }}>{v}</div>
                </div>
              ))}
            </div>
            <div style={{ fontSize: 13, fontWeight: 700, marginTop: 20 }}>Eligibility</div>
            <div style={{ fontSize: 12, color: SF.muted, marginTop: 5 }}>Add a provider to run the licensing and conflict checks.</div>
          </div>
          <div style={{ flex: 1, padding: "16px 20px" }}>
            <div style={{ fontSize: 13.5, fontWeight: 700, marginBottom: 11 }}>Programs on this visit</div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", columnGap: 24 }}>
              {progs.map(([l, note], i) => (
                <Check key={l} label={l} note={note} on={on(i)} pop={pop(i)} />
              ))}
            </div>
            <div style={{ fontSize: 12.5, color: SF.weak, minHeight: 18 }}>
              {chosen.length ? `${chosen.length} programs on this visit: ${chosen.join(", ")}.` : ""}
            </div>
            <div style={{ fontSize: 13.5, fontWeight: 700, margin: "16px 0 9px", borderTop: `1px solid ${SF.border}`, paddingTop: 14 }}>
              Who is going
            </div>
            <FieldLabel>Add a provider</FieldLabel>
            <div style={{ position: "relative", width: 470 }}>
              <div style={{ height: 32, border: `1px solid ${picker ? SF.brand : "#c9c9c9"}`, borderRadius: 4, display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 10px", fontSize: 13, color: "#9b9b9b", boxShadow: picker ? `0 0 0 2px ${SF.brand}33` : undefined }}>
                Select a provider
                <Ico name="chevrondown" size={11} color={SF.brand} />
              </div>
              {picker ? (
                <div style={{ position: "absolute", left: 0, right: 0, top: 35, background: "#fff", border: `1px solid ${SF.border}`, borderRadius: 4, boxShadow: "0 10px 26px rgba(0,0,0,.2)", overflow: "hidden", zIndex: 2 }}>
                  {["Devon Farr", "Femi Okafor"].map((n, i) => (
                    <div key={n} style={{ padding: "9px 12px", fontSize: 13, background: i === 0 ? "#f3f8ff" : "#fff", opacity: u(t, (showPicker as number) + 0.08 + i * 0.09, 0.28) }}>
                      {n}
                    </div>
                  ))}
                </div>
              ) : null}
            </div>
            <div style={{ fontSize: 12, color: SF.weak, marginTop: picker ? 96 : 10, maxWidth: 600, lineHeight: 1.5 }}>
              0 of 4 slots used. Showing providers licensed in <b>Ohio</b> and approved for{" "}
              <b>{chosen.join(" and ") || "the selected programs"}</b>. <b>321 hidden</b>: 318 not licensed here, 3 not
              approved for every program.
            </div>
          </div>
        </div>
        <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 56, borderTop: `1px solid ${SF.border}`, background: "#fafaf9", display: "flex", alignItems: "center", justifyContent: "flex-end", gap: 9, padding: "0 18px" }}>
          <Btn label="Cancel" />
          <Btn label="Save changes" primary />
        </div>
      </div>
    </div>
  );
};

/** The app fills the frame, so native SLDS type lands near the readable floor before any zoom. */
export const AppFrame: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div style={{ position: "absolute", left: 0, top: 0, width: 1920, height: 1080, overflow: "hidden" }}>
    <div style={{ position: "absolute", left: 0, top: 0, width: APP_W, height: APP_H, transformOrigin: "0 0", transform: `scale(${1920 / APP_W})` }}>
      {children}
    </div>
  </div>
);
