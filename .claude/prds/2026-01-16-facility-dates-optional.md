# PRD: Make Launch Dates and On Hold Dates Optional in FacilityEditor

**Date:** 2026-01-16
**Status:** Analysis Complete - Ready for Review

## Request Summary
Make Launch Date and On Hold Date fields NOT required when enabling programs in the facilityEditor LWC component. Users should be able to enable a program checkbox without being forced to enter dates.

## Questions & Unclear Points

**Questions for User:**
None - the change has minimal risk based on analysis.

**Assumptions:**
- Business logic does not depend on dates being populated when a program is enabled
- Reports/dashboards may show null dates, which is acceptable
- No downstream integrations require these dates to be populated

## Impact Analysis

### 1. Apex Controller (FacilityEditorController.cls)
**Status:** NO CHANGES NEEDED
- The controller has no date validation logic
- It dynamically handles field updates based on what the LWC sends
- Lines 143-149 already handle null/empty date values correctly:
  ```apex
  if (fieldValue == null || (fieldValue instanceof String && String.isBlank((String) fieldValue))) {
      facility.put(fieldName, null);
  }
  ```

### 2. Triggers on Facility__c
**Status:** NO IMPACT
- No triggers exist directly on Facility__c
- Only `dlrs_Opportunity_FacilityTrigger.trigger` exists (DLRS rollup, not related to dates)

### 3. Validation Rules on Facility__c
**Status:** NO IMPACT
- No validation rules found in source control for Facility__c object
- NOTE: Should verify in target org that no validation rules exist there

### 4. Field Definitions
**Status:** ALREADY OPTIONAL
- All date fields have `<required>false</required>` in their metadata
- Example from CCM_Launch_Date__c.field-meta.xml:
  ```xml
  <required>false</required>
  ```

### 5. Field Set (Facility_LWC)
**Status:** ALREADY OPTIONAL
- All fields in the field set have `<isRequired>false</isRequired>`

### 6. Flows
**Status:** NO IMPACT
- Three flows reference Facility__c but NONE use Launch_Date or On_Hold_Date fields:
  - Report_User_Facility_TF_on_C_U_Update_Name.flow-meta.xml
  - Facility_Mapper_TF_Delete_False_Leaked_Admissions.flow-meta.xml
  - Facility_SF_Create_Opp.flow-meta.xml

### 7. HTML Template (facilityEditor.html)
**Status:** CLEANUP NEEDED
- Line 163 has outdated tooltip text: `title="Both dates are required"`
- No `required` attributes on the date input fields themselves
- Validation error UI elements exist but are controlled by JS (already disabled)

### 8. JavaScript (facilityEditor.js)
**Status:** VALIDATION ALREADY REMOVED
- Lines 733-736 show validation is already disabled:
  ```javascript
  validateDates() {
      // Launch dates and on hold dates are optional - no validation required
      return [];
  }
  ```
- However, the HTML still shows validation error UI components that will never trigger

## Data Model
- **Objects affected:** Facility__c
- **Fields:** (already exist, no changes needed)
  - CCM_Launch_Date__c, CCM_On_Hold_Date__c
  - RPM_Launch_Date__c, RPM_On_Hold_Date__c
  - TCM_Launch_Date__c, TCM_On_Hold_Date__c
  - COCM_Launch_Date__c, COCM_On_Hold_Date__c
  - AHTH_Launch_Date__c, AHTH_On_Hold_Date__c
  - APCM_Launch_Date__c, APCM_On_Hold_Date__c
  - BHI_Launch_Date__c, BHI_On_Hold_Date__c

## Implementation Plan

### Step 1: Clean Up HTML Template (Optional but Recommended)
- **What:** Remove/update vestigial validation UI elements
- **Where:** `/force-app/main/default/lwc/facilityEditor/facilityEditor.html`
- **Why:** Dead code cleanup - validation error UI will never display

**Changes:**
1. Line 157-165: Remove warning icon with "Both dates are required" tooltip
2. Lines 179-181: Remove "Required" error text for launch date
3. Lines 194-196: Remove "Required" error text for on hold date
4. Lines 321-323: Remove modal launch date "Required" error text
5. Lines 337-339: Remove modal on hold date "Required" error text

### Step 2: Clean Up JavaScript (Optional but Recommended)
- **What:** Remove unused validation properties from program objects
- **Where:** `/force-app/main/default/lwc/facilityEditor/facilityEditor.js`
- **Why:** Dead code cleanup

**Properties that could be removed from `computeRowDisplayProperties` (lines 183-188):**
- `hasLaunchDateError: false`
- `hasOnHoldDateError: false`
- `hasValidationError: false`
- `launchDateClass: 'date-input'` (can simplify since no error variant)
- `onHoldDateClass: 'date-input'`

**Properties that could be removed from `modalProgramList` getter (lines 606-609):**
- `hasLaunchDateError: false`
- `hasOnHoldDateError: false`

### Step 3: Update Help Text (Optional)
- **What:** Update help text to clarify dates are optional
- **Where:** `/force-app/main/default/lwc/facilityEditor/facilityEditor.html` line 214
- **Why:** User clarity

## Technical Specifications
- API Version: 65.0
- No Apex changes required
- No deployment of objects/fields required
- LWC-only cleanup

## Test Scenarios
| Scenario | Type | Expected Result |
|----------|------|-----------------|
| Enable program without dates | Positive | Save succeeds, dates are null |
| Enable program with launch date only | Positive | Save succeeds, on hold date is null |
| Enable program with on hold date only | Positive | Save succeeds, launch date is null |
| Enable program with both dates | Positive | Save succeeds, both dates populated |
| Clear existing dates | Positive | Save succeeds, dates become null |
| Bulk enable 200+ facilities without dates | Bulk | Save succeeds for all |

## Risks & Considerations

### Low Risk Items
1. **Reports/Dashboards:** May show blank dates - verify this is acceptable
2. **Integrations:** Verify Thoroughcare or other systems don't require dates
3. **Org Validation Rules:** Verify no validation rules exist in the org that aren't in source control

### No Risk Items
- Apex controller already handles null dates
- No triggers enforce date requirements
- No flows use these date fields
- Field definitions already mark fields as optional

## Success Criteria
- [x] Validation removed from JS (already done)
- [ ] HTML cleanup (optional - dead code removal)
- [ ] Test in dev org: enable program without dates
- [ ] Verify no org-level validation rules block the save
- [ ] Deploy to dev org

## Summary for Orchestrator

**PRD Status:** Ready for Review (Analysis shows LOW RISK)

**Key Findings:**
1. JS validation is ALREADY removed (lines 733-736)
2. Apex controller has NO date validation
3. NO triggers, flows, or validation rules enforce dates
4. All field definitions already mark dates as optional

**Recommended Actions:**
1. **Minimal:** No code changes needed - just test and deploy current state
2. **Recommended:** Clean up dead validation UI code in HTML (lines 157-196, 321-339)
3. **Optional:** Remove unused validation properties from JS

**Questions for User:**
- Should we clean up the dead validation UI code, or leave as-is?
- Want to verify in the target org for any validation rules not in source control?

**Execution Steps (if cleanup approved):**
1. Developer removes dead validation UI from HTML
2. Developer removes unused validation properties from JS
3. Deploy and test
4. QA review
