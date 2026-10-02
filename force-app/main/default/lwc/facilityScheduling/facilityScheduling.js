import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getWorklist from "@salesforce/apex/FacilitySchedulingController.getWorklist";
import getEvents from "@salesforce/apex/FacilitySchedulingController.getEvents";
import getSummary from "@salesforce/apex/FacilitySchedulingController.getSummary";
import FacilitySchedulingBooking from "c/facilitySchedulingBooking";
import {
  PROGRAMS,
  programClass,
  programShortLabel,
  facilityStatusTone,
  eventStatusTone,
  coverageFor,
  eventChipClass
} from "c/schedulingLabels";

const DAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const SKELETON_ROWS = 6;
const SEARCH_DEBOUNCE_MS = 300;
const ROW_CAP = 200;

/**
 * Parent company rides inside the Facility cell rather than taking a column of its
 * own, which was blank on most rows and twelve rem wide. Numeric columns use the
 * number type so each header ranges right with its own figures.
 */

export default class FacilityScheduling extends LightningElement {
  view = "list";
  loading = false;
  firstLoadDone = false;
  error;

  rangePreset = "next30";
  fromDate;
  toDate;
  program = "";
  searchTerm = "";
  unscheduledOnly = false;
  // Set when you jump to the calendar from a row, so the month shows that facility
  // on its own instead of everything.
  focusFacilityId;
  focusFacilityName;
  searchTimer;

  bookingOpen = false;

  sortKey = "rolloutDate";

  @track summary;
  summaryError;
  @track allRows = [];
  // month | week | day. Month is where the calendar opens: a single week of a
  // rollout plan says almost nothing on its own.
  calMode = "month";
  anchor = new Date();
  @track grid = [];
  @track dayEvents = [];

  connectedCallback() {
    this.applyPreset();
    this.loadWorklist();
    this.loadSummary();
    // The card sizes itself to whatever is left below the Salesforce chrome, so the
    // page itself never scrolls and only the rows or the grid do.
    this.boundFit = () => this.fitToViewport();
    window.addEventListener("resize", this.boundFit);
  }

  renderedCallback() {
    this.fitToViewport();
  }

  /**
   * Height is measured rather than guessed with a vh calc, because the chrome above
   * the component differs between a console app, a standard app and a record page.
   *
   * It measures against the nearest scrolling ancestor, not the window. A console
   * app puts the page inside its own scroll container, so sizing to the viewport
   * left the card taller than that container and the console scrolled behind it.
   */
  fitToViewport() {
    const card = this.template.querySelector(".card");
    if (!card) {
      return;
    }
    const top = card.getBoundingClientRect().top;
    let bottom = window.innerHeight;
    let node = this.template.host ? this.template.host.parentNode : null;
    for (let i = 0; i < 20 && node; i++) {
      if (node.nodeType === 1) {
        const cs = window.getComputedStyle(node);
        if (/auto|scroll/.test(cs.overflowY)) {
          bottom = Math.min(bottom, node.getBoundingClientRect().bottom);
          break;
        }
      }
      node = node.parentNode || node.host;
    }
    const available = Math.max(320, bottom - top - 12);
    const next = `${Math.round(available)}px`;
    if (card.style.height !== next) {
      card.style.height = next;
    }
  }

  disconnectedCallback() {
    window.clearTimeout(this.searchTimer);
    if (this.boundFit) {
      window.removeEventListener("resize", this.boundFit);
    }
  }

  // ------------------------------------------------------------ chrome
  get cardTitle() {
    return this.isCalendar ? this.spanLabel : "Onboarding worklist";
  }

  get isList() {
    return this.view === "list";
  }

  get isCalendar() {
    return this.view === "calendar";
  }

  get listVariant() {
    return this.isList ? "brand-outline" : "neutral";
  }

  get calendarVariant() {
    return this.isCalendar ? "brand-outline" : "neutral";
  }

  get showList() {
    return this.isList && !this.error;
  }

  get showCalendar() {
    return this.isCalendar && !this.error;
  }

  get showSkeleton() {
    return this.loading && !this.firstLoadDone;
  }

  get skeletonRows() {
    return Array.from({ length: SKELETON_ROWS }, (unused, i) => ({
      key: `sk-${i}`
    }));
  }

  // ------------------------------------------------------------ summary strip
  async loadSummary() {
    try {
      this.summary = await getSummary();
    } catch (e) {
      // The strip is a convenience. A failure here must not take the list with it,
      // so the error is swallowed and the tiles simply read zero.
      this.summary = undefined;
      this.summaryError = this.messageOf(e);
    }
  }

  get stats() {
    const s = this.summary || {};
    const awaiting = s.awaiting || 0;
    const unscheduled = s.unscheduled || 0;
    const booked = s.bookedThisWeek || 0;
    const pct = (n) => (awaiting ? Math.round((n / awaiting) * 100) : 0);
    return [
      {
        key: "all",
        label: "Awaiting onboarding",
        value: awaiting,
        sub: awaiting === 1 ? "facility" : "facilities",
        pressed: String(this.isList && !this.unscheduledOnly),
        inert: false,
        numberClass: "stat__n",
        barClass: "stat__bar",
        barStyle: "width:100%"
      },
      {
        key: "unscheduled",
        label: "No event booked",
        value: unscheduled,
        sub: "need scheduling",
        pressed: String(this.isList && this.unscheduledOnly),
        inert: unscheduled === 0,
        numberClass: unscheduled ? "stat__n stat__n_warn" : "stat__n",
        barClass: "stat__bar stat__bar_warn",
        barStyle: `width:${pct(unscheduled)}%`
      },
      {
        key: "week",
        label: "Booked this week",
        value: booked,
        sub: booked === 1 ? "visit" : "visits",
        pressed: String(this.isCalendar),
        inert: false,
        numberClass: "stat__n",
        barClass: "stat__bar",
        barStyle: `width:${pct(booked)}%`
      },
      {
        key: "next",
        label: "Next rollout",
        value: s.nextRolloutDate ? this.dayOnly(s.nextRolloutDate) : "\u2014",
        sub: s.nextRolloutFacility || "nothing scheduled",
        pressed: "false",
        inert: false,
        numberClass: "stat__n",
        barClass: "stat__bar",
        barStyle: "width:0%"
      }
    ];
  }

  /**
   * Every tile does the same kind of thing: take you to what its number is about.
   *
   * Before, the two list tiles only set a list filter, so once you were on the
   * calendar they did nothing at all and the strip was a dead end.
   */
  handleStatClick(e) {
    const key = e.currentTarget.dataset.stat;
    if (key === "week") {
      this.view = "calendar";
      this.calMode = "week";
      this.anchor = new Date();
      this.firstLoadDone = false;
      this.loadCalendar();
      return;
    }

    this.unscheduledOnly = key === "unscheduled";
    if (key === "next") {
      // The soonest rollout is a list question, so sort the list by it.
      this.sortKey = "rolloutDate";
    }
    if (this.isCalendar) {
      this.view = "list";
      this.firstLoadDone = false;
      this.loadWorklist();
    }
  }

  dayOnly(value) {
    return new Date(value).toLocaleDateString(undefined, {
      day: "numeric",
      month: "short"
    });
  }

  get cardSubtitle() {
    return this.isCalendar
      ? "Choose an event to edit it, or use the plus on a day"
      : "Facilities with status Onboarding or Opportunity";
  }

  // ------------------------------------------------------------ rows
  get rows() {
    const rows = this.unscheduledOnly
      ? this.allRows.filter((r) => !r.eventCount)
      : this.allRows;
    return this.sortRows(rows);
  }

  get hasRows() {
    return !this.showSkeleton && this.rows.length > 0;
  }

  get unscheduledCount() {
    return this.allRows.filter((r) => !r.eventCount).length;
  }

  get hasUnscheduled() {
    return this.unscheduledCount > 0;
  }

  get unscheduledLabel() {
    return `${this.unscheduledCount} need scheduling`;
  }

  get unscheduledOnlyString() {
    return String(this.unscheduledOnly);
  }

  get countLabel() {
    if (this.loading && !this.firstLoadDone) {
      return "Loading facilities";
    }
    if (this.isCalendar) {
      const n = this.visibleEvents.length;
      return `${n} event${n === 1 ? "" : "s"} this ${this.calMode}`;
    }
    const n = this.allRows.length;
    return `${n} ${n === 1 ? "facility" : "facilities"} ${this.rangeLabel}`;
  }

  get rangeLabel() {
    const chosen = this.rangeOptions.find((o) => o.value === this.rangePreset);
    return chosen && this.rangePreset !== "all"
      ? `in the ${chosen.label.toLowerCase()}`
      : "across all dates";
  }

  get capLabel() {
    const n = this.allRows.length;
    return n >= ROW_CAP
      ? `Showing the first ${ROW_CAP} facilities. Narrow the dates or search to see the rest.`
      : `Showing all ${n} ${n === 1 ? "facility" : "facilities"}.`;
  }

  // ------------------------------------------------------------ sorting
  /**
   * Custom rows mean no column headers to click, so sorting is an explicit control.
   * Three orders cover the job: when it goes live, how big it is, and alphabetical.
   */
  get sortOptions() {
    return [
      { label: "Rollout date", value: "rolloutDate" },
      { label: "Facility name", value: "name" },
      { label: "Census, largest first", value: "census" }
    ];
  }

  handleSortChange(e) {
    this.sortKey = e.detail.value;
  }

  sortRows(rows) {
    const key = this.sortKey;
    const dir = key === "census" ? -1 : 1;
    return [...rows].sort((a, b) => {
      const x = a[key];
      const y = b[key];
      if (x === y) {
        return 0;
      }
      // Blanks sort last whichever direction is chosen, so an empty rollout never
      // floats to the top of a date sort.
      if (x === null || x === undefined || x === "") {
        return 1;
      }
      if (y === null || y === undefined || y === "") {
        return -1;
      }
      return x > y ? dir : -dir;
    });
  }

  // ------------------------------------------------------------ filters
  get rangeOptions() {
    return [
      { label: "Next 30 days", value: "next30" },
      { label: "This month", value: "thisMonth" },
      { label: "Last month", value: "lastMonth" },
      { label: "Last 3 months", value: "last3" },
      { label: "Last 6 months", value: "last6" },
      { label: "This year", value: "thisYear" },
      { label: "Last year", value: "lastYear" },
      { label: "All dates", value: "all" },
      { label: "Custom range", value: "custom" }
    ];
  }

  get programFilterOptions() {
    return [{ label: "All programs", value: "" }].concat(
      PROGRAMS.map((p) => ({ label: p, value: p }))
    );
  }

  get showCustomDates() {
    return this.isList && this.rangePreset === "custom";
  }

  /**
   * The date range and the sort order narrow a list of facilities, and the calendar
   * is driven by its own navigation, so those two are list-only. Search and Program
   * narrow both, so they show on both.
   */
  get showListFilters() {
    return this.isList;
  }

  get searchLabel() {
    return this.isCalendar ? "Search by facility" : "Search facilities";
  }

  /**
   * Only filters without a visible control of their own. The date range and program
   * dropdowns are on screen, so echoing them back as pills would say the same thing
   * twice.
   */
  get removableFilters() {
    const pills = [];
    if (this.searchTerm) {
      pills.push({ name: "search", label: `Search: ${this.searchTerm}` });
    }
    if (this.unscheduledOnly) {
      pills.push({
        name: "unscheduled",
        label: "Only facilities with no event"
      });
    }
    return pills;
  }

  get hasPills() {
    return this.removableFilters.length > 0;
  }

  get hasRemovableFilters() {
    return this.removableFilters.length > 0 || this.isNonDefault;
  }

  /** Clear filters appears only when something differs from how the page opens. */
  get isNonDefault() {
    return (
      this.rangePreset !== "next30" ||
      !!this.program ||
      !!this.searchTerm ||
      this.unscheduledOnly ||
      !!this.focusFacilityId
    );
  }

  handleRemoveFilter(e) {
    const name = e.detail.item ? e.detail.item.name : e.detail.name;
    if (name === "search") {
      this.searchTerm = "";
      this.loadWorklist();
    } else if (name === "unscheduled") {
      this.unscheduledOnly = false;
    }
  }

  handleSearch(e) {
    const value = e.detail.value || "";
    window.clearTimeout(this.searchTimer);
    // Debounced so a fast typist does not fire a query per keystroke.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = window.setTimeout(() => {
      this.searchTerm = value;
      this.reload();
    }, SEARCH_DEBOUNCE_MS);
  }

  handleToggleUnscheduled() {
    this.unscheduledOnly = !this.unscheduledOnly;
  }

  handleRangeChange(e) {
    this.rangePreset = e.detail.value;
    if (this.rangePreset === "all") {
      this.fromDate = undefined;
      this.toDate = undefined;
    } else {
      this.applyPreset();
    }
    this.reload();
  }

  handleFromChange(e) {
    this.fromDate = e.detail.value;
    this.reload();
  }

  handleToChange(e) {
    this.toDate = e.detail.value;
    this.reload();
  }

  handleProgramFilterChange(e) {
    this.program = e.detail.value;
    this.reload();
  }

  handleClear() {
    this.rangePreset = "next30";
    this.program = "";
    this.searchTerm = "";
    this.unscheduledOnly = false;
    this.focusFacilityId = undefined;
    this.focusFacilityName = undefined;
    this.applyPreset();
    this.reload();
  }

  handleRefresh() {
    this.reload();
    this.loadSummary();
  }

  handleViewChange(e) {
    const next = e.currentTarget.dataset.view;
    if (next === this.view) {
      return;
    }
    this.view = next;
    this.firstLoadDone = false;
    this.reload();
  }

  reload() {
    if (this.isCalendar) {
      this.loadCalendar();
    } else {
      this.loadWorklist();
    }
  }

  // ------------------------------------------------------------ empty
  get showEmpty() {
    return !this.loading && !this.error && this.rows.length === 0;
  }

  get emptyVariant() {
    return this.isNonDefault ? "filtered" : "first-use";
  }

  get emptyHeading() {
    return this.isNonDefault
      ? "No facilities match these filters"
      : "Nothing is waiting to be scheduled";
  }

  get emptyBody() {
    if (!this.isNonDefault) {
      return "Facilities appear here while their status is Onboarding or Opportunity. They leave once they are Active with Seen populated and facilitation is confirmed complete.";
    }
    const bits = [];
    if (this.searchTerm) {
      bits.push(`"${this.searchTerm}"`);
    }
    if (this.program) {
      bits.push(this.program);
    }
    const what = bits.length ? bits.join(" and ") : "these filters";
    return `Nothing matches ${what}. Widen the dates, or clear the filters.`;
  }

  get emptyCta() {
    return this.isNonDefault ? "Clear filters" : undefined;
  }

  handleEmptyCta() {
    if (this.isNonDefault) {
      this.handleClear();
    } else {
      this.handleNewEvent();
    }
  }

  handleRetry() {
    this.reload();
  }

  // ------------------------------------------------------------ data
  async loadWorklist() {
    this.loading = true;
    this.error = undefined;
    try {
      const found = await getWorklist({
        parentCompanyId: null,
        fromDate: this.fromDate || null,
        toDate: this.toDate || null,
        program: this.program || null,
        searchTerm: this.searchTerm || null
      });
      this.allRows = (found || []).map((r) => this.decorateRow(r));
    } catch (e) {
      this.error = this.messageOf(e);
      this.allRows = [];
    } finally {
      this.loading = false;
      this.firstLoadDone = true;
    }
  }

  decorateRow(r) {
    const coverage = coverageFor(r.eventCount);
    const census = r.census || 0;
    const pct = (n) => (census ? Math.round((n / census) * 100) : 0);
    return {
      ...r,
      facilityUrl: `/lightning/r/Facility__c/${r.facilityId}/view`,
      parentCompanyLabel: r.parentCompany || "No parent company",
      stateLabel: r.stateCode || "No state on address",
      statusTone: facilityStatusTone(r.status),
      coverageLabel: coverage.label,
      coverageTone: coverage.tone,
      coverageIcon: coverage.iconName,
      menuLabel: `Actions for ${r.name}`,
      rolloutLabel: r.rolloutDate ? this.dayOnly(r.rolloutDate) : "Not set",
      // A bar reads as "nothing loaded yet" where three zeroes read as broken.
      hasPatients: census > 0,
      seenStyle: `width:${pct(r.seen || 0)}%`,
      consentStyle: `width:${pct(r.consented || 0)}%`,
      progressLabel: `${r.seen || 0} of ${census} seen, ${r.consented || 0} consented`,
      nextLabel: this.nextLabelFor(r),
      hasEvents: (r.eventCount || 0) > 0,
      showOnCalendarLabel: `Show ${r.name} on the calendar`
    };
  }

  /**
   * Either when the next visit is, or how long is left before the rollout, which is
   * the thing you want to know when nothing is booked.
   */
  nextLabelFor(r) {
    if (r.nextEventStart) {
      return `next ${this.shortDate(r.nextEventStart)}`;
    }
    if (!r.rolloutDate) {
      return "no rollout date";
    }
    // Rollout is a date with no time, so both sides are flattened to local midnight.
    // Comparing it against the current timestamp lost a day for most of the day.
    const rollout = new Date(r.rolloutDate);
    const target = Date.UTC(
      rollout.getUTCFullYear(),
      rollout.getUTCMonth(),
      rollout.getUTCDate()
    );
    const now = new Date();
    const today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
    const days = Math.round((target - today) / 86400000);
    if (days < 0) {
      return `${Math.abs(days)} days overdue`;
    }
    return days === 0 ? "rolls out today" : `${days} days out`;
  }

  shortDate(value) {
    return new Date(value).toLocaleDateString(undefined, {
      day: "numeric",
      month: "short"
    });
  }

  // ------------------------------------------------------------ calendar span
  get calModeOptions() {
    return [
      { label: "Month", value: "month" },
      { label: "Week", value: "week" },
      { label: "Day", value: "day" }
    ];
  }

  handleCalMode(e) {
    const next = e.detail.value;
    if (!next || next === this.calMode) {
      return;
    }
    this.calMode = next;
    this.firstLoadDone = false;
    this.loadCalendar();
  }

  get isMonth() {
    return this.calMode === "month";
  }

  get isDay() {
    return this.calMode === "day";
  }

  get showGrid() {
    return !this.isDay;
  }

  /** First and last day the current span covers, inclusive. */
  get span() {
    const a = new Date(this.anchor);
    a.setHours(0, 0, 0, 0);
    if (this.calMode === "day") {
      return { from: a, to: a };
    }
    if (this.calMode === "week") {
      const from = this.startOfWeek(a);
      const to = new Date(from);
      to.setDate(to.getDate() + 6);
      return { from, to };
    }
    // Month, padded to whole weeks so the grid is always six rows of seven.
    const first = new Date(a.getFullYear(), a.getMonth(), 1);
    const from = this.startOfWeek(first);
    const to = new Date(from);
    to.setDate(to.getDate() + 41);
    return { from, to };
  }

  get spanLabel() {
    const { from, to } = this.span;
    if (this.calMode === "day") {
      return from.toLocaleDateString(undefined, {
        weekday: "long",
        day: "numeric",
        month: "long",
        year: "numeric"
      });
    }
    if (this.calMode === "week") {
      const fmt = (d) =>
        d.toLocaleDateString(undefined, { day: "numeric", month: "short" });
      return `${fmt(from)} to ${fmt(to)}`;
    }
    return new Date(
      this.anchor.getFullYear(),
      this.anchor.getMonth(),
      1
    ).toLocaleDateString(undefined, { month: "long", year: "numeric" });
  }

  get todayLabel() {
    if (this.calMode === "day") {
      return "Today";
    }
    return this.calMode === "week" ? "This week" : "This month";
  }

  step(direction) {
    const a = new Date(this.anchor);
    if (this.calMode === "day") {
      a.setDate(a.getDate() + direction);
    } else if (this.calMode === "week") {
      a.setDate(a.getDate() + 7 * direction);
    } else {
      a.setMonth(a.getMonth() + direction);
    }
    this.anchor = a;
    this.loadCalendar();
  }

  handlePrev() {
    this.step(-1);
  }

  handleNext() {
    this.step(1);
  }

  handleToday() {
    this.anchor = new Date();
    this.loadCalendar();
  }

  // ------------------------------------------------------------ calendar data
  async loadCalendar() {
    this.loading = true;
    this.error = undefined;
    try {
      const { from, to } = this.span;
      const events = await getEvents({
        fromDate: this.iso(from),
        toDate: this.iso(to),
        program: this.program || null
      });
      this.buildCalendar(events || []);
    } catch (e) {
      this.error = this.messageOf(e);
      this.buildCalendar([]);
    } finally {
      this.loading = false;
      this.firstLoadDone = true;
    }
  }

  buildCalendar(events) {
    const term = (this.searchTerm || "").trim().toLowerCase();
    const filtered = events.filter((ev) => {
      if (this.focusFacilityId && ev.facilityId !== this.focusFacilityId) {
        return false;
      }
      if (term && !(ev.facilityName || "").toLowerCase().includes(term)) {
        return false;
      }
      return true;
    });
    const decorated = filtered.map((ev) => this.decorateEvent(ev));
    const byDay = new Map();
    decorated.forEach((ev) => {
      const key = new Date(ev.startTime).toDateString();
      if (!byDay.has(key)) {
        byDay.set(key, []);
      }
      byDay.get(key).push(ev);
    });

    if (this.calMode === "day") {
      this.dayEvents = byDay.get(this.anchor.toDateString()) || [];
      this.grid = [];
      return;
    }

    const { from } = this.span;
    const todayKey = new Date().toDateString();
    const thisMonth = this.anchor.getMonth();
    const cells = [];
    const total = this.calMode === "week" ? 7 : 42;
    for (let i = 0; i < total; i++) {
      const d = new Date(from);
      d.setDate(d.getDate() + i);
      const list = byDay.get(d.toDateString()) || [];
      const isToday = d.toDateString() === todayKey;
      // A month grid spills into the neighbouring months. Those days are dimmed
      // rather than hidden, so every week stays whole.
      const outside = this.calMode === "month" && d.getMonth() !== thisMonth;
      const cap = this.calMode === "month" ? 3 : list.length;
      const hidden = list.length > cap ? list.length - cap : 0;
      cells.push({
        key: d.toISOString(),
        label: DAY_LABELS[d.getDay()],
        dayNumber: d.getDate(),
        isToday,
        addLabel: `Schedule an event on ${d.toLocaleDateString(undefined, {
          day: "numeric",
          month: "short"
        })}`,
        cellClass: `cal__cell${isToday ? " cal__cell_today" : ""}${
          outside ? " cal__cell_outside" : ""
        }`,
        headClass: `cal__cellhead${isToday ? " cal__cellhead_today" : ""}`,
        events: list.slice(0, cap),
        hasOverflow: hidden > 0,
        overflowLabel: hidden > 0 ? `+${hidden} more` : "",
        isEmpty: list.length === 0
      });
    }
    this.grid = cells;
    this.dayEvents = [];
  }

  get gridClass() {
    return this.isMonth
      ? "cal__grid cal__grid_month"
      : "cal__grid cal__grid_week";
  }

  /** Weekday headings across the top of a month or week grid. */
  get weekdayHeads() {
    return DAY_LABELS.map((d) => ({ key: d, label: d }));
  }

  get calendarHasEvents() {
    if (this.showSkeleton) {
      return false;
    }
    return this.calMode === "day"
      ? this.dayEvents.length > 0
      : this.grid.some((c) => c.events.length > 0);
  }

  get calendarIsEmpty() {
    return (
      !this.loading &&
      !this.error &&
      this.firstLoadDone &&
      !this.calendarHasEvents
    );
  }

  get emptyCalendarHeading() {
    return `Nothing booked this ${this.calMode}`;
  }

  /** A day in the month grid opens that day rather than the booking dialog. */
  handleOpenDay(e) {
    this.anchor = new Date(e.currentTarget.dataset.day);
    this.calMode = "day";
    this.firstLoadDone = false;
    this.loadCalendar();
  }

  decorateEvent(ev) {
    const lead = ev.programs && ev.programs.length ? ev.programs[0] : null;
    return {
      ...ev,
      key: ev.eventId,
      facilitatorName: ev.facilitatorName || "Unassigned",
      providerName: ev.providerName || "Unassigned",
      providerExtraLabel: ev.providerExtra ? ` +${ev.providerExtra}` : "",
      // Status now sits beside the time, so it is no longer folded into this line.
      programText: ev.programLabel || "No program",
      statusLabel: ev.onboardingStatus || "Scheduled",
      statusTone: eventStatusTone(ev.onboardingStatus),
      dotClass: `ev__dot ev__dot_${programClass(lead)}`,
      timeLabel: this.timeRange(ev.startTime, ev.endTime),
      // A month cell cannot hold "3:00 PM to 5:00 PM" beside a status chip without
      // truncating, so the grid shows the start and the full range is in the tooltip.
      timeShort: new Date(ev.startTime).toLocaleTimeString(undefined, {
        hour: "numeric",
        minute: "2-digit"
      }),
      tooltip: `${ev.facilityName}. ${this.timeRange(
        ev.startTime,
        ev.endTime
      )}. ${ev.programLabel || "No program"}. Facilitator: ${
        ev.facilitatorName || "unassigned"
      }. Providers: ${ev.providerNamesFull || "none assigned"}.`,
      css: eventChipClass(ev.programs, ev.onboardingStatus)
    };
  }

  timeRange(start, end) {
    const f = (v) =>
      new Date(v).toLocaleTimeString(undefined, {
        hour: "numeric",
        minute: "2-digit"
      });
    return end ? `${f(start)} to ${f(end)}` : f(start);
  }

  get programLegend() {
    const items = PROGRAMS.map((p) => ({
      key: p,
      label: programShortLabel(p),
      css: `legend__dot legend__dot_${programClass(p)}`
    }));
    items.push({
      key: "__cancelled",
      label: "Cancelled",
      css: "legend__dot legend__dot_cancelled"
    });
    return items;
  }

  // ------------------------------------------------------------ booking
  /**
   * The event count on a row is a button: it takes you to the calendar showing that
   * facility on its own, landing on the month its next visit falls in.
   */
  handleShowOnCalendar(e) {
    const id = e.currentTarget.dataset.id;
    const row = this.allRows.find((r) => r.facilityId === id);
    if (!row) {
      return;
    }
    this.focusFacilityId = id;
    this.focusFacilityName = row.name;
    this.view = "calendar";
    this.calMode = "month";
    this.anchor = row.nextEventStart
      ? new Date(row.nextEventStart)
      : new Date();
    this.firstLoadDone = false;
    this.loadCalendar();
  }

  get hasFocusFacility() {
    return !!this.focusFacilityId;
  }

  get focusLabel() {
    return `Showing ${this.focusFacilityName} only`;
  }

  handleClearFocus() {
    this.focusFacilityId = undefined;
    this.focusFacilityName = undefined;
    this.loadCalendar();
  }

  handleRowMenu(e) {
    const facilityId = e.currentTarget.dataset.id;
    const row = this.allRows.find((r) => r.facilityId === facilityId);
    if (!row) {
      return;
    }
    if (e.detail.value === "schedule") {
      this.openBooking({ facilityId: row.facilityId, facilityName: row.name });
    } else if (e.detail.value === "open") {
      window.open(row.facilityUrl, "_self");
    }
  }

  handleNewEvent() {
    this.openBooking({});
  }

  /** Books into the day that was chosen, rather than making you retype the date. */
  handleAddOnDay(e) {
    const iso = e.currentTarget.dataset.day;
    const start = new Date(iso);
    start.setHours(10, 0, 0, 0);
    const end = new Date(start);
    end.setHours(12, 0, 0, 0);
    this.openBooking({
      startTime: start.toISOString(),
      endTime: end.toISOString()
    });
  }

  /** Every event currently on screen, whichever span is showing. */
  get visibleEvents() {
    return this.calMode === "day"
      ? this.dayEvents
      : this.grid.reduce((all, cell) => all.concat(cell.events), []);
  }

  handleEditEvent(e) {
    const id = e.currentTarget.dataset.id;
    const found = this.visibleEvents.find((ev) => ev.eventId === id);
    if (!found) {
      return;
    }
    this.openBooking({
      eventId: found.eventId,
      facilityId: found.facilityId,
      facilityName: found.facilityName,
      programs: found.programs || [],
      facilitatorId: found.facilitatorId || "",
      providerIds: found.providerIds || [],
      onboardingStatus: found.onboardingStatus || "Scheduled",
      startTime: found.startTime,
      endTime: found.endTime
    });
  }

  async openBooking(context) {
    // A second click while the dialog is opening used to stack another modal on top
    // of the first, leaving two live copies of the same booking.
    if (this.bookingOpen) {
      return;
    }
    this.bookingOpen = true;
    try {
      await this.showBooking(context);
    } finally {
      this.bookingOpen = false;
    }
  }

  async showBooking(context) {
    const result = await FacilitySchedulingBooking.open({
      size: "medium",
      label: context.eventId
        ? "Edit facility onboarding"
        : "Schedule facility onboarding",
      context
    });
    if (!result || !result.savedId) {
      return;
    }
    this.dispatchEvent(
      new ShowToastEvent({
        title: result.edited
          ? "Onboarding visit updated"
          : "Onboarding visit scheduled",
        message: result.facilityName
          ? `${result.facilityName}. The assigned people have been emailed.`
          : "The assigned people have been emailed.",
        variant: "success"
      })
    );
    this.reload();
  }

  // ------------------------------------------------------------ dates
  startOfWeek(d) {
    const out = new Date(d);
    out.setHours(0, 0, 0, 0);
    out.setDate(out.getDate() - out.getDay());
    return out;
  }

  /**
   * A calendar date, formatted from the local parts.
   *
   * toISOString converts to UTC first, so a local midnight in any zone ahead of UTC
   * came out as the previous day and the month grid asked Apex for a span starting
   * on the wrong Saturday.
   */
  iso(d) {
    if (!d) {
      return undefined;
    }
    const x = new Date(d);
    const pad = (n) => String(n).padStart(2, "0");
    return `${x.getFullYear()}-${pad(x.getMonth() + 1)}-${pad(x.getDate())}`;
  }

  applyPreset() {
    const today = new Date();
    const y = today.getFullYear();
    const m = today.getMonth();
    let from;
    let to;

    switch (this.rangePreset) {
      case "thisMonth":
        from = new Date(y, m, 1);
        to = new Date(y, m + 1, 0);
        break;
      case "lastMonth":
        from = new Date(y, m - 1, 1);
        to = new Date(y, m, 0);
        break;
      case "next30":
        from = today;
        to = new Date(y, m, today.getDate() + 30);
        break;
      case "last3":
        from = new Date(y, m - 3, 1);
        to = today;
        break;
      case "last6":
        from = new Date(y, m - 6, 1);
        to = today;
        break;
      case "thisYear":
        from = new Date(y, 0, 1);
        to = new Date(y, 11, 31);
        break;
      case "lastYear":
        from = new Date(y - 1, 0, 1);
        to = new Date(y - 1, 11, 31);
        break;
      case "all":
      case "custom":
      default:
        return;
    }
    this.fromDate = this.iso(from);
    this.toDate = this.iso(to);
  }

  messageOf(e) {
    return e?.body?.message || e?.message || "Something went wrong. Try again.";
  }
}
