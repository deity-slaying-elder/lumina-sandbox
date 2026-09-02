# PRD: Facility Editor UX Fixes

**Date:** 2026-01-13
**Status:** Planning

## Request Summary
Fix 5 UX/functionality issues in the facilityEditor LWC: (1) Add "Select All Programs" per-row functionality, (2) Auto-expand row when program selected, (3) Require Launch Date when program enabled, (4) Fix Select All rows checkbox, (5) Add bulk "Set Dates" modal for selected facilities.

## Questions & Unclear Points

**Questions for User:**
1. **Select All Programs per Row:** Should this be a button in the row (next to expand chevron) or a button in each program header column? Or both?
2. **Auto-Expand Behavior:** When selecting ALL programs at once (via "Select All Programs"), should it also auto-expand? Or only when individual checkboxes are clicked?
3. **Date Validation - Which Dates Required?** When a program is enabled, should ONLY Launch Date be required, or BOTH Launch Date AND On Hold Date? (Task mentions "Launch Date" specifically)
4. **Date Validation - When to Validate?** Should validation happen:
   - On save attempt (prevent save with error message)?
   - Inline (show red border on empty required fields)?
   - Both?
5. **Set Dates Modal - Which Dates?** Should the modal allow setting:
   - Only Launch Date for all enabled programs?
   - Both Launch Date and On Hold Date?
   - Separate date fields per program type (CCM Launch, RPM Launch, etc.)?
6. **Set Dates Modal - Apply Logic:** Should the modal:
   - Apply dates only to programs already enabled on selected facilities?
   - OR enable all programs and apply dates?
   - OR let user select which programs to apply dates to?

**Assumptions (if questions not answered):**
- Select All Programs button placed per-row (next to expand chevron)
- Auto-expand triggers on both individual checkbox and "Select All Programs"
- Only Launch Date required (On Hold Date optional)
- Validation on save attempt with inline visual indicators
- Modal allows setting dates for programs already enabled on selected facilities

---

## Issue Analysis

### Issue 1: Select All Programs Per Row

**Current State:**
- No "Select All Programs" functionality exists per row
- Users must click each of 7 program checkboxes individually
- Toolbar has "Select All" for row selection, not programs

**Root Cause:**
- Feature not implemented - no handler or UI element exists

**Solution:**
- Add a button in each row (col-expand area or new column) labeled "All" or with icon
- Handler `handleSelectAllPrograms(event)` to toggle all 7 programs for that row
- Apply bulk logic if multiple rows selected

### Issue 2: Auto-Expand When Program Selected

**Current State:**
- `handleProgramToggle()` only collapses rows when ALL programs disabled (line 271)
- Does NOT auto-expand when program is enabled
- User must manually click chevron to see dates

**Root Cause:**
- Missing `this.expandedRows.add(targetRowId)` when program checkbox is checked

**Solution:**
- Add auto-expand logic in `handleProgramToggle()` when `isChecked === true`
- Ensure reactivity triggers properly

### Issue 3: Date Validation for Enabled Programs

**Current State:**
- No validation exists - dates are optional regardless of program status
- `handleUpdateFacilities()` calls `buildUpdateData()` without validation
- `buildUpdateData()` only checks if values changed, not if required

**Root Cause:**
- Validation logic never implemented

**Solution:**
- Add `validateRequiredDates()` method
- Check: For each enabled program checkbox, ensure Launch Date is not null
- Return validation errors with facility names and missing programs
- Block save with user-friendly error message
- Add visual indicator (CSS class) on empty required date fields

### Issue 4: Select All Checkbox Not Working

**Current State:**
- `handleSelectAllRows(event)` exists (lines 211-221)
- `allRowsSelected` getter exists (lines 414-417)
- HTML binding appears correct (lines 57-62)

**Root Cause Investigation:**
The logic appears correct. Possible issues:
1. **Reactivity:** `selectedFacilities` is a @track array, assignment should trigger
2. **Checkbox binding:** Uses `checked={allRowsSelected}` which should work
3. **Event target:** `event.target.checked` should work for lightning-input

**Likely Issue:**
- The checkbox shows "Select All" label but the getter `allRowsSelected` may not reflect state properly when list is filtered
- Or the checkbox state gets out of sync after filtering

**Solution:**
- Debug and verify event handler fires
- Ensure `filterData()` recomputes properly
- May need explicit reactivity trigger

### Issue 5: Set Dates Modal

**Current State:**
- No modal exists for bulk date setting
- Dates can only be set by expanding individual rows

**Root Cause:**
- Feature not implemented

**Solution:**
- Add "Set Dates" button in toolbar (next to Select All)
- Button enabled only when `selectedFacilityCount > 0`
- Modal contains:
  - Header showing count of selected facilities
  - For each program (or enabled programs): Launch Date + On Hold Date inputs
  - Apply / Cancel buttons
- Handler applies dates to all selected facilities' enabled programs
- Consider checkbox to select which programs to apply to

---

## Data Model

**Objects Affected:**
- Facility__c (existing)

**Fields Referenced (existing, no new fields):**
| Field API Name | Type | Purpose |
|----------------|------|---------|
| CCM__c | Checkbox | CCM program enabled |
| CCM_Launch_Date__c | Date | CCM launch date |
| CCM_On_Hold_Date__c | Date | CCM on hold date |
| RPM__c | Checkbox | RPM program enabled |
| RPM_Launch_Date__c | Date | RPM launch date |
| RPM_On_Hold_Date__c | Date | RPM on hold date |
| TCM__c | Checkbox | TCM program enabled |
| TCM_Launch_Date__c | Date | TCM launch date |
| TCM_On_Hold_Date__c | Date | TCM on hold date |
| COCM__c | Checkbox | COCM program enabled |
| COCM_Launch_Date__c | Date | COCM launch date |
| COCM_On_Hold_Date__c | Date | COCM on hold date |
| AHTH__c | Checkbox | AHTH program enabled |
| AHTH_Launch_Date__c | Date | AHTH launch date |
| AHTH_On_Hold_Date__c | Date | AHTH on hold date |
| APCM__c | Checkbox | APCM program enabled |
| APCM_Launch_Date__c | Date | APCM launch date |
| APCM_On_Hold_Date__c | Date | APCM on hold date |
| BHI__c | Checkbox | BHI program enabled |
| BHI_Launch_Date__c | Date | BHI launch date |
| BHI_On_Hold_Date__c | Date | BHI on hold date |

---

## Implementation Plan

### Step 1: Fix Select All Rows (Issue 4)

**What:** Debug and fix the Select All checkbox functionality

**Where:** `facilityEditor.js` - `handleSelectAllRows()` method (lines 211-221)

**Why:** This is likely a simple fix and resolves existing broken functionality

**Details:**
1. Verify event handler fires (add temporary console.log)
2. Check if `filteredData` is populated at time of call
3. Verify reactivity - may need `this.selectedFacilities = [...newArray]` pattern
4. Test with both checked and unchecked scenarios

**Acceptance:**
- Clicking "Select All" selects all visible rows
- Clicking again deselects all rows
- Works correctly after search filtering

---

### Step 2: Add Auto-Expand on Program Selection (Issue 2)

**What:** Auto-expand row when user enables a program checkbox

**Where:** `facilityEditor.js` - `handleProgramToggle()` method (lines 245-283)

**Why:** Users expect to set dates immediately after enabling a program

**Details:**
1. Inside the `targetRows.forEach()` loop, after setting program to enabled:
2. Add: `if (isChecked) { this.expandedRows.add(targetRowId); }`
3. Existing code already handles reactivity: `this.expandedRows = new Set(this.expandedRows);`

**Acceptance:**
- Enabling any program checkbox auto-expands that row
- Disabling all programs auto-collapses (existing behavior retained)
- Works for bulk operations (multiple selected rows)

---

### Step 3: Add Select All Programs Per Row (Issue 1)

**What:** Add button to select/deselect all 7 programs for a single row

**Where:**
- `facilityEditor.html` - Add button in row (suggest after expand column or in col-expand)
- `facilityEditor.js` - Add `handleSelectAllPrograms()` method
- `facilityEditor.css` - Style the button

**Why:** Saves time when enabling all programs for a facility

**Details:**

**HTML Changes:**
- Add new column or button inside existing expand column
- Button with icon (utility:check_all or text "All")
- data-id attribute for row identification

**JS Changes:**
```javascript
handleSelectAllPrograms(event) {
    const rowId = event.currentTarget.dataset.id;

    // Determine if selecting all or deselecting all
    // If any program is disabled, select all; otherwise deselect all
    const row = this.filteredData.find(r => r.Id === rowId);
    const allEnabled = PROGRAM_CONFIG.every(p =>
        this.draftChanges.get(rowId)?.[p.checkbox] ?? row[p.checkbox]
    );
    const newValue = !allEnabled;

    // Apply to target rows (bulk if multiple selected)
    const targetRows = (this.selectedFacilities.length > 1 && this.selectedFacilities.includes(rowId))
        ? this.selectedFacilities
        : [rowId];

    targetRows.forEach(targetRowId => {
        if (!this.draftChanges.has(targetRowId)) {
            this.draftChanges.set(targetRowId, {});
        }

        PROGRAM_CONFIG.forEach(program => {
            this.draftChanges.get(targetRowId)[program.checkbox] = newValue;

            // Clear dates if disabling
            if (!newValue) {
                this.draftChanges.get(targetRowId)[program.launchDate] = null;
                this.draftChanges.get(targetRowId)[program.onHoldDate] = null;
            }
        });

        this.rowsWithChanges.add(targetRowId);

        // Auto-expand if enabling
        if (newValue) {
            this.expandedRows.add(targetRowId);
        } else {
            this.expandedRows.delete(targetRowId);
        }
    });

    this.expandedRows = new Set(this.expandedRows);
    this.filterData();

    // Toast notification for bulk
    if (targetRows.length > 1) {
        const action = newValue ? 'enabled' : 'disabled';
        this.showToast('Success', `All programs ${action} for ${targetRows.length} facilities`, 'success');
    }
}
```

**Acceptance:**
- Button visible in each row
- Click toggles all 7 programs
- Works with bulk selection
- Auto-expands when enabling all

---

### Step 4: Add Date Validation (Issue 3)

**What:** Require Launch Date when program is enabled

**Where:**
- `facilityEditor.js` - Add `validateRequiredDates()` method, modify `handleUpdateFacilities()`
- `facilityEditor.html` - Add required indicator styling
- `facilityEditor.css` - Add error styling for empty required fields

**Why:** Ensures data integrity - programs need launch dates

**Details:**

**JS Changes:**
```javascript
validateRequiredDates() {
    const errors = [];

    this.filteredData.forEach(row => {
        const draftRow = this.draftChanges.get(row.Id) || {};

        PROGRAM_CONFIG.forEach(program => {
            // Check if program is enabled (draft value or original)
            const isEnabled = draftRow[program.checkbox] !== undefined
                ? draftRow[program.checkbox]
                : row[program.checkbox];

            if (isEnabled) {
                // Check if launch date exists
                const launchDate = draftRow[program.launchDate] !== undefined
                    ? draftRow[program.launchDate]
                    : row[program.launchDate];

                if (!launchDate) {
                    errors.push({
                        facilityId: row.Id,
                        facilityName: row.Name,
                        program: program.name,
                        field: 'Launch Date'
                    });
                }
            }
        });
    });

    return errors;
}

// Modify handleUpdateFacilities:
handleUpdateFacilities() {
    // Validate first
    const validationErrors = this.validateRequiredDates();
    if (validationErrors.length > 0) {
        const uniqueFacilities = [...new Set(validationErrors.map(e => e.facilityName))];
        const message = validationErrors.length <= 3
            ? validationErrors.map(e => `${e.facilityName}: ${e.program} Launch Date required`).join('. ')
            : `${validationErrors.length} programs missing Launch Date across ${uniqueFacilities.length} facilities`;
        this.showToast('Validation Error', message, 'error');
        return;
    }

    // Continue with existing save logic...
}
```

**CSS Changes:**
```css
/* Required field indicator */
.date-input-required {
    --slds-c-input-color-border: #c23934;
}

.date-input-required::after {
    content: '*';
    color: #c23934;
    margin-left: 2px;
}
```

**HTML Changes:**
- Add dynamic class to date inputs based on validation state
- Consider adding required asterisk to Launch Date label

**Acceptance:**
- Save blocked if any enabled program lacks Launch Date
- Error toast shows which facilities/programs are missing dates
- Visual indicator on empty required fields
- On Hold Date remains optional

---

### Step 5: Add Set Dates Modal (Issue 5)

**What:** Modal to bulk-set dates for selected facilities

**Where:**
- `facilityEditor.html` - Add button in toolbar, add modal markup
- `facilityEditor.js` - Add modal state, handlers, apply logic
- `facilityEditor.css` - Modal styling

**Why:** Enables efficient bulk date assignment across facilities

**Details:**

**State Properties:**
```javascript
@track isSetDatesModalOpen = false;
@track modalDates = {}; // { CCM_Launch_Date__c: 'YYYY-MM-DD', ... }
```

**HTML - Toolbar Button:**
```html
<template lwc:if={selectedFacilityCount}>
    <lightning-button
        variant="neutral"
        label="Set Dates"
        icon-name="utility:date_input"
        onclick={handleOpenSetDatesModal}
        class="slds-m-left_x-small">
    </lightning-button>
</template>
```

**HTML - Modal:**
```html
<template lwc:if={isSetDatesModalOpen}>
    <section role="dialog" tabindex="-1" class="slds-modal slds-fade-in-open">
        <div class="slds-modal__container">
            <header class="slds-modal__header">
                <lightning-button-icon
                    icon-name="utility:close"
                    variant="bare-inverse"
                    onclick={handleCloseSetDatesModal}
                    class="slds-modal__close">
                </lightning-button-icon>
                <h2 class="slds-modal__title">Set Program Dates</h2>
            </header>
            <div class="slds-modal__content slds-p-around_medium">
                <p class="slds-m-bottom_medium">
                    Set dates for {selectedFacilityCount} selected facilities.
                    Dates will apply only to programs that are enabled.
                </p>
                <div class="modal-date-grid">
                    <template for:each={programColumns} for:item="prog">
                        <div key={prog.name} class="modal-program-dates">
                            <span class="modal-program-label">{prog.name}</span>
                            <lightning-input
                                type="date"
                                label="Launch Date"
                                data-field={prog.launchDate}
                                onchange={handleModalDateChange}>
                            </lightning-input>
                            <lightning-input
                                type="date"
                                label="On Hold"
                                data-field={prog.onHoldDate}
                                onchange={handleModalDateChange}>
                            </lightning-input>
                        </div>
                    </template>
                </div>
            </div>
            <footer class="slds-modal__footer">
                <lightning-button
                    label="Cancel"
                    onclick={handleCloseSetDatesModal}>
                </lightning-button>
                <lightning-button
                    variant="brand"
                    label="Apply Dates"
                    onclick={handleApplyModalDates}>
                </lightning-button>
            </footer>
        </div>
    </section>
    <div class="slds-backdrop slds-backdrop_open"></div>
</template>
```

**JS Handlers:**
```javascript
handleOpenSetDatesModal() {
    this.modalDates = {};
    this.isSetDatesModalOpen = true;
}

handleCloseSetDatesModal() {
    this.isSetDatesModalOpen = false;
    this.modalDates = {};
}

handleModalDateChange(event) {
    const field = event.target.dataset.field;
    const value = event.target.value || null;
    this.modalDates[field] = value;
}

handleApplyModalDates() {
    let appliedCount = 0;

    this.selectedFacilities.forEach(facilityId => {
        const row = this.filteredData.find(r => r.Id === facilityId);
        if (!row) return;

        if (!this.draftChanges.has(facilityId)) {
            this.draftChanges.set(facilityId, {});
        }

        PROGRAM_CONFIG.forEach(program => {
            // Check if program is enabled
            const draftValue = this.draftChanges.get(facilityId)?.[program.checkbox];
            const isEnabled = draftValue !== undefined ? draftValue : row[program.checkbox];

            if (isEnabled) {
                // Apply dates from modal if provided
                if (this.modalDates[program.launchDate]) {
                    this.draftChanges.get(facilityId)[program.launchDate] = this.modalDates[program.launchDate];
                }
                if (this.modalDates[program.onHoldDate]) {
                    this.draftChanges.get(facilityId)[program.onHoldDate] = this.modalDates[program.onHoldDate];
                }
                appliedCount++;
            }
        });

        this.rowsWithChanges.add(facilityId);
    });

    this.handleCloseSetDatesModal();
    this.filterData();

    if (appliedCount > 0) {
        this.showToast('Success', `Dates applied to ${appliedCount} enabled programs`, 'success');
    } else {
        this.showToast('Info', 'No enabled programs found on selected facilities', 'info');
    }
}
```

**CSS:**
```css
.modal-date-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 1rem;
}

.modal-program-dates {
    padding: 0.75rem;
    background: #f3f3f3;
    border-radius: 0.25rem;
}

.modal-program-label {
    display: block;
    font-weight: 600;
    margin-bottom: 0.5rem;
    color: #0070d2;
}
```

**Acceptance:**
- "Set Dates" button visible when facilities selected
- Modal shows all 7 programs with date fields
- Applies dates only to enabled programs
- Shows success count
- Empty modal fields don't overwrite existing dates

---

## Technical Specifications

- **API Version:** 65.0 (from tech.md)
- **Sharing Model:** Not applicable (LWC component, Apex already `with sharing`)
- **Security:** No new Apex changes - existing controller handles CRUD/FLS
- **Governor Limits:** N/A for frontend changes

---

## Test Scenarios

| # | Scenario | Type | Expected Result |
|---|----------|------|-----------------|
| 1 | Click "Select All" with no rows selected | Positive | All visible rows selected |
| 2 | Click "Select All" with all rows selected | Positive | All rows deselected |
| 3 | Click "Select All" after filtering | Edge | Only filtered rows selected |
| 4 | Enable single program checkbox | Positive | Row auto-expands to show dates |
| 5 | Enable program on selected rows (bulk) | Bulk | All selected rows expand |
| 6 | Click "All Programs" button (none enabled) | Positive | All 7 programs enabled, row expands |
| 7 | Click "All Programs" button (all enabled) | Positive | All 7 programs disabled, row collapses |
| 8 | Click "All Programs" with multi-select | Bulk | All programs toggled on all selected rows |
| 9 | Save with enabled program, no Launch Date | Negative | Validation error, save blocked |
| 10 | Save with enabled program + Launch Date | Positive | Save succeeds |
| 11 | Save with 5 programs enabled, 2 missing dates | Negative | Error shows all missing fields |
| 12 | Open Set Dates modal, no facilities selected | Edge | Button not visible |
| 13 | Apply dates via modal to 10 selected facilities | Bulk | Dates applied to enabled programs only |
| 14 | Apply dates when no programs enabled | Edge | Info toast, no changes |
| 15 | Apply Launch Date only (leave On Hold empty) | Positive | Only Launch Date applied |

---

## Success Criteria

- [ ] Select All rows checkbox works correctly
- [ ] Program checkbox auto-expands row
- [ ] "All Programs" per-row button works
- [ ] Launch Date validation blocks invalid saves
- [ ] Set Dates modal applies dates to selected facilities
- [ ] All 15 test scenarios pass manual testing
- [ ] No regressions in existing functionality
- [ ] Component deploys successfully

---

## Summary for Orchestrator

**PRD Status:** Needs Clarification (see questions)

**Key Components:**
- facilityEditor.js - 5 handler modifications/additions
- facilityEditor.html - Toolbar button + modal markup + row button
- facilityEditor.css - Modal styles + validation styles

**Questions for User:**
1. Where should "Select All Programs" button go - per row or header?
2. Should auto-expand trigger on "Select All Programs" too?
3. Is ONLY Launch Date required, or both dates?
4. Should validation be on-save, inline, or both?
5. What programs should modal allow setting dates for?
6. Should modal apply to enabled programs only, or allow enabling?

**Execution Steps (after questions answered):**
1. Fix Select All rows checkbox
2. Add auto-expand on program selection
3. Add "Select All Programs" per-row button
4. Add Launch Date validation
5. Add Set Dates modal
6. Manual testing of 15 scenarios
7. Deploy to dev org
