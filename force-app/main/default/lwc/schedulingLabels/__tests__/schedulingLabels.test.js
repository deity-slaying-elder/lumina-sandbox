import {
  PROGRAMS,
  EVENT_STATUSES,
  programShortLabel,
  programClass,
  eventStatusTone,
  facilityStatusTone,
  coverageFor,
  eventChipClass
} from "c/schedulingLabels";

describe("c-scheduling-labels", () => {
  it("offers every programme the visit picklist allows", () => {
    expect(PROGRAMS).toHaveLength(8);
    expect(PROGRAMS).toEqual(
      expect.arrayContaining(["TCM", "CoCM", "After Hours Telehealth"])
    );
  });

  it("offers every event status the picklist allows", () => {
    expect(EVENT_STATUSES).toEqual([
      "Scheduled",
      "Confirmed",
      "Complete",
      "Cancelled"
    ]);
  });

  it("shortens only the long programme names", () => {
    expect(programShortLabel("After Hours Telehealth")).toBe("AHTH");
    expect(programShortLabel("IPV Onboarding")).toBe("IPV");
    expect(programShortLabel("TCM")).toBe("TCM");
  });

  it("gives every programme its own colour class", () => {
    const classes = PROGRAMS.map(programClass);
    expect(new Set(classes).size).toBe(PROGRAMS.length);
    expect(classes).not.toContain("none");
  });

  it("falls back to the neutral class for an unknown programme", () => {
    expect(programClass("Not A Program")).toBe("none");
    expect(programClass(null)).toBe("none");
  });

  it("maps event status to the house tone meanings", () => {
    expect(eventStatusTone("Scheduled")).toBe("info");
    expect(eventStatusTone("Confirmed")).toBe("info");
    expect(eventStatusTone("Complete")).toBe("success");
    expect(eventStatusTone("Cancelled")).toBe("neutral");
  });

  it("maps facility status to the house tone meanings", () => {
    expect(facilityStatusTone("Onboarding")).toBe("info");
    expect(facilityStatusTone("Active")).toBe("success");
    expect(facilityStatusTone("Hold")).toBe("warning");
  });

  it("never throws on an unknown status, it goes neutral", () => {
    expect(eventStatusTone(undefined)).toBe("neutral");
    expect(facilityStatusTone("Something New")).toBe("neutral");
  });
});

describe("coverageFor", () => {
  it("reads a facility with nothing booked as needing attention", () => {
    expect(coverageFor(0)).toEqual({
      label: "None yet",
      tone: "warning",
      iconName: "utility:clock"
    });
    expect(coverageFor(undefined).tone).toBe("warning");
  });

  it("reads a booked facility as done, and counts the events", () => {
    expect(coverageFor(1).label).toBe("1 event");
    expect(coverageFor(3).label).toBe("3 events");
    expect(coverageFor(3).tone).toBe("success");
  });
});

describe("eventChipClass", () => {
  it("colours a visit by its first programme", () => {
    expect(eventChipClass(["BHI", "TCM"], "Scheduled")).toBe("ev ev_bhi");
  });

  it("lets cancelled win over the programme colour", () => {
    expect(eventChipClass(["TCM"], "Cancelled")).toBe("ev ev_cancelled");
  });

  it("falls back to the neutral chip when no programme is set", () => {
    expect(eventChipClass([], "Scheduled")).toBe("ev ev_none");
    expect(eventChipClass(null, "Scheduled")).toBe("ev ev_none");
  });
});
