# PRD: Facility Editor Program Dates Enhancement

**Date:** 2026-01-12
**Status:** Planning

## Request Summary

Add 14 new Date fields (Launch Date and On Hold Date for 7 programs: CCM, RPM, TCM, COCM, AHTH, APCM, BHI) to Facility__c and refactor the facilityEditor LWC to display these dates in expandable row details, with automatic date clearing when program checkboxes are unchecked.

## Questions & Unclear Points

**Questions for User:**
1. Should the expandable row detail show ALL 7 programs with their dates, or only programs that are currently checked (enabled)?
   - **Assumption:** Only show date fields for programs that have their checkbox = true (as specified in requirements).
2. For the "On Hold Date" field - does setting this date have any business logic implications (e.g., should it automatically uncheck the program checkbox, or is it just informational)?
   - **Assumption:** On Hold Date is informational only; no automatic checkbox changes.
3. Should there be validation preventing Launch Date > On Hold Date (chronological order)?
   - **Assumption:** No validation required - dates are independent.
4. For bulk edit of dates - should we add a modal/action bar for setting dates on multiple selected facilities, or is inline editing sufficient?
   - **Assumption:** Inline editing is sufficient (consistent with current pattern). Editing a date while multiple rows are selected will apply to all selected rows that have the program enabled.

**Assumptions Made:**
- Date type is Date (not DateTime) - confirmed in requirements
- Uncheck behavior: Clear both dates automatically - confirmed in requirements
- UI Layout: Expandable row detail - confirmed in requirements
- Bulk edit: Only apply to facilities with program checked - confirmed in requirements
- No trigger/automation needed for date clearing - handled in LWC before save

## Data Model

### Objects Affected
- **Facility__c** - Add 14 new Date fields

### Existing Program Checkbox Fields (Reference)
| Field API Name | Label | Type |
|----------------|-------|------|
| CCM__c | CCM | Checkbox |
| RPM__c | RPM | Checkbox |
| TCM__c | TCM | Checkbox |
| COCM__c | COCM | Checkbox |
| AHTH__c | AHTH | Checkbox |
| APCM__c | APCM | Checkbox |
| BHI__c | BHI | Checkbox |

### New Fields to Create
| Field API Name | Label | Type | Description |
|----------------|-------|------|-------------|
| CCM_Launch_Date__c | CCM Launch Date | Date | When CCM program launched for this facility |
| CCM_On_Hold_Date__c | CCM On Hold Date | Date | When CCM program was put on hold |
| RPM_Launch_Date__c | RPM Launch Date | Date | When RPM program launched for this facility |
| RPM_On_Hold_Date__c | RPM On Hold Date | Date | When RPM program was put on hold |
| TCM_Launch_Date__c | TCM Launch Date | Date | When TCM program launched for this facility |
| TCM_On_Hold_Date__c | TCM On Hold Date | Date | When TCM program was put on hold |
| COCM_Launch_Date__c | COCM Launch Date | Date | When COCM program launched for this facility |
| COCM_On_Hold_Date__c | COCM On Hold Date | Date | When COCM program was put on hold |
| AHTH_Launch_Date__c | AHTH Launch Date | Date | When AHTH program launched for this facility |
| AHTH_On_Hold_Date__c | AHTH On Hold Date | Date | When AHTH program was put on hold |
| APCM_Launch_Date__c | APCM Launch Date | Date | When APCM program launched for this facility |
| APCM_On_Hold_Date__c | APCM On Hold Date | Date | When APCM program was put on hold |
| BHI_Launch_Date__c | BHI Launch Date | Date | When BHI program launched for this facility |
| BHI_On_Hold_Date__c | BHI On Hold Date | Date | When BHI program was put on hold |

### Field Set Update (Declarative)
- **Field Set:** Facility_LWC on Facility__c
- **Action:** Add all 14 new date fields to the field set (manual step after deployment)

## Implementation Plan

### Step 1: Create 14 Date Field Metadata Files

**What:** Create field-meta.xml files for all 14 new Date fields
**Where:** `/force-app/main/default/objects/Facility__c/fields/`
**Why:** Fields must exist before LWC can reference them

**Files to Create:**
```
CCM_Launch_Date__c.field-meta.xml
CCM_On_Hold_Date__c.field-meta.xml  (Note: Already exists as CCM_Opt_Out_Date__c - may need to rename or use existing)
RPM_Launch_Date__c.field-meta.xml
RPM_On_Hold_Date__c.field-meta.xml
TCM_Launch_Date__c.field-meta.xml
TCM_On_Hold_Date__c.field-meta.xml  (Note: Already exists as TCM_Opt_Out_Date__c - may need to rename or use existing)
COCM_Launch_Date__c.field-meta.xml
COCM_On_Hold_Date__c.field-meta.xml
AHTH_Launch_Date__c.field-meta.xml
AHTH_On_Hold_Date__c.field-meta.xml
APCM_Launch_Date__c.field-meta.xml
APCM_On_Hold_Date__c.field-meta.xml
BHI_Launch_Date__c.field-meta.xml
BHI_On_Hold_Date__c.field-meta.xml
```

**IMPORTANT DISCOVERY:** The following fields already exist:
- `CCM_Opt_Out_Date__c` - Similar to CCM_On_Hold_Date__c
- `TCM_Opt_Out_Date__c` - Similar to TCM_On_Hold_Date__c

**Question for User:** Should we reuse `*_Opt_Out_Date__c` fields as `*_On_Hold_Date__c`, or create new fields with the new naming convention? The existing fields may already have data.

**Assumption:** Create new fields with the specified naming pattern. The existing Opt_Out_Date fields serve a different purpose.

**Template (based on existing CCM_Opt_Out_Date__c):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>{Program}_Launch_Date__c</fullName>
    <label>{Program} Launch Date</label>
    <required>false</required>
    <trackHistory>false</trackHistory>
    <trackTrending>false</trackTrending>
    <type>Date</type>
</CustomField>
```

### Step 2: Define Program Configuration Constant in LWC

**What:** Add a constant mapping programs to their checkbox and date fields
**Where:** `facilityEditor.js`
**Why:** Centralized configuration for program-field relationships, enables iteration and reduces hardcoding

```javascript
const PROGRAM_CONFIG = [
    { name: 'CCM', checkbox: 'CCM__c', launchDate: 'CCM_Launch_Date__c', onHoldDate: 'CCM_On_Hold_Date__c' },
    { name: 'RPM', checkbox: 'RPM__c', launchDate: 'RPM_Launch_Date__c', onHoldDate: 'RPM_On_Hold_Date__c' },
    { name: 'TCM', checkbox: 'TCM__c', launchDate: 'TCM_Launch_Date__c', onHoldDate: 'TCM_On_Hold_Date__c' },
    { name: 'COCM', checkbox: 'COCM__c', launchDate: 'COCM_Launch_Date__c', onHoldDate: 'COCM_On_Hold_Date__c' },
    { name: 'AHTH', checkbox: 'AHTH__c', launchDate: 'AHTH_Launch_Date__c', onHoldDate: 'AHTH_On_Hold_Date__c' },
    { name: 'APCM', checkbox: 'APCM__c', launchDate: 'APCM_Launch_Date__c', onHoldDate: 'APCM_On_Hold_Date__c' },
    { name: 'BHI', checkbox: 'BHI__c', launchDate: 'BHI_Launch_Date__c', onHoldDate: 'BHI_On_Hold_Date__c' }
];
```

### Step 3: Modify facilityEditor.html - Add Expandable Row Pattern

**What:** Add expand/collapse button per row and detail section showing program dates
**Where:** `facilityEditor.html`
**Why:** Show program date fields without cluttering the main table

**Changes:**
1. Add expand/collapse icon column after checkbox column
2. Add conditional detail row after each data row (only visible when expanded)
3. Detail row spans all columns and shows grid of program dates

**UI Structure:**
```
| Select | Expand | # | Name | CCM | RPM | TCM | COCM | AHTH | APCM | BHI | ...other fields... |
|--------|--------|---|------|-----|-----|-----|------|------|------|-----|-------------------|
| [ ]    | v      | 1 | ABC  | [x] | [ ] | [x] | [ ]  | [ ]  | [x]  | [ ] | ...               |
|        | [EXPANDED DETAIL ROW - Program Dates Grid]                                           |
|        | CCM: Launch [date] On Hold [date] | TCM: Launch [date] On Hold [date] | APCM: ...   |
```

**Detail Row Layout (2 columns per program, 3-4 programs per row):**
- Only show programs where checkbox = true
- Each program shows: Program Name, Launch Date input, On Hold Date input
- Responsive grid: 3 programs per row on desktop, 2 on tablet, 1 on mobile

### Step 4: Modify facilityEditor.js - Add Expand/Collapse Logic

**What:** Add state management for expanded rows and handle expand/collapse
**Where:** `facilityEditor.js`
**Why:** Track which rows are expanded and rebuild display data accordingly

**Changes:**
1. Add `expandedRows` Set to track expanded row IDs
2. Add `handleToggleExpand(event)` method
3. Modify `buildTableData()` to include program checkbox states
4. Add computed property `getEnabledPrograms(row)` to filter programs by checkbox state
5. Modify row data structure to include `isExpanded` and `enabledPrograms` properties

### Step 5: Modify facilityEditor.js - Add Date Clearing Logic

**What:** When a program checkbox is unchecked, automatically clear its Launch Date and On Hold Date
**Where:** `facilityEditor.js` - `handleFieldChange()` method
**Why:** Business rule - dates should be cleared when program is disabled

**Logic:**
```javascript
// In handleFieldChange, after detecting a checkbox change:
if (isCheckbox && !newValue) {
    // Find which program this checkbox belongs to
    const program = PROGRAM_CONFIG.find(p => p.checkbox === fieldName);
    if (program) {
        // Clear both date fields in draft changes
        draftChanges.get(rowId)[program.launchDate] = null;
        draftChanges.get(rowId)[program.onHoldDate] = null;
    }
}
```

### Step 6: Modify facilityEditor.js - Add Bulk Edit Date Logic

**What:** When editing a date field with multiple rows selected, only apply to rows where the program is enabled
**Where:** `facilityEditor.js` - `handleFieldChange()` method
**Why:** Business rule - can't set dates for programs that aren't enabled on a facility

**Logic:**
```javascript
// When applying bulk date change:
if (isDateField && this.selectedFacilities.length > 1) {
    const program = PROGRAM_CONFIG.find(p =>
        p.launchDate === fieldName || p.onHoldDate === fieldName
    );
    if (program) {
        let appliedCount = 0;
        let skippedCount = 0;

        this.selectedFacilities.forEach(selectedRowId => {
            const row = this.allData.find(r => r.Id === selectedRowId);
            const isEnabled = row[program.checkbox] ||
                              this.draftChanges.get(selectedRowId)?.[program.checkbox];

            if (isEnabled) {
                // Apply the date change
                if (!this.draftChanges.has(selectedRowId)) {
                    this.draftChanges.set(selectedRowId, {});
                }
                this.draftChanges.get(selectedRowId)[fieldName] = newValue;
                appliedCount++;
            } else {
                skippedCount++;
            }
        });

        if (skippedCount > 0) {
            this.showToast('Warning',
                `Date applied to ${appliedCount} facilities. Skipped ${skippedCount} facilities without ${program.name} enabled.`,
                'warning'
            );
        }
    }
}
```

### Step 7: Modify facilityEditor.css - Add Expanded Row Styles

**What:** Style the expandable row detail section
**Where:** `facilityEditor.css`
**Why:** Visual distinction for expanded content

**Styles to Add:**
- Expand/collapse icon styling
- Detail row background color (subtle grey)
- Program date grid layout (CSS Grid or Flexbox)
- Responsive breakpoints for grid columns
- Transition animations for expand/collapse

### Step 8: Update FacilityEditorController.cls - Type Conversion for Dates

**What:** Ensure Date fields are properly handled during update
**Where:** `FacilityEditorController.cls` - `updateFacilities()` method
**Why:** Date values from JSON need proper type conversion

**Changes:**
Add Date type handling in the field type conversion logic:
```apex
} else if (fieldType == Schema.DisplayType.DATE) {
    if (fieldValue instanceof String && String.isNotBlank((String) fieldValue)) {
        facility.put(fieldName, Date.valueOf((String) fieldValue));
    } else if (fieldValue == null || (fieldValue instanceof String && String.isBlank((String) fieldValue))) {
        facility.put(fieldName, null);
    }
}
```

**Note:** The controller uses Security.stripInaccessible() - verify it's added before the update DML per security pattern.

### Step 9: Update Facility_LWC Field Set (Declarative/Manual)

**What:** Add the 14 new date fields to the Facility_LWC field set
**Where:** Salesforce Setup > Object Manager > Facility__c > Field Sets > Facility_LWC
**Why:** The LWC dynamically loads fields from this field set

**Note:** This is a manual step after field deployment. Document in deployment steps.

## Technical Specifications

- **API Version:** 65.0 (from sfdx-project.json)
- **Sharing Model:** `with sharing` (per steering/structure.md)
- **Security:** Use `Security.stripInaccessible(AccessType.UPDATABLE, records)` before DML
- **SOQL:** Use binding variables (already implemented in controller)
- **Governor Limits Considerations:**
  - Field set query is lightweight (metadata only)
  - Single SOQL for facilities, fields included dynamically
  - Single DML for bulk updates
  - No concerns with 14 additional fields

## Test Scenarios

| Scenario | Type | Expected Result |
|----------|------|-----------------|
| Expand row with CCM enabled | Positive | Shows CCM Launch Date and On Hold Date inputs |
| Expand row with no programs enabled | Edge | Shows "No programs enabled" message |
| Expand row with all 7 programs enabled | Positive | Shows all 14 date fields in organized grid |
| Set CCM Launch Date on single facility | Positive | Draft change recorded, shows in UI |
| Uncheck CCM when dates are set | Positive | Both CCM dates cleared in draft changes |
| Bulk select 5 facilities, set RPM Launch Date | Positive | Date applied only to facilities with RPM checked |
| Bulk select includes facilities without program | Positive/Warning | Warning toast shows count of skipped facilities |
| Save facilities with new date values | Positive | Dates persisted to database correctly |
| Save facilities with cleared date values (nulls) | Positive | Dates set to null in database |
| Cancel changes after setting dates | Positive | All draft date changes discarded |
| 200+ facilities with various programs | Bulk | No performance issues, UI remains responsive |
| Edit date in expanded row while filtered | Edge | Change persists after filter changes |
| Empty date field submitted | Edge | Saves as null without error |
| Invalid date format entered | Negative | Browser date picker prevents invalid input |

## FacilityEditorController Test Class Updates

The existing test class (if any) needs updates for:
1. Test facilities with program checkboxes checked
2. Test updating date fields
3. Test updating date fields to null
4. Bulk test with 200+ facilities
5. Test Date type conversion in updateFacilities()

## Success Criteria

- [ ] All 14 date field-meta.xml files created and valid
- [ ] Fields deployed successfully to org
- [ ] Expand/collapse works for all rows
- [ ] Only enabled programs shown in expanded detail
- [ ] Date inputs editable in expanded rows
- [ ] Unchecking program clears both dates
- [ ] Bulk edit respects program checkbox state
- [ ] Warning toast when bulk edit skips facilities
- [ ] Save persists dates correctly
- [ ] Cancel discards all date changes
- [ ] All tests passing
- [ ] Coverage > 80%
- [ ] No governor limit issues with 200+ records
- [ ] Deployed to dev org

## Files to Create

| File Path | Description |
|-----------|-------------|
| `force-app/main/default/objects/Facility__c/fields/CCM_Launch_Date__c.field-meta.xml` | CCM Launch Date field |
| `force-app/main/default/objects/Facility__c/fields/CCM_On_Hold_Date__c.field-meta.xml` | CCM On Hold Date field |
| `force-app/main/default/objects/Facility__c/fields/RPM_Launch_Date__c.field-meta.xml` | RPM Launch Date field |
| `force-app/main/default/objects/Facility__c/fields/RPM_On_Hold_Date__c.field-meta.xml` | RPM On Hold Date field |
| `force-app/main/default/objects/Facility__c/fields/TCM_Launch_Date__c.field-meta.xml` | TCM Launch Date field |
| `force-app/main/default/objects/Facility__c/fields/TCM_On_Hold_Date__c.field-meta.xml` | TCM On Hold Date field |
| `force-app/main/default/objects/Facility__c/fields/COCM_Launch_Date__c.field-meta.xml` | COCM Launch Date field |
| `force-app/main/default/objects/Facility__c/fields/COCM_On_Hold_Date__c.field-meta.xml` | COCM On Hold Date field |
| `force-app/main/default/objects/Facility__c/fields/AHTH_Launch_Date__c.field-meta.xml` | AHTH Launch Date field |
| `force-app/main/default/objects/Facility__c/fields/AHTH_On_Hold_Date__c.field-meta.xml` | AHTH On Hold Date field |
| `force-app/main/default/objects/Facility__c/fields/APCM_Launch_Date__c.field-meta.xml` | APCM Launch Date field |
| `force-app/main/default/objects/Facility__c/fields/APCM_On_Hold_Date__c.field-meta.xml` | APCM On Hold Date field |
| `force-app/main/default/objects/Facility__c/fields/BHI_Launch_Date__c.field-meta.xml` | BHI Launch Date field |
| `force-app/main/default/objects/Facility__c/fields/BHI_On_Hold_Date__c.field-meta.xml` | BHI On Hold Date field |

## Files to Modify

| File Path | Changes |
|-----------|---------|
| `force-app/main/default/lwc/facilityEditor/facilityEditor.html` | Add expand column, expandable detail row with program dates grid |
| `force-app/main/default/lwc/facilityEditor/facilityEditor.js` | Add PROGRAM_CONFIG, expand state, date clearing logic, bulk edit logic |
| `force-app/main/default/lwc/facilityEditor/facilityEditor.css` | Add expanded row styles, program grid layout |
| `force-app/main/default/classes/FacilityEditorController.cls` | Add Date type conversion in updateFacilities() |

## Deployment Steps

1. **Deploy field metadata** - 14 new field-meta.xml files
   ```bash
   sf project deploy start --source-dir force-app/main/default/objects/Facility__c/fields --target-org <org>
   ```

2. **Update Field Set** (Manual in Salesforce Setup)
   - Go to: Setup > Object Manager > Facility__c > Field Sets > Facility_LWC
   - Add all 14 new date fields to the field set
   - Save

3. **Deploy LWC and Controller changes**
   ```bash
   sf project deploy start --source-dir force-app/main/default/lwc/facilityEditor --target-org <org>
   sf project deploy start --source-dir force-app/main/default/classes/FacilityEditorController.cls --target-org <org>
   ```

4. **Run Tests**
   ```bash
   sf apex run test --class-names FacilityEditorControllerTest --target-org <org> --code-coverage --json
   ```

5. **Verify in UI**
   - Navigate to Account with linked Facilities
   - Verify expand/collapse works
   - Verify program dates display correctly
   - Test save functionality

---

## Summary for Orchestrator

**PRD Status:** Ready for Review

**Key Components:**
- 14 new Date fields on Facility__c (Launch Date and On Hold Date for 7 programs)
- Expandable row detail pattern in facilityEditor LWC
- Automatic date clearing when program checkbox unchecked
- Bulk edit that respects program checkbox state
- Controller update for Date type conversion

**Questions for User:**
1. Should we reuse existing `CCM_Opt_Out_Date__c` and `TCM_Opt_Out_Date__c` fields, or create new `*_On_Hold_Date__c` fields? (Current assumption: create new fields)
2. Any validation needed for Launch Date vs On Hold Date chronology? (Current assumption: no)
3. Confirm the expandable row should only show programs where checkbox = true (Current assumption: yes)

**Execution Steps (for Developer):**
1. Create 14 field-meta.xml files
2. Modify facilityEditor.js - Add PROGRAM_CONFIG constant
3. Modify facilityEditor.js - Add expand/collapse state management
4. Modify facilityEditor.js - Add date clearing logic in handleFieldChange
5. Modify facilityEditor.js - Add bulk edit filtering for dates
6. Modify facilityEditor.html - Add expand column and detail row
7. Modify facilityEditor.css - Add expanded row styles
8. Modify FacilityEditorController.cls - Add Date type conversion
9. Create/update test class with 200+ record scenarios
10. Deploy and test

**Estimated Complexity:** Medium-High
- 14 new metadata files (straightforward)
- Significant LWC refactoring (expandable rows pattern)
- Controller change is minimal but important for date handling
