import { createElement } from "@lwc/engine-dom";
import FacilityScheduling from "c/facilityScheduling";
import getWorklist from "@salesforce/apex/FacilitySchedulingController.getWorklist";
import getEvents from "@salesforce/apex/FacilitySchedulingController.getEvents";
import getSummary from "@salesforce/apex/FacilitySchedulingController.getSummary";
import FacilitySchedulingBooking from "c/facilitySchedulingBooking";

// jest.mock only hoists when it is written at the top level, so these are spelled
// out rather than produced by a helper.
jest.mock(
  "@salesforce/apex/FacilitySchedulingController.getWorklist",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FacilitySchedulingController.getEvents",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FacilitySchedulingController.getSummary",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "c/facilitySchedulingBooking",
  () => ({ __esModule: true, default: { open: jest.fn() } }),
  { virtual: true }
);

const DAY = 86400000;
const iso = (offsetDays) =>
  new Date(Date.now() + offsetDays * DAY).toISOString().slice(0, 10);

const ROW = {
  facilityId: "a01000000000001",
  name: "ZZ TEST - Cedar Ridge SNF",
  parentCompany: "ZZ TEST Cedar Group",
  status: "Onboarding",
  rolloutDate: iso(4),
  stateCode: "PA",
  census: 128,
  seen: 64,
  consented: 32,
  eventCount: 2,
  nextEventStart: new Date(Date.now() + 2 * DAY).toISOString()
};

const SUMMARY = {
  awaiting: 18,
  unscheduled: 5,
  bookedThisWeek: 6,
  nextRolloutDate: iso(3),
  nextRolloutFacility: "ZZ TEST - Cedar Ridge SNF"
};

function build() {
  const el = createElement("c-facility-scheduling", { is: FacilityScheduling });
  document.body.appendChild(el);
  return el;
}

async function settle() {
  for (let i = 0; i < 14; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

const text = (el) => (el ? el.textContent.replace(/\s+/g, " ").trim() : null);

function calendarButton(el) {
  return [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.dataset.view === "calendar"
  );
}

describe("c-facility-scheduling", () => {
  beforeEach(() => {
    getWorklist.mockResolvedValue([ROW]);
    getEvents.mockResolvedValue([]);
    getSummary.mockResolvedValue(SUMMARY);
    FacilitySchedulingBooking.open.mockResolvedValue(null);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  // ---------------------------------------------------------------- rows
  it("renders one designed row per facility, not a datatable", async () => {
    const el = build();
    await settle();

    expect(el.shadowRoot.querySelector("c-scheduling-datatable")).toBeNull();
    const rows = el.shadowRoot.querySelectorAll(".row");
    expect(rows).toHaveLength(1);
    expect(text(rows[0].querySelector(".who__name"))).toBe(
      "ZZ TEST - Cedar Ridge SNF"
    );
  });

  it("carries the parent company and state under the name", async () => {
    const el = build();
    await settle();

    const sub = text(el.shadowRoot.querySelector(".who__sub"));
    expect(sub).toContain("ZZ TEST Cedar Group");
    expect(sub).toContain("PA");
  });

  it("says so plainly when a facility has no parent or state", async () => {
    getWorklist.mockResolvedValue([
      { ...ROW, parentCompany: null, stateCode: null }
    ]);
    const el = build();
    await settle();

    const sub = text(el.shadowRoot.querySelector(".who__sub"));
    expect(sub).toContain("No parent company");
    expect(sub).toContain("No state on address");
  });

  // ---------------------------------------------------------------- progress
  it("draws the patient counts as a bar instead of three numbers", async () => {
    const el = build();
    await settle();

    const track = el.shadowRoot.querySelector(".prog__track");
    expect(track.getAttribute("role")).toBe("img");
    expect(track.getAttribute("aria-label")).toBe(
      "64 of 128 seen, 32 consented"
    );
    expect(track.querySelector(".prog__seen").style.width).toBe("50%");
    expect(track.querySelector(".prog__consent").style.width).toBe("25%");
  });

  it("reads as not loaded yet rather than broken when the census is zero", async () => {
    getWorklist.mockResolvedValue([
      { ...ROW, census: 0, seen: 0, consented: 0 }
    ]);
    const el = build();
    await settle();

    expect(el.shadowRoot.querySelector(".prog__track")).toBeNull();
    expect(text(el.shadowRoot.querySelector(".prog__empty"))).toBe(
      "No patients loaded yet"
    );
  });

  // ---------------------------------------------------------------- booked state
  it("shows the next visit date when something is booked", async () => {
    const el = build();
    await settle();

    const chip = el.shadowRoot.querySelector("c-status-chip");
    expect(chip.label).toBe("2 events");
    expect(chip.tone).toBe("success");
    expect(text(el.shadowRoot.querySelector(".booked__next"))).toMatch(
      /^next /
    );
  });

  it("counts down to the rollout when nothing is booked", async () => {
    getWorklist.mockResolvedValue([
      { ...ROW, eventCount: 0, nextEventStart: null, rolloutDate: iso(7) }
    ]);
    const el = build();
    await settle();

    expect(el.shadowRoot.querySelector("c-status-chip").tone).toBe("warning");
    expect(text(el.shadowRoot.querySelector(".booked__next"))).toBe(
      "7 days out"
    );
  });

  it("calls out a rollout that has already passed", async () => {
    getWorklist.mockResolvedValue([
      { ...ROW, eventCount: 0, nextEventStart: null, rolloutDate: iso(-3) }
    ]);
    const el = build();
    await settle();

    expect(text(el.shadowRoot.querySelector(".booked__next"))).toBe(
      "3 days overdue"
    );
  });

  // ---------------------------------------------------------------- summary strip
  it("leads with a summary strip of the whole queue", async () => {
    const el = build();
    await settle();

    const tiles = el.shadowRoot.querySelectorAll(".stat");
    expect(tiles).toHaveLength(4);
    expect(text(tiles[0])).toContain("18");
    expect(text(tiles[1])).toContain("5");
    expect(text(tiles[2])).toContain("6");
    expect(text(tiles[3])).toContain("ZZ TEST - Cedar Ridge SNF");
  });

  it("keeps the strip unfiltered so it does not move when the list narrows", async () => {
    const el = build();
    await settle();

    const combos = el.shadowRoot.querySelectorAll("lightning-combobox");
    combos[1].dispatchEvent(
      new CustomEvent("change", { detail: { value: "TCM" } })
    );
    await settle();

    expect(getSummary).toHaveBeenCalledTimes(1);
    expect(text(el.shadowRoot.querySelectorAll(".stat")[0])).toContain("18");
  });

  it("filters to the unscheduled facilities from the strip", async () => {
    getWorklist.mockResolvedValue([
      ROW,
      { ...ROW, facilityId: "b", name: "ZZ TEST - B", eventCount: 0 }
    ]);
    const el = build();
    await settle();

    const unscheduledTile = el.shadowRoot.querySelector(
      '[data-stat="unscheduled"]'
    );
    expect(unscheduledTile.getAttribute("aria-pressed")).toBe("false");
    unscheduledTile.click();
    await settle();

    expect(el.shadowRoot.querySelectorAll(".row")).toHaveLength(1);
    expect(
      el.shadowRoot
        .querySelector('[data-stat="unscheduled"]')
        .getAttribute("aria-pressed")
    ).toBe("true");
  });

  it("sends every tile somewhere, including from the calendar", async () => {
    const el = build();
    await settle();

    // Next rollout is a list question, so it sorts the list by rollout date.
    const next = el.shadowRoot.querySelector('[data-stat="next"]');
    expect(next.disabled).toBe(false);
    next.click();
    await settle();

    // From the calendar, the two list tiles used to do nothing at all.
    el.shadowRoot.querySelector('[data-stat="week"]').click();
    await settle();
    expect(el.shadowRoot.querySelector(".calbar")).not.toBeNull();

    el.shadowRoot.querySelector('[data-stat="unscheduled"]').click();
    await settle();
    expect(el.shadowRoot.querySelector(".calbar")).toBeNull();
    expect(
      el.shadowRoot
        .querySelector('[data-stat="unscheduled"]')
        .getAttribute("aria-pressed")
    ).toBe("true");
  });

  it("survives a summary failure without losing the list", async () => {
    getSummary.mockRejectedValue({ body: { message: "nope" } });
    const el = build();
    await settle();

    expect(el.shadowRoot.querySelectorAll(".row")).toHaveLength(1);
    expect(text(el.shadowRoot.querySelectorAll(".stat")[0])).toContain("0");
  });

  // ---------------------------------------------------------------- sorting
  it("sorts from an explicit control, since custom rows have no column headers", async () => {
    getWorklist.mockResolvedValue([
      { ...ROW, facilityId: "a", name: "ZZ C", rolloutDate: iso(9) },
      { ...ROW, facilityId: "b", name: "ZZ A", rolloutDate: null },
      { ...ROW, facilityId: "c", name: "ZZ B", rolloutDate: iso(2) }
    ]);
    const el = build();
    await settle();

    const names = () =>
      [...el.shadowRoot.querySelectorAll(".who__name")].map((n) => text(n));
    // Default is rollout date, blanks last.
    expect(names()).toEqual(["ZZ B", "ZZ C", "ZZ A"]);

    const sort = [...el.shadowRoot.querySelectorAll("lightning-combobox")].find(
      (c) => c.label === "Sort by"
    );
    sort.dispatchEvent(
      new CustomEvent("change", { detail: { value: "name" } })
    );
    await settle();
    expect(names()).toEqual(["ZZ A", "ZZ B", "ZZ C"]);
  });

  it("sorts census largest first", async () => {
    getWorklist.mockResolvedValue([
      { ...ROW, facilityId: "a", name: "ZZ small", census: 10 },
      { ...ROW, facilityId: "b", name: "ZZ big", census: 300 }
    ]);
    const el = build();
    await settle();

    const sort = [...el.shadowRoot.querySelectorAll("lightning-combobox")].find(
      (c) => c.label === "Sort by"
    );
    sort.dispatchEvent(
      new CustomEvent("change", { detail: { value: "census" } })
    );
    await settle();

    expect(
      [...el.shadowRoot.querySelectorAll(".who__name")].map((n) => text(n))
    ).toEqual(["ZZ big", "ZZ small"]);
  });

  // ---------------------------------------------------------------- filters
  it("hides the custom date inputs unless a custom range is chosen", async () => {
    const el = build();
    await settle();
    const dates = () =>
      [...el.shadowRoot.querySelectorAll("lightning-input")].filter(
        (i) => i.type === "date"
      );
    expect(dates()).toHaveLength(0);

    el.shadowRoot
      .querySelector("lightning-combobox")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: "custom" } })
      );
    await settle();
    expect(dates()).toHaveLength(2);
  });

  it("sends the search term to Apex after the debounce", async () => {
    jest.useFakeTimers();
    const el = build();
    await settle();

    el.shadowRoot
      .querySelector(".filters__search")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "Cedar" } }));
    jest.runAllTimers();
    await settle();

    expect(getWorklist).toHaveBeenLastCalledWith(
      expect.objectContaining({ searchTerm: "Cedar" })
    );
    jest.useRealTimers();
  });

  it("offers Clear filters only once something differs from the defaults", async () => {
    const el = build();
    await settle();
    const clear = () =>
      [...el.shadowRoot.querySelectorAll("lightning-button")].find(
        (b) => b.label === "Clear filters"
      );
    expect(clear()).toBeUndefined();

    el.shadowRoot
      .querySelectorAll("lightning-combobox")[1]
      .dispatchEvent(new CustomEvent("change", { detail: { value: "TCM" } }));
    await settle();
    expect(clear()).toBeTruthy();
  });

  // ---------------------------------------------------------------- states
  it("offers a filtered empty state that quotes the filter", async () => {
    getWorklist.mockResolvedValue([]);
    const el = build();
    await settle();

    el.shadowRoot
      .querySelectorAll("lightning-combobox")[1]
      .dispatchEvent(new CustomEvent("change", { detail: { value: "TCM" } }));
    await settle();

    const empty = el.shadowRoot.querySelector("c-empty-state");
    expect(empty.variant).toBe("filtered");
    expect(empty.body).toContain("TCM");
  });

  it("shows a failed state with Try again, and no rows", async () => {
    getWorklist.mockRejectedValue({ body: { message: "Reference 4821." } });
    const el = build();
    await settle();

    const failed = el.shadowRoot.querySelector("c-empty-state");
    expect(failed.variant).toBe("failed");
    expect(failed.body).toContain("Reference 4821.");
    expect(el.shadowRoot.querySelectorAll(".row")).toHaveLength(0);
  });

  it("says when the list has been capped", async () => {
    getWorklist.mockResolvedValue(
      Array.from({ length: 200 }, (unused, i) => ({
        ...ROW,
        facilityId: `f${i}`,
        name: `ZZ TEST ${i}`
      }))
    );
    const el = build();
    await settle();

    expect(text(el.shadowRoot.querySelector(".tablefoot"))).toContain(
      "first 200"
    );
  });

  // ---------------------------------------------------------------- booking
  it("books from the row menu", async () => {
    const el = build();
    await settle();

    const menu = el.shadowRoot.querySelector("lightning-button-menu");
    menu.dispatchEvent(
      new CustomEvent("select", { detail: { value: "schedule" } })
    );
    await settle();

    expect(FacilitySchedulingBooking.open).toHaveBeenCalledTimes(1);
    expect(
      FacilitySchedulingBooking.open.mock.calls[0][0].context.facilityId
    ).toBe(ROW.facilityId);
  });

  it("toasts and reloads after a save", async () => {
    FacilitySchedulingBooking.open.mockResolvedValue({
      savedId: "a02",
      facilityName: ROW.name,
      edited: false
    });
    const el = build();
    await settle();

    const toast = jest.fn();
    el.addEventListener("lightning__showtoast", toast);
    el.shadowRoot
      .querySelector("lightning-button-menu")
      .dispatchEvent(
        new CustomEvent("select", { detail: { value: "schedule" } })
      );
    await settle();

    expect(toast.mock.calls[0][0].detail.title).toBe(
      "Onboarding visit scheduled"
    );
    expect(getWorklist).toHaveBeenCalledTimes(2);
  });

  it("never stacks a second booking dialog on a double click", async () => {
    let release;
    FacilitySchedulingBooking.open.mockImplementation(
      () =>
        new Promise((r) => {
          release = r;
        })
    );
    const el = build();
    await settle();

    const menu = el.shadowRoot.querySelector("lightning-button-menu");
    menu.dispatchEvent(
      new CustomEvent("select", { detail: { value: "schedule" } })
    );
    await settle();
    menu.dispatchEvent(
      new CustomEvent("select", { detail: { value: "schedule" } })
    );
    await settle();

    expect(FacilitySchedulingBooking.open).toHaveBeenCalledTimes(1);
    release(null);
    await settle();
  });

  // ---------------------------------------------------------------- calendar
  it("renders a multi-programme event with one tint and one dot", async () => {
    getEvents.mockResolvedValue([
      {
        eventId: "a09",
        facilityId: ROW.facilityId,
        facilityName: ROW.name,
        startTime: new Date().toISOString(),
        endTime: new Date().toISOString(),
        programs: ["TCM", "BHI"],
        programLabel: "TCM, BHI",
        onboardingStatus: "Scheduled",
        providerIds: []
      }
    ]);
    const el = build();
    await settle();
    calendarButton(el).click();
    await settle();

    const chip = el.shadowRoot.querySelector(".ev");
    expect(chip.className).toContain("ev_tcm");
    expect(chip.querySelector(".ev__dot").className).toContain("ev__dot_tcm");
    // Every programme on the visit is on the chip itself, not only in the tooltip.
    expect(chip.textContent).toContain("TCM, BHI");
    expect(chip.getAttribute("title")).toContain("TCM, BHI");
  });

  it("opens on the month and shows one empty state, not a cell per day", async () => {
    const el = build();
    await settle();
    calendarButton(el).click();
    await settle();

    // No grid at all when the span is empty, and one statement rather than 42.
    expect(el.shadowRoot.querySelectorAll(".cal__cell")).toHaveLength(0);
    expect(el.shadowRoot.querySelector("c-empty-state").heading).toBe(
      "Nothing booked this month"
    );
  });

  it("asks Apex for a whole month, padded to whole weeks", async () => {
    const el = build();
    await settle();
    calendarButton(el).click();
    await settle();

    const call = getEvents.mock.calls[getEvents.mock.calls.length - 1][0];
    const from = new Date(call.fromDate);
    const to = new Date(call.toDate);
    expect(from.getUTCDay()).toBe(0);
    expect(Math.round((to - from) / 86400000)).toBe(41);
  });

  it("switches to week and day, and narrows the span each time", async () => {
    getEvents.mockResolvedValue([
      {
        eventId: "a09",
        facilityId: ROW.facilityId,
        facilityName: ROW.name,
        startTime: new Date().toISOString(),
        endTime: new Date().toISOString(),
        programs: ["TCM"],
        programLabel: "TCM",
        onboardingStatus: "Scheduled",
        providerIds: []
      }
    ]);
    const el = build();
    await settle();
    calendarButton(el).click();
    await settle();

    const span = el.shadowRoot.querySelector("lightning-radio-group");
    // A real segmented control, so the current span reads as a selection.
    expect(span.value).toBe("month");
    expect(span.options.map((o) => o.value)).toEqual(["month", "week", "day"]);
    expect(el.shadowRoot.querySelectorAll(".cal__cell")).toHaveLength(42);

    span.dispatchEvent(
      new CustomEvent("change", { detail: { value: "week" } })
    );
    await settle();
    expect(el.shadowRoot.querySelectorAll(".cal__cell")).toHaveLength(7);

    span.dispatchEvent(new CustomEvent("change", { detail: { value: "day" } }));
    await settle();
    expect(el.shadowRoot.querySelectorAll(".cal__cell")).toHaveLength(0);
    expect(el.shadowRoot.querySelector(".daylist")).not.toBeNull();
  });

  it("books into the day whose add button was used", async () => {
    getEvents.mockResolvedValue([
      {
        eventId: "a1",
        facilityId: ROW.facilityId,
        facilityName: ROW.name,
        startTime: new Date().toISOString(),
        endTime: new Date().toISOString(),
        programs: ["TCM"],
        programLabel: "TCM",
        onboardingStatus: "Scheduled",
        providerIds: []
      }
    ]);
    const el = build();
    await settle();
    calendarButton(el).click();
    await settle();

    el.shadowRoot.querySelector(".cal__add").click();
    await settle();

    const ctx = FacilitySchedulingBooking.open.mock.calls[0][0].context;
    expect(new Date(ctx.startTime).getHours()).toBe(10);
  });

  it("marks exactly one summary tile as current", async () => {
    const el = build();
    await settle();

    const pressed = () =>
      [...el.shadowRoot.querySelectorAll(".stat")].filter(
        (t) => t.getAttribute("aria-pressed") === "true"
      ).length;
    expect(pressed()).toBe(1);

    el.shadowRoot.querySelector('[data-stat="unscheduled"]').click();
    await settle();
    expect(pressed()).toBe(1);

    // Switching to the week must not leave a list filter looking selected too.
    el.shadowRoot.querySelector('[data-stat="week"]').click();
    await settle();
    expect(pressed()).toBe(1);
    expect(
      el.shadowRoot
        .querySelector('[data-stat="week"]')
        .getAttribute("aria-pressed")
    ).toBe("true");
  });

  it("drops the filters that do nothing to a calendar", async () => {
    const el = build();
    await settle();

    const labels = () =>
      [
        ...el.shadowRoot.querySelectorAll("lightning-combobox, lightning-input")
      ].map((c) => c.label);
    expect(labels()).toEqual(
      expect.arrayContaining(["Search facilities", "Date range", "Sort by"])
    );

    calendarButton(el).click();
    await settle();

    const onCalendar = labels();
    expect(onCalendar).not.toContain("Search facilities");
    expect(onCalendar).not.toContain("Date range");
    expect(onCalendar).not.toContain("Sort by");
    // Program narrows both views, so it stays.
    expect(onCalendar).toContain("Program");
  });

  it("opens the booking dialog when a calendar event is chosen", async () => {
    const EVENT = {
      eventId: "a0X000000000001",
      facilityId: ROW.facilityId,
      facilityName: ROW.name,
      startTime: new Date().toISOString(),
      endTime: new Date().toISOString(),
      programs: ["TCM", "BHI"],
      programLabel: "TCM, BHI",
      onboardingStatus: "Confirmed",
      facilitatorId: "a03000000000001",
      providerIds: ["a02000000000001"],
      providerNamesFull: "Ada Rowe"
    };
    getEvents.mockResolvedValue([EVENT]);
    const el = build();
    await settle();
    calendarButton(el).click();
    await settle();

    const chip = el.shadowRoot.querySelector(".ev");
    expect(chip).not.toBeNull();
    chip.click();
    await settle();

    expect(FacilitySchedulingBooking.open).toHaveBeenCalledTimes(1);
    const ctx = FacilitySchedulingBooking.open.mock.calls[0][0].context;
    expect(ctx.eventId).toBe(EVENT.eventId);
    expect(ctx.programs).toEqual(["TCM", "BHI"]);
    expect(ctx.onboardingStatus).toBe("Confirmed");
    expect(ctx.providerIds).toEqual(["a02000000000001"]);
  });

  it("opens an event from the day view too", async () => {
    getEvents.mockResolvedValue([
      {
        eventId: "a0X000000000002",
        facilityId: ROW.facilityId,
        facilityName: ROW.name,
        startTime: new Date().toISOString(),
        endTime: new Date().toISOString(),
        programs: ["TCM"],
        programLabel: "TCM",
        onboardingStatus: "Scheduled",
        providerIds: []
      }
    ]);
    const el = build();
    await settle();
    calendarButton(el).click();
    await settle();

    el.shadowRoot
      .querySelector("lightning-radio-group")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "day" } }));
    await settle();

    el.shadowRoot.querySelector(".daylist .ev").click();
    await settle();

    expect(FacilitySchedulingBooking.open).toHaveBeenCalledTimes(1);
    expect(
      FacilitySchedulingBooking.open.mock.calls[0][0].context.eventId
    ).toBe("a0X000000000002");
  });

  it("jumps from a row's event count to that facility on the calendar", async () => {
    getEvents.mockResolvedValue([
      {
        eventId: "a1",
        facilityId: ROW.facilityId,
        facilityName: ROW.name,
        startTime: new Date().toISOString(),
        endTime: new Date().toISOString(),
        programs: ["TCM"],
        programLabel: "TCM",
        onboardingStatus: "Scheduled",
        providerIds: []
      },
      {
        eventId: "a2",
        facilityId: "other",
        facilityName: "ZZ Somewhere Else",
        startTime: new Date().toISOString(),
        endTime: new Date().toISOString(),
        programs: ["CCM"],
        programLabel: "CCM",
        onboardingStatus: "Scheduled",
        providerIds: []
      }
    ]);
    const el = build();
    await settle();

    el.shadowRoot.querySelector(".booked__link").click();
    await settle();

    // On the calendar, showing that facility alone, with a pill to drop the focus.
    expect(el.shadowRoot.querySelector(".calbar")).not.toBeNull();
    expect(el.shadowRoot.querySelectorAll(".ev")).toHaveLength(1);
    const focus = el.shadowRoot.querySelector(".focusbar");
    expect(focus.textContent).toContain(ROW.name);

    [...el.shadowRoot.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Show all facilities")
      .click();
    await settle();
    expect(el.shadowRoot.querySelectorAll(".ev")).toHaveLength(2);
  });

  it("gives a facility with nothing booked a plain chip, not a link", async () => {
    getWorklist.mockResolvedValue([
      { ...ROW, eventCount: 0, nextEventStart: null }
    ]);
    const el = build();
    await settle();

    expect(el.shadowRoot.querySelector(".booked__link")).toBeNull();
    expect(el.shadowRoot.querySelector("c-status-chip").tone).toBe("warning");
  });

  it("keeps the search box on the calendar and filters events by it", async () => {
    jest.useFakeTimers();
    getEvents.mockResolvedValue([
      {
        eventId: "a1",
        facilityId: "f1",
        facilityName: "TST Brightwater Health Care Center",
        startTime: new Date().toISOString(),
        endTime: new Date().toISOString(),
        programs: ["TCM"],
        programLabel: "TCM",
        onboardingStatus: "Scheduled",
        providerIds: []
      },
      {
        eventId: "a2",
        facilityId: "f2",
        facilityName: "TST Piketon Nursing Care Center",
        startTime: new Date().toISOString(),
        endTime: new Date().toISOString(),
        programs: ["CCM"],
        programLabel: "CCM",
        onboardingStatus: "Scheduled",
        providerIds: []
      }
    ]);
    const el = build();
    await settle();
    calendarButton(el).click();
    await settle();
    expect(el.shadowRoot.querySelectorAll(".ev")).toHaveLength(2);

    const search = el.shadowRoot.querySelector(".filters__search");
    expect(search).not.toBeNull();
    search.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Brightwater" } })
    );
    jest.runAllTimers();
    await settle();

    expect(el.shadowRoot.querySelectorAll(".ev")).toHaveLength(1);
    jest.useRealTimers();
  });
});
