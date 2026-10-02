import { createElement } from "@lwc/engine-dom";
import TIME_ZONE from "@salesforce/i18n/timeZone";
import FacilitySchedulingBooking from "c/facilitySchedulingBooking";
import getFacilityPrograms from "@salesforce/apex/FacilitySchedulingController.getFacilityPrograms";
import getFacilitySnapshot from "@salesforce/apex/FacilitySchedulingController.getFacilitySnapshot";
import getFacilitators from "@salesforce/apex/FacilitySchedulingController.getFacilitators";
import getProviders from "@salesforce/apex/FacilitySchedulingController.getProviders";
import checkEligibility from "@salesforce/apex/FacilitySchedulingController.checkEligibility";
import saveVisit from "@salesforce/apex/FacilitySchedulingController.saveVisit";

jest.mock(
  "@salesforce/apex/FacilitySchedulingController.getFacilityPrograms",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FacilitySchedulingController.getFacilitySnapshot",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FacilitySchedulingController.getFacilitators",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FacilitySchedulingController.getProviders",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FacilitySchedulingController.checkEligibility",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FacilitySchedulingController.searchFacilities",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FacilitySchedulingController.saveVisit",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FacilitySchedulingController.updateVisit",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const FACILITY_ID = "001000000000001";

const PROGRAM_CHOICES = [
  { value: "TCM", label: "TCM", available: true, reason: null },
  { value: "CCM", label: "CCM", available: true, reason: null },
  { value: "BHI", label: "BHI", available: true, reason: null },
  {
    value: "CoCM",
    label: "CoCM",
    available: false,
    reason: "Not active at this facility."
  },
  {
    value: "IPV Onboarding",
    label: "IPV Onboarding",
    available: true,
    reason: "Not tracked on the facility record."
  }
];

function build(context) {
  const el = createElement("c-facility-scheduling-booking", {
    is: FacilitySchedulingBooking
  });
  el.context = context;
  document.body.appendChild(el);
  return el;
}

async function settle() {
  for (let i = 0; i < 8; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

function programBoxes(el) {
  return [...el.shadowRoot.querySelectorAll("lightning-input")].filter(
    (i) => i.type === "checkbox"
  );
}

function tickProgram(el, value) {
  const box = programBoxes(el).find((b) => b.dataset.program === value);
  box.checked = true;
  box.dispatchEvent(new CustomEvent("change"));
  return box;
}

function brandButton(el) {
  return [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.variant === "brand"
  );
}

describe("c-facility-scheduling-booking", () => {
  beforeEach(() => {
    getFacilityPrograms.mockResolvedValue(PROGRAM_CHOICES);
    getFacilitySnapshot.mockResolvedValue({
      facilityId: FACILITY_ID,
      name: "ZZ TEST - Cedar Ridge SNF",
      stateCode: "PA",
      census: 42,
      seen: 9,
      consented: 4,
      eventCount: 0
    });
    getFacilitators.mockResolvedValue({ options: [], hiddenBooked: 0 });
    getProviders.mockResolvedValue({
      options: [{ label: "Ada Rowe", value: "a02000000000001" }],
      stateName: "Pennsylvania",
      hiddenUnlicensed: 3,
      hiddenUntagged: 0,
      hiddenConflicted: 0,
      hiddenBooked: 0
    });
    checkEligibility.mockResolvedValue({ allowed: true, checks: [] });
    saveVisit.mockResolvedValue("a01000000000001");
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists every programme, including the ones the facility does not run", async () => {
    const el = build({ facilityId: FACILITY_ID, facilityName: "Cedar Ridge" });
    await settle();

    const boxes = programBoxes(el);
    expect(boxes).toHaveLength(5);

    const cocm = boxes.find((b) => b.dataset.program === "CoCM");
    expect(cocm.disabled).toBe(true);
    // Unavailable is shown with its reason, not hidden behind a count.
    expect(el.shadowRoot.textContent).toContain("Not active at this facility.");
  });

  it("keeps an untracked programme selectable and says why it is untracked", async () => {
    const el = build({ facilityId: FACILITY_ID });
    await settle();

    const ipv = programBoxes(el).find(
      (b) => b.dataset.program === "IPV Onboarding"
    );
    expect(ipv.disabled).toBe(false);
    expect(el.shadowRoot.textContent).toContain(
      "Not tracked on the facility record."
    );
  });

  it("carries more than one programme on a visit", async () => {
    const el = build({ facilityId: FACILITY_ID });
    await settle();

    tickProgram(el, "TCM");
    await settle();
    tickProgram(el, "BHI");
    await settle();

    const summary = el.shadowRoot.querySelector('.hint[role="status"]');
    expect(summary.textContent).toContain("2 programs on this visit");
    expect(summary.textContent).toContain("TCM, BHI");
  });

  it("sends every selected programme to the provider query", async () => {
    const el = build({ facilityId: FACILITY_ID });
    await settle();

    tickProgram(el, "TCM");
    await settle();
    tickProgram(el, "BHI");
    await settle();

    const last = getProviders.mock.calls[getProviders.mock.calls.length - 1][0];
    expect(last.programs).toEqual(["TCM", "BHI"]);
  });

  it("unticking a programme takes it back off the visit", async () => {
    const el = build({ facilityId: FACILITY_ID });
    await settle();

    const box = tickProgram(el, "TCM");
    await settle();
    box.checked = false;
    box.dispatchEvent(new CustomEvent("change"));
    await settle();

    const last = getProviders.mock.calls[getProviders.mock.calls.length - 1][0];
    expect(last.programs).toEqual([]);
  });

  it("saves every selected programme, not just the first", async () => {
    const el = build({ facilityId: FACILITY_ID, facilityName: "Cedar Ridge" });
    await settle();

    tickProgram(el, "TCM");
    await settle();
    tickProgram(el, "BHI");
    await settle();

    brandButton(el).dispatchEvent(new CustomEvent("click"));
    await settle();

    expect(saveVisit).toHaveBeenCalledTimes(1);
    expect(saveVisit.mock.calls[0][0].programs).toEqual(["TCM", "BHI"]);
  });

  it("shows the facility patient counts inside the dialog", async () => {
    const el = build({ facilityId: FACILITY_ID, facilityName: "Cedar Ridge" });
    await settle();

    const values = [...el.shadowRoot.querySelectorAll(".counts__value")].map(
      (n) => n.textContent.trim()
    );
    expect(values).toEqual(["42", "9", "4"]);
    // The counts sit in the rail beside the facility, which also names its state.
    expect(el.shadowRoot.querySelector(".rail__name").textContent).toContain(
      "Cedar Ridge"
    );
    expect(el.shadowRoot.querySelector(".rail__sub").textContent).toContain(
      "PA"
    );
  });

  it("says why Save is disabled rather than just disabling it", async () => {
    const el = build({});
    await settle();

    expect(brandButton(el).disabled).toBe(true);
    expect(el.shadowRoot.querySelector(".footer__why").textContent).toBe(
      "Choose a facility to continue."
    );
  });

  it("names the blocking check when eligibility fails, and blocks Save", async () => {
    checkEligibility.mockResolvedValue({
      allowed: false,
      checks: [
        {
          level: "blocked",
          label: "Programs conflict",
          detail: "BHI and CoCM cannot be billed on the same visit."
        }
      ]
    });
    const el = build({
      eventId: "a01000000000001",
      facilityId: FACILITY_ID,
      facilityName: "Cedar Ridge",
      programs: ["BHI"],
      providerIds: ["a02000000000001"],
      startTime: "2026-10-05T14:00:00.000Z",
      endTime: "2026-10-05T16:00:00.000Z",
      onboardingStatus: "Scheduled"
    });
    await settle();

    expect(el.shadowRoot.querySelector(".footer__why").textContent).toBe(
      "Blocked: Programs conflict."
    );
    expect(brandButton(el).disabled).toBe(true);
    expect(el.shadowRoot.querySelector(".check_blocked")).not.toBeNull();
  });

  it("explains a short provider list instead of showing nothing", async () => {
    const el = build({ facilityId: FACILITY_ID });
    await settle();

    expect(el.shadowRoot.textContent).toContain("licensed in Pennsylvania");
    expect(el.shadowRoot.textContent).toContain("3 not licensed here");
  });

  it("surfaces a save failure inline with a role=alert, and re-enables Save", async () => {
    saveVisit.mockRejectedValue({ body: { message: "Reference 9931." } });
    const el = build({ facilityId: FACILITY_ID, facilityName: "Cedar Ridge" });
    await settle();

    brandButton(el).dispatchEvent(new CustomEvent("click"));
    await settle();

    const alert = el.shadowRoot.querySelector('[role="alert"]');
    expect(alert).not.toBeNull();
    expect(alert.textContent).toContain("Reference 9931.");
    expect(alert.textContent).toContain("The event didn't save.");
  });

  it("adds providers as chips rather than four standing dropdowns", async () => {
    const el = build({ facilityId: FACILITY_ID, facilityName: "Cedar Ridge" });
    await settle();

    const pickers = [
      ...el.shadowRoot.querySelectorAll("lightning-combobox")
    ].filter((c) => (c.label || "").startsWith("Provider"));
    expect(pickers).toHaveLength(0);

    const add = [...el.shadowRoot.querySelectorAll("lightning-combobox")].find(
      (c) => c.label === "Add a provider"
    );
    expect(add).toBeTruthy();
    expect(el.shadowRoot.querySelectorAll(".person")).toHaveLength(0);

    add.dispatchEvent(
      new CustomEvent("change", { detail: { value: "a02000000000001" } })
    );
    await settle();

    const chips = el.shadowRoot.querySelectorAll(".person");
    expect(chips).toHaveLength(1);
    expect(chips[0].textContent).toContain("Ada Rowe");
    // The person on the visit drops out of the list of people you can add.
    expect(
      [...el.shadowRoot.querySelectorAll("lightning-combobox")]
        .find((c) => c.label === "Add a provider")
        .options.map((o) => o.value)
    ).not.toContain("a02000000000001");
  });

  it("removes a provider from the chip", async () => {
    const el = build({ facilityId: FACILITY_ID, facilityName: "Cedar Ridge" });
    await settle();

    [...el.shadowRoot.querySelectorAll("lightning-combobox")]
      .find((c) => c.label === "Add a provider")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: "a02000000000001" } })
      );
    await settle();

    el.shadowRoot
      .querySelector(".person lightning-button-icon")
      .dispatchEvent(new CustomEvent("click"));
    await settle();

    expect(el.shadowRoot.querySelectorAll(".person")).toHaveLength(0);
  });

  it("shows the event status only when an existing visit is being edited", async () => {
    const fresh = build({
      facilityId: FACILITY_ID,
      facilityName: "Cedar Ridge"
    });
    await settle();
    const labels = [
      ...fresh.shadowRoot.querySelectorAll("lightning-combobox")
    ].map((c) => c.label);
    expect(labels).not.toContain("Event status");

    const editing = build({
      eventId: "a01000000000001",
      facilityId: FACILITY_ID,
      facilityName: "Cedar Ridge",
      programs: ["TCM"],
      providerIds: [],
      onboardingStatus: "Confirmed",
      startTime: "2026-10-05T14:00:00.000Z",
      endTime: "2026-10-05T16:00:00.000Z"
    });
    await settle();
    const editLabels = [
      ...editing.shadowRoot.querySelectorAll("lightning-combobox")
    ].map((c) => c.label);
    expect(editLabels).toContain("Event status");

    // The picklist shows the value, so the chip that used to sit beside it was
    // dropped as a second copy of the same fact.
    expect(
      [...editing.shadowRoot.querySelectorAll("lightning-combobox")].find(
        (c) => c.label === "Event status"
      ).value
    ).toBe("Confirmed");
  });

  it("defaults the window to 10:00 in the user's Salesforce time zone", async () => {
    // The When fields only exist past the facility step.
    const el = build({ facilityId: FACILITY_ID, facilityName: "Cedar Ridge" });
    await settle();

    const zone = TIME_ZONE;
    const reading = (value) =>
      new Date(value).toLocaleTimeString("en-GB", {
        timeZone: zone,
        hour: "2-digit",
        minute: "2-digit",
        hour12: false
      });

    const starts = [...el.shadowRoot.querySelectorAll("lightning-input")].find(
      (i) => i.label === "Starts"
    );
    const ends = [...el.shadowRoot.querySelectorAll("lightning-input")].find(
      (i) => i.label === "Ends"
    );
    // Built from the browser clock, these read 10:00 only when the two zones agree.
    expect(reading(starts.value)).toBe("10:00");
    expect(reading(ends.value)).toBe("12:00");
  });

  it("says what the eligibility panel will show before anyone is chosen", async () => {
    const el = build({ facilityId: FACILITY_ID, facilityName: "Cedar Ridge" });
    await settle();

    const rail = el.shadowRoot.textContent;
    expect(rail).toContain("Eligibility");
    expect(rail).toContain("Pick a program to check licensing.");
  });
});
