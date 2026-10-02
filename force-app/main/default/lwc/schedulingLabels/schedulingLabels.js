/**
 * One source for the scheduling vocabulary: the programmes, the event statuses,
 * and the tone each value is shown in. Kept in one module so a value always gets
 * the same tone on every screen, rather than the worklist and the calendar each
 * deciding for themselves.
 */

export const PROGRAMS = [
  "TCM",
  "CCM",
  "BHI",
  "CoCM",
  "Telepsych",
  "After Hours Telehealth",
  "Community Full-Time",
  "IPV Onboarding"
];

export const EVENT_STATUSES = [
  "Scheduled",
  "Confirmed",
  "Complete",
  "Cancelled"
];

/** Shorter names for the calendar key only. The stored picklist values are unchanged. */
const SHORT_LABEL = {
  "After Hours Telehealth": "AHTH",
  "Community Full-Time": "Community FT",
  "IPV Onboarding": "IPV"
};

/** One hue per programme. The suffix matches a .cal-event_* / .cal-swatch_* rule. */
const PROGRAM_CLASS = {
  TCM: "tcm",
  CCM: "ccm",
  BHI: "bhi",
  CoCM: "cocm",
  Telepsych: "telepsych",
  "After Hours Telehealth": "ahth",
  "Community Full-Time": "community",
  "IPV Onboarding": "ipv"
};

/**
 * Tones follow the house meanings: success is done, warning is waiting or needs a
 * look, info is new or active, neutral is inert or by design.
 */
const EVENT_STATUS_TONE = {
  // Scheduled is the ordinary state of a booked visit, so it reads as active, not as
  // something waiting on anyone. Amber stays free for the exceptions worth spotting.
  Scheduled: "info",
  Confirmed: "info",
  Complete: "success",
  Cancelled: "neutral"
};

const FACILITY_STATUS_TONE = {
  Onboarding: "info",
  Opportunity: "warning",
  Active: "success",
  Hold: "warning",
  Inactive: "neutral"
};

export function programShortLabel(program) {
  return SHORT_LABEL[program] || program;
}

export function programClass(program) {
  return PROGRAM_CLASS[program] || "none";
}

export function eventStatusTone(status) {
  return EVENT_STATUS_TONE[status] || "neutral";
}

export function facilityStatusTone(status) {
  return FACILITY_STATUS_TONE[status] || "neutral";
}

/**
 * How a facility's event coverage is shown in the worklist. A facility with nothing
 * booked is the thing this screen exists to surface, so it gets a warning chip rather
 * than a zero the eye slides past.
 */
export function coverageFor(eventCount) {
  const n = eventCount || 0;
  return n > 0
    ? {
        label: `${n} event${n === 1 ? "" : "s"}`,
        tone: "success",
        iconName: "utility:check"
      }
    : { label: "None yet", tone: "warning", iconName: "utility:clock" };
}

/**
 * The calendar chip's class. A cancelled visit always reads as cancelled, whatever
 * programmes are on it; otherwise the first programme sets the hue and the chip names
 * them all in text beside it.
 */
export function eventChipClass(programs, status) {
  if (status === "Cancelled") {
    return "ev ev_cancelled";
  }
  const lead = programs && programs.length ? programs[0] : null;
  return `ev ev_${programClass(lead)}`;
}
