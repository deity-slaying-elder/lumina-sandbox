# LMNA-630 scheduling: deploy and test script

Written for whoever runs the sandbox test pass. Everything below happens in **lumDev**.

lumDev is a Partial Copy and carries real patient data. Do not screenshot any screen showing
patient records, and do not paste patient names into Jira or Teams.

---

## 1. Deploy

From the repo root, on branch `LMNA-630-scheduling-ui`:

```bash
export SF_AUTOUPDATE_DISABLE=true

sf project deploy start --target-org lumDev \
  --source-dir force-app/main/default/lwc/facilityScheduling \
  --source-dir force-app/main/default/lwc/facilitySchedulingBooking \
  --source-dir force-app/main/default/lwc/schedulingDatatable \
  --source-dir force-app/main/default/lwc/schedulingLabels \
  --source-dir force-app/main/default/lwc/schedulingTokens \
  --source-dir force-app/main/default/lwc/statusChip \
  --source-dir force-app/main/default/lwc/emptyState \
  --source-dir force-app/main/default/lwc/uiTokens \
  --source-dir force-app/main/default/objects/Onboarding_Visit__c/fields/Programs__c.field-meta.xml \
  --source-dir force-app/main/default/classes/FacilitySchedulingController.cls \
  --source-dir force-app/main/default/classes/FacilitySchedulingControllerTest.cls \
  --source-dir force-app/main/default/classes/OnboardingVisitShadowSync.cls \
  --source-dir force-app/main/default/classes/OnboardingVisitNotifier.cls \
  --source-dir force-app/main/default/classes/SchedulingMultiProgramTest.cls \
  --source-dir force-app/main/default/triggers/OnboardingVisitTrigger.trigger \
  --source-dir force-app/main/default/triggers/OnboardingVisitProviderTrigger.trigger
```

Then run the Apex tests:

```bash
sf apex run test --target-org lumDev --wait 20 \
  --class-names FacilitySchedulingControllerTest \
  --class-names SchedulingMultiProgramTest \
  --result-format human
```

Open the page:

```bash
sf org open --target-org lumDev --path lightning/n/Facility_Scheduling_Page
```

### If the deploy fails

The Apex has never been compiled. It was parse-checked only, with the Apex formatter. Two
classes of failure are the likely ones:

- A field the controller reads that is spelled differently in the org. The error names it.
- `Programs__c` not existing yet, if the field deployed after the Apex. Deploy the field on
  its own first, then the rest.

---

## 2. What changed, in order of what to look at

**The look.** Headings no longer truncate to "Cen...", "Conse..." and "Eve...". Status is a
chip rather than plain text. A facility with nothing booked gets an amber "None yet" chip
instead of a zero. List and Calendar are real tabs. The two greyed-out date boxes are gone,
and only appear when you pick Custom range. Filters show as removable pills. Empty and failed
states say what happened and offer the next step.

**Multiple programs.** A visit now carries several. The dialog has a checklist, not a single
picklist.

**Programs follow the facility.** The checklist only enables the programs that facility is
marked Active for. The rest stay visible but disabled, with the reason next to them.

**Notifications.** Creating, moving or cancelling a visit emails the facilitator and every
assigned provider. Adding or removing one provider emails just that person.

**Patient counts in the dialog.** Census, Seen and Consented for the chosen facility, so you
do not have to close the dialog to read them.

---

## 3. Test script

Work top to bottom. Each step says what you should see.

### 3.1 The list

1. Open the tab. Every column heading reads as a whole word. No "Cen...".
2. A facility with no event shows an amber **None yet** chip in Scheduled.
3. A facility with events shows a green **N events** chip.
4. Status shows as a coloured chip, not plain text.
5. The line above the table names the count, for example "2 facilities, 1 with no event
   scheduled".
6. Change Date range to **Custom range**. Two date boxes appear. Change it back. They go.
7. Set Program to TCM. A pill reads "Program: TCM". Remove the pill. The list widens again.
8. Filter to something that matches nothing. You get a "No facilities match these filters"
   panel with a **Clear filters** button, not a blank box.

### 3.2 Booking a visit

9. Use the row menu **Schedule** on a facility. The dialog opens with that facility filled in,
   not the first one in the list.
10. The dialog shows Census, Seen and Consented for that facility.
11. The Programs section lists all eight. The ones the facility is not Active for are greyed
    with "Not active at this facility." Community Full-Time and IPV Onboarding are selectable
    with "Not tracked on the facility record."
12. Tick two programs. The line below reads "2 programs on this visit: TCM, BHI".
13. The provider list shrinks. The help text says how many were hidden and why.
14. Press **Escape**. The dialog closes. Reopen it and press Tab repeatedly: focus stays
    inside the dialog and does not fall through to the page behind.
15. Save with a facility but no time set. The footer says "Set a start and end time to
    continue" and Save is disabled. It should never be disabled without saying why.
16. Save a valid visit. You get a toast titled "Onboarding visit scheduled".

### 3.3 Conflicts and licensing

17. Tick BHI and CoCM together. You should be blocked with "BHI and CoCM cannot be billed on
    the same visit."
18. Pick a provider licensed for only one of two ticked programs. The block names the program
    they are missing, not just the provider.
19. Book the same provider into two overlapping visits. The second is refused and names them.

### 3.4 Notifications

20. Check the inbox of the facilitator and the provider on a visit you just created. Both
    should have an email naming the facility, the window and the programs.
21. Move the visit an hour. Both get a "changed" email.
22. Add a fourth provider. Only that person gets an email.
23. Remove them. Only that person gets an email.
24. Cancel the visit. Everyone gets a "cancelled" email.
25. Save the cancelled visit again without changing anything. **Nobody** gets another email.

### 3.5 Calendar

26. Switch to Calendar. Today's column is outlined.
27. A two-program visit shows both program names on the chip.
28. A cancelled visit is grey with the facility name struck through.
29. Tab to a visit chip and press Enter. The dialog opens. The focus ring is clearly visible.
30. Move to a week with nothing in it. Each day reads "Nothing booked".

### 3.6 Other users

Log in as, in turn: a scheduling coordinator, a user with the Facility Scheduling permission
set, and a user without it.

31. The coordinator can do everything above.
32. A user without Patient access still sees a usable list, with the counts showing zero
    rather than the page erroring.
33. A user who cannot see a facility cannot book against it. The dialog says the facility was
    not found rather than failing silently.

### 3.7 Small screen

34. Narrow the browser to phone width. The calendar stacks into day rows. Nothing scrolls
    sideways.

---

## 4. Known gaps

- **The Apex has not been compiled or run.** Jest covers the front end, 71 tests across 7
  suites, all passing. Nothing has exercised the Apex.
- **The live theme was not probed.** The CSS uses hooks that mean the same thing on classic
  and Cosmos, with classic values as the fallback, so it is safe either way, but nobody has
  read `getComputedStyle` in this org to confirm which is running.
- **The rendered page has not been audited.** `ui-audit.mjs` needs a live URL, so contrast,
  touch targets and focus have been reasoned about rather than measured.
- **Program conflict pairs are still one row.** Only BHI and CoCM. Dorothy has not confirmed
  the rest, so step 17 is the only conflict that can fire.
- **RPM, PCM and APCM** are tracked on the facility but are not offered as programs. That is a
  product decision, not an oversight.
- **`Program__c` on the visit is now unused.** `Programs__c` replaced it. The old field was
  left in place rather than deleted; it should go once this is signed off.
- **Event.Onboarding_Program__c stays single-value.** Activity fields are shared with Task, so
  it carries the first program and the Event description carries the full list.
