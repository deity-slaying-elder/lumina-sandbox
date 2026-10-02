import { api, track } from "lwc";
import LightningModal from "lightning/modal";
import TIME_ZONE from "@salesforce/i18n/timeZone";
import getFacilitators from "@salesforce/apex/FacilitySchedulingController.getFacilitators";
import getProviders from "@salesforce/apex/FacilitySchedulingController.getProviders";
import getFacilityPrograms from "@salesforce/apex/FacilitySchedulingController.getFacilityPrograms";
import getFacilitySnapshot from "@salesforce/apex/FacilitySchedulingController.getFacilitySnapshot";
import checkEligibility from "@salesforce/apex/FacilitySchedulingController.checkEligibility";
import searchFacilities from "@salesforce/apex/FacilitySchedulingController.searchFacilities";
import saveVisit from "@salesforce/apex/FacilitySchedulingController.saveVisit";
import updateVisit from "@salesforce/apex/FacilitySchedulingController.updateVisit";
import { EVENT_STATUSES, eventStatusTone } from "c/schedulingLabels";

const PROVIDER_SLOTS = 4;
const DEFAULT_START_HOUR = 10;
const DEFAULT_END_HOUR = 12;

/**
 * The instant whose clock reading in the user's Salesforce time zone is the given
 * hour on the given day.
 *
 * Building the default with setHours used the BROWSER zone, so anyone whose browser
 * and Salesforce zones differ opened the dialog on a time they did not choose.
 */
function atUserHour(day, hour, timeZone) {
  const naive = Date.UTC(
    day.getUTCFullYear(),
    day.getUTCMonth(),
    day.getUTCDate(),
    hour,
    0,
    0
  );
  // How far the zone sits from UTC at that moment, daylight saving included.
  const probe = new Date(naive);
  const inZone = new Date(probe.toLocaleString("en-US", { timeZone }));
  const inUtc = new Date(probe.toLocaleString("en-US", { timeZone: "UTC" }));
  return new Date(naive - (inZone.getTime() - inUtc.getTime()));
}
const SEARCH_DEBOUNCE_MS = 300;

const CHECK_ICON = {
  ok: "utility:success",
  warning: "utility:warning",
  blocked: "utility:error"
};

/**
 * The booking dialog, as a LightningModal subclass rather than a hand-built
 * section.slds-modal. That is what gives it the focus trap, Escape to close and focus
 * return to the trigger, none of which the previous hand-rolled markup had.
 */
export default class FacilitySchedulingBooking extends LightningModal {
  /** Existing visit to edit, or a facility row to book against. */
  @api context = {};

  @track modal = {};
  @track checks = [];
  @track facilityMatches = [];
  @track programChoices = [];
  @track snapshot;
  @track providerChoices;
  @track facilitatorChoices;

  facilitatorOptions = [];
  providerOptions = [];
  facilitySearchTerm = "";
  facilitySearching = false;
  facilitySearchTimer;

  saving = false;
  loadingPickers = false;
  modalError;

  // ------------------------------------------------------------ lifecycle
  connectedCallback() {
    const c = this.context || {};
    if (c.eventId) {
      this.modal = {
        eventId: c.eventId,
        facilityId: c.facilityId,
        facilityName: c.facilityName,
        programs: [...(c.programs || [])],
        facilitatorId: c.facilitatorId || "",
        providerIds: this.padSlots(c.providerIds),
        onboardingStatus: c.onboardingStatus || "Scheduled",
        startTime: c.startTime,
        endTime: c.endTime
      };
    } else {
      const tomorrow = new Date();
      tomorrow.setDate(tomorrow.getDate() + 1);
      const start = atUserHour(tomorrow, DEFAULT_START_HOUR, TIME_ZONE);
      const end = atUserHour(tomorrow, DEFAULT_END_HOUR, TIME_ZONE);
      this.modal = {
        eventId: undefined,
        onboardingStatus: "Scheduled",
        facilityId: c.facilityId,
        facilityName: c.facilityName,
        programs: [],
        facilitatorId: "",
        providerIds: this.padSlots([]),
        startTime: start.toISOString(),
        endTime: end.toISOString()
      };
    }
    this.initialise();
  }

  async initialise() {
    this.loadingPickers = true;
    try {
      await Promise.all([
        this.loadFacilityContext(),
        this.loadFacilitators(),
        this.loadProviders()
      ]);
      if (this.modal.eventId) {
        await this.runChecks();
      }
    } catch (e) {
      this.modalError = this.messageOf(e);
    } finally {
      this.loadingPickers = false;
    }
  }

  disconnectedCallback() {
    window.clearTimeout(this.facilitySearchTimer);
  }

  // ------------------------------------------------------------ labels
  get heading() {
    return this.modal.eventId
      ? "Edit facility onboarding"
      : "Schedule facility onboarding";
  }

  get saveLabel() {
    return this.modal.eventId ? "Save changes" : "Schedule event";
  }

  get isEditing() {
    return !!this.modal.eventId;
  }

  get statusPickerOptions() {
    return EVENT_STATUSES.map((s) => ({ label: s, value: s }));
  }

  get statusTone() {
    return eventStatusTone(this.modal.onboardingStatus);
  }

  // ------------------------------------------------------------ programs
  /**
   * Every programme is rendered, including the ones this facility does not run.
   * Those come back disabled with the reason beside them rather than being dropped
   * from the list, so a coordinator can see that a programme exists and is off here.
   */
  get programItems() {
    const chosen = new Set(this.modal.programs || []);
    const noFacility = !this.modal.facilityId;
    return (this.programChoices || []).map((p) => ({
      key: p.value,
      value: p.value,
      label: p.label,
      checked: chosen.has(p.value),
      disabled: !p.available,
      // With no facility chosen every row carries the same sentence, so it is said
      // once in the summary instead of eight times down the list.
      reason: noFacility ? null : p.reason,
      hasReason: !noFacility && !!p.reason
    }));
  }

  get selectedPrograms() {
    return this.modal.programs || [];
  }

  get programSummary() {
    const n = this.selectedPrograms.length;
    if (!this.modal.facilityId) {
      return "Choose a facility to see which programs it runs.";
    }
    if (!n) {
      return "No program selected. Provider licensing cannot be checked until you pick one.";
    }
    return `${n} program${n === 1 ? "" : "s"} on this visit: ${this.selectedPrograms.join(
      ", "
    )}.`;
  }

  handleProgramToggle(e) {
    const value = e.currentTarget.dataset.program;
    const on = e.target.checked;
    const held = new Set(this.modal.programs || []);
    if (on) {
      held.add(value);
    } else {
      held.delete(value);
    }
    // Keep the choice list's own order, so the summary reads the same every time.
    const ordered = (this.programChoices || [])
      .map((p) => p.value)
      .filter((v) => held.has(v));
    this.modal = { ...this.modal, programs: ordered };
    this.refreshForPrograms();
  }

  async refreshForPrograms() {
    this.loadingPickers = true;
    try {
      await this.loadProviders();
      await this.runChecks();
    } catch (e) {
      this.modalError = this.messageOf(e);
    } finally {
      this.loadingPickers = false;
    }
  }

  // ------------------------------------------------------------ facility counts
  get hasSnapshot() {
    return !!this.snapshot;
  }

  get counts() {
    const s = this.snapshot;
    if (!s) {
      return [];
    }
    return [
      { key: "census", label: "Census", value: s.census },
      { key: "seen", label: "Seen", value: s.seen },
      { key: "consented", label: "Consented", value: s.consented }
    ];
  }

  get snapshotCaption() {
    const s = this.snapshot;
    if (!s) {
      return "";
    }
    const where = s.stateCode ? ` in ${s.stateCode}` : "";
    return `Active patients at this facility${where}, as of now.`;
  }

  // ------------------------------------------------------------ state
  get busy() {
    return this.saving || this.loadingPickers;
  }

  get saveDisabled() {
    return (
      this.saving ||
      !this.modal.facilityId ||
      !this.modal.startTime ||
      !this.modal.endTime ||
      this.blockedChecks.length > 0
    );
  }

  get blockedChecks() {
    return this.checks.filter((c) => c.level === "blocked");
  }

  /**
   * Named, so the disabled Save button says why it is disabled, which is the one
   * thing a disabled control always has to do.
   */
  get saveBlockedReason() {
    if (this.saving) {
      return "Saving.";
    }
    if (!this.modal.facilityId) {
      return "Choose a facility to continue.";
    }
    if (!this.modal.startTime || !this.modal.endTime) {
      return "Set a start and end time to continue.";
    }
    const blocked = this.blockedChecks;
    if (blocked.length === 1) {
      return `Blocked: ${blocked[0].label}.`;
    }
    if (blocked.length > 1) {
      return `Blocked by ${blocked.length} eligibility errors.`;
    }
    return "Ready to save.";
  }

  get hasChecks() {
    return this.checks.length > 0;
  }

  /**
   * The rail always carries an eligibility block, so it is not an empty panel until
   * a provider happens to be chosen. Before then it says what will appear there.
   */
  get eligibilityHint() {
    if (!this.selectedPrograms.length) {
      return "Pick a program to check licensing.";
    }
    if (!this.selectedProviderIds.length && !this.modal.facilitatorId) {
      return "Add a provider to run the licensing and conflict checks.";
    }
    return "Checking.";
  }

  get checkSummary() {
    const blocked = this.blockedChecks.length;
    const warnings = this.checks.filter((c) => c.level === "warning").length;
    if (blocked) {
      return {
        tone: "error",
        label: `${blocked} blocking ${blocked === 1 ? "issue" : "issues"}`
      };
    }
    if (warnings) {
      return {
        tone: "warning",
        label: `${warnings} ${warnings === 1 ? "warning" : "warnings"}`
      };
    }
    return { tone: "success", label: "All checks pass" };
  }

  // ------------------------------------------------------------ facility
  get hasFacilityMatches() {
    return this.facilityMatches.length > 0;
  }

  get facilitySearchHint() {
    if (this.facilitySearching) {
      return "Searching.";
    }
    if (this.facilitySearchTerm.trim().length < 2) {
      return "Type at least two characters. Only facilities awaiting onboarding are searched.";
    }
    return this.facilityMatches.length
      ? `${this.facilityMatches.length} match${
          this.facilityMatches.length === 1 ? "" : "es"
        }.`
      : "No matching facility is awaiting onboarding.";
  }

  handleFacilitySearch(e) {
    this.facilitySearchTerm = e.target.value || "";
    window.clearTimeout(this.facilitySearchTimer);
    const term = this.facilitySearchTerm;
    if (term.trim().length < 2) {
      this.facilityMatches = [];
      this.facilitySearching = false;
      return;
    }
    this.facilitySearching = true;
    // Debouncing needs a real timer. The rule exists to stop components polling or
    // scheduling work the framework cannot see; this one clears itself in
    // disconnectedCallback and drops results that arrive after the term changed.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.facilitySearchTimer = window.setTimeout(async () => {
      try {
        const found = await searchFacilities({ term });
        // Ignore a result that arrived after the user typed something else.
        if (term === this.facilitySearchTerm) {
          this.facilityMatches = found;
        }
      } catch (err) {
        this.modalError = this.messageOf(err);
        this.facilityMatches = [];
      } finally {
        this.facilitySearching = false;
      }
    }, SEARCH_DEBOUNCE_MS);
  }

  /**
   * Changing the facility changes which programmes are on offer and which providers
   * are licensed, so the programme list, the provider picker and the checks are all
   * rebuilt, and a programme the new facility does not run is dropped.
   */
  async handleFacilityPick(e) {
    const id = e.currentTarget.dataset.id;
    const hit = this.facilityMatches.find((o) => o.value === id);
    this.modal = {
      ...this.modal,
      facilityId: id,
      facilityName: hit ? hit.label : ""
    };
    this.facilityMatches = [];
    this.facilitySearchTerm = "";
    this.loadingPickers = true;
    try {
      await this.loadFacilityContext();
      await this.loadProviders();
      await this.runChecks();
    } catch (err) {
      this.modalError = this.messageOf(err);
    } finally {
      this.loadingPickers = false;
    }
  }

  handleClearFacility() {
    this.modal = {
      ...this.modal,
      facilityId: "",
      facilityName: "",
      programs: []
    };
    this.facilityMatches = [];
    this.facilitySearchTerm = "";
    this.snapshot = undefined;
    this.checks = [];
    this.loadFacilityContext();
  }

  /**
   * The programme list and the patient counts both hang off the chosen facility, so
   * they are loaded together and a programme the facility does not run is dropped
   * from the selection rather than left silently checked.
   */
  async loadFacilityContext() {
    const facilityId = this.modal.facilityId || null;
    const [choices, snap] = await Promise.all([
      getFacilityPrograms({ facilityId }),
      facilityId ? getFacilitySnapshot({ facilityId }) : Promise.resolve(null)
    ]);
    this.programChoices = choices || [];
    this.snapshot = snap || undefined;

    const offered = new Set(
      this.programChoices.filter((p) => p.available).map((p) => p.value)
    );
    const kept = (this.modal.programs || []).filter((p) => offered.has(p));
    if (kept.length !== (this.modal.programs || []).length) {
      this.modal = { ...this.modal, programs: kept };
    }
  }

  // ------------------------------------------------------------ pickers
  get providerHelp() {
    if (!this.modal.facilityId) {
      return "Choose a facility to see who is licensed to work there.";
    }
    const c = this.providerChoices;
    if (!c) {
      return "Choose a program to narrow the provider list.";
    }
    const where = c.stateName ? ` licensed in ${c.stateName}` : "";
    const what = this.selectedPrograms.length
      ? ` and approved for ${this.selectedPrograms.join(" and ")}`
      : "";
    const parts = [];
    if (c.hiddenUnlicensed) {
      parts.push(`${c.hiddenUnlicensed} not licensed here`);
    }
    if (c.hiddenUntagged) {
      parts.push(`${c.hiddenUntagged} not approved for every program`);
    }
    if (c.hiddenConflicted) {
      parts.push(`${c.hiddenConflicted} program conflict`);
    }
    if (c.hiddenBooked) {
      parts.push(`${c.hiddenBooked} already booked`);
    }
    const hidden =
      (c.hiddenUnlicensed || 0) +
      (c.hiddenUntagged || 0) +
      (c.hiddenConflicted || 0) +
      (c.hiddenBooked || 0);
    const tail = hidden ? ` ${hidden} hidden: ${parts.join(", ")}.` : "";
    const used = `${this.selectedProviderIds.length} of ${PROVIDER_SLOTS} slots used.`;
    return `${used} Showing providers${where}${what}.${tail}`;
  }

  get facilitatorHelp() {
    const c = this.facilitatorChoices;
    if (!c) {
      return "Active facilitators only.";
    }
    return c.hiddenBooked
      ? `Free in this window. ${c.hiddenBooked} hidden because they are already booked.`
      : "Free in this window.";
  }

  get noFreeFacilitators() {
    return (
      !!this.facilitatorChoices &&
      this.facilitatorOptions.length === 0 &&
      !!this.modal.startTime
    );
  }

  get noEligibleProviders() {
    return (
      !!this.providerChoices &&
      this.providerOptions.length === 0 &&
      !!this.modal.facilityId
    );
  }

  /**
   * The four provider slots, so the template renders one picker each. Larger
   * facilities run several providers per visit.
   */
  /** The providers already on the visit, as removable chips. */
  get chosenProviders() {
    const byId = new Map(this.providerOptions.map((o) => [o.value, o.label]));
    return this.selectedProviderIds.map((id) => ({
      value: id,
      label: byId.get(id) || "Selected provider",
      removeLabel: `Remove ${byId.get(id) || "this provider"}`
    }));
  }

  get needsFacility() {
    return !this.modal.facilityId;
  }

  get hasProviders() {
    return this.selectedProviderIds.length > 0;
  }

  get providerSlotsFull() {
    return this.selectedProviderIds.length >= PROVIDER_SLOTS;
  }

  get addProviderPlaceholder() {
    return this.providerSlotsFull
      ? `All ${PROVIDER_SLOTS} slots used`
      : "Select a provider";
  }

  /** Anyone eligible who is not already on the visit. */
  get addableProviders() {
    const taken = new Set(this.selectedProviderIds);
    return this.providerOptions.filter((o) => !taken.has(o.value));
  }

  handleAddProvider(e) {
    const id = e.detail.value;
    if (!id || this.providerSlotsFull) {
      return;
    }
    this.modal = {
      ...this.modal,
      providerIds: this.padSlots([...this.selectedProviderIds, id])
    };
    this.runChecks();
  }

  handleRemoveProvider(e) {
    const id = e.currentTarget.dataset.id;
    this.modal = {
      ...this.modal,
      providerIds: this.padSlots(
        this.selectedProviderIds.filter((v) => v !== id)
      )
    };
    this.runChecks();
  }

  /**
   * The search result label carries the state ("Cedar Ridge SNF - PA") because that
   * is what disambiguates two facilities with the same name. The rail states the
   * state on its own line, so it uses the record name and drops the suffix.
   */
  get railFacilityName() {
    const snap = this.snapshot;
    return (snap && snap.name) || this.modal.facilityName;
  }

  /** The line under the facility name in the rail. */
  get facilityContext() {
    const s = this.snapshot;
    const bits = [];
    if (s && s.parentCompany) {
      bits.push(s.parentCompany);
    }
    if (s && s.stateCode) {
      bits.push(s.stateCode);
    }
    if (s && s.rolloutDate) {
      bits.push(
        `rollout ${new Date(s.rolloutDate).toLocaleDateString(undefined, {
          day: "numeric",
          month: "short",
          year: "numeric"
        })}`
      );
    }
    return bits.length
      ? bits.join(" \u00b7 ")
      : "No parent company or state on record";
  }

  get providerSlots() {
    const ids = this.modal.providerIds || [];
    return Array.from({ length: PROVIDER_SLOTS }, (unused, i) => ({
      key: `provider-${i}`,
      index: String(i),
      label: i === 0 ? "Provider 1" : `Provider ${i + 1} (optional)`,
      value: ids[i] || "",
      options: this.slotOptions(i)
    }));
  }

  /**
   * A provider already chosen in another slot is dropped from this one's list, so
   * the same person cannot be picked twice. The server rejects it either way.
   */
  slotOptions(index) {
    const ids = this.modal.providerIds || [];
    const taken = ids.filter((v, i) => v && i !== index);
    return this.providerOptions.filter((o) => !taken.includes(o.value));
  }

  get selectedProviderIds() {
    return (this.modal.providerIds || []).filter((v) => v);
  }

  async loadPickers() {
    this.loadingPickers = true;
    try {
      await Promise.all([this.loadFacilitators(), this.loadProviders()]);
    } finally {
      this.loadingPickers = false;
    }
  }

  async loadFacilitators() {
    const result = await getFacilitators({
      startTime: this.modal.startTime || null,
      endTime: this.modal.endTime || null,
      excludeVisitId: this.modal.eventId || null
    });
    this.facilitatorChoices = result;
    this.facilitatorOptions = (result.options || []).map((o) => ({
      label: o.label,
      value: o.value
    }));
    // Someone who has become unavailable must not stay selected.
    if (
      !this.facilitatorOptions.some((o) => o.value === this.modal.facilitatorId)
    ) {
      this.modal = { ...this.modal, facilitatorId: "" };
    }
  }

  async loadProviders() {
    const result = await getProviders({
      programs: this.selectedPrograms,
      facilityId: this.modal.facilityId || null,
      startTime: this.modal.startTime || null,
      endTime: this.modal.endTime || null,
      excludeVisitId: this.modal.eventId || null
    });
    this.providerOptions = (result.options || []).map((o) => ({
      label: o.label,
      value: o.value
    }));
    this.providerChoices = result;
    // Any slot holding a provider no longer offered is cleared.
    const offered = new Set(this.providerOptions.map((o) => o.value));
    const ids = this.modal.providerIds || [];
    const kept = ids.map((v) => (v && offered.has(v) ? v : ""));
    if (kept.some((v, i) => v !== ids[i])) {
      this.modal = { ...this.modal, providerIds: kept };
      this.checks = [];
    }
  }

  padSlots(ids) {
    const out = (ids || []).slice(0, PROVIDER_SLOTS).map((v) => v || "");
    while (out.length < PROVIDER_SLOTS) {
      out.push("");
    }
    return out;
  }

  // ------------------------------------------------------------ field changes
  handleEventStatusChange(e) {
    this.modal = { ...this.modal, onboardingStatus: e.detail.value };
  }

  handleFacilitatorChange(e) {
    this.modal = { ...this.modal, facilitatorId: e.detail.value };
    this.runChecks();
  }

  handleProviderChange(e) {
    const i = Number(e.currentTarget.dataset.index);
    const ids = [...(this.modal.providerIds || [])];
    ids[i] = e.detail.value || "";
    this.modal = { ...this.modal, providerIds: ids };
    this.runChecks();
  }

  async handleStartChange(e) {
    this.modal = { ...this.modal, startTime: e.detail.value };
    await this.loadPickers();
    this.runChecks();
  }

  async handleEndChange(e) {
    this.modal = { ...this.modal, endTime: e.detail.value };
    await this.loadPickers();
    this.runChecks();
  }

  // ------------------------------------------------------------ eligibility
  /**
   * Advisory only. The same checks run again server-side in saveVisit, so a user
   * cannot get past them by manipulating the page.
   */
  async runChecks() {
    if (
      !this.modal.facilityId ||
      (!this.selectedProviderIds.length && !this.modal.facilitatorId)
    ) {
      this.checks = [];
      return;
    }
    try {
      const result = await checkEligibility({
        providerIds: this.selectedProviderIds,
        facilitatorId: this.modal.facilitatorId || null,
        facilityId: this.modal.facilityId || null,
        programs: this.selectedPrograms,
        startTime: this.modal.startTime || null,
        endTime: this.modal.endTime || null,
        excludeVisitId: this.modal.eventId || null
      });
      this.checks = (result.checks || []).map((c, i) => ({
        ...c,
        key: `${c.level}-${i}-${c.label}`,
        css: `check check_${c.level}`,
        icon: CHECK_ICON[c.level] || CHECK_ICON.warning
      }));
    } catch (e) {
      this.modalError = this.messageOf(e);
      this.checks = [];
    }
  }

  // ------------------------------------------------------------ save
  handleCancel() {
    this.close(null);
  }

  async handleSave() {
    this.modalError = undefined;
    this.saving = true;
    try {
      let savedId;
      if (this.modal.eventId) {
        savedId = await updateVisit({
          visitId: this.modal.eventId,
          facilitatorId: this.modal.facilitatorId || null,
          providerIds: this.selectedProviderIds,
          programs: this.selectedPrograms,
          startTime: this.modal.startTime,
          endTime: this.modal.endTime,
          onboardingStatus: this.modal.onboardingStatus || "Scheduled"
        });
      } else {
        savedId = await saveVisit({
          facilityId: this.modal.facilityId || null,
          facilitatorId: this.modal.facilitatorId || null,
          providerIds: this.selectedProviderIds,
          programs: this.selectedPrograms,
          startTime: this.modal.startTime,
          endTime: this.modal.endTime
        });
      }
      this.close({
        savedId,
        facilityName: this.modal.facilityName,
        edited: !!this.modal.eventId
      });
    } catch (e) {
      this.modalError = this.messageOf(e);
    } finally {
      this.saving = false;
    }
  }

  /**
   * Apex detail never reaches the screen as-is. The controller already returns a
   * user-safe message plus a reference, so this only guards the cases where the
   * platform, not the controller, produced the failure.
   */
  messageOf(e) {
    return e?.body?.message || e?.message || "Something went wrong. Try again.";
  }
}
