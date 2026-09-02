# QA Report: Facility Editor Program Dates

**Date:** 2026-01-12
**Reviewer:** Salesforce Senior Developer (QA)
**Status:** CONDITIONAL PASS - Requires FLS Configuration

---

## Summary

The implementation adds 14 new Date fields (Launch Date and On Hold Date for 7 programs) to the Facility__c object and updates the FacilityEditor LWC to support expandable row details for viewing and editing program dates.

---

## Security Gate Results

| Check | Status | Details |
|-------|--------|---------|
| `with sharing` | PASS | Class uses `public with sharing class FacilityEditorController` (line 1) |
| FLS Enforcement | PASS | Uses `Security.stripInaccessible()` before DML (lines 167-171) |
| SOQL Injection | PASS | Dynamic SOQL uses field paths from FieldSet metadata only, not user input |
| Hardcoded IDs/Secrets | PASS | No hardcoded IDs or credentials found |

---

## PRD Requirements Verification

| # | Requirement | Status | Evidence |
|---|------------|--------|----------|
| 1 | 14 Date fields created | PASS | 7 Launch_Date and 7 On_Hold_Date fields exist in `force-app/main/default/objects/Facility__c/fields/` |
| 2 | Expandable row detail pattern | PASS | LWC implements `handleToggleExpand`, `expandedRows` Set, and renders `expanded-detail-row` |
| 3 | Show dates only for enabled programs | PASS | `getEnabledProgramsForRow()` filters based on program checkbox value |
| 4 | Clear dates when unchecking program | PASS | `handleFieldChange()` clears `launchDate` and `onHoldDate` when program unchecked |
| 5 | Bulk edit with skip warning | PASS | `handleFieldChange()` shows warning toast for skipped facilities without program |
| 6 | Date type conversion | PASS | Controller handles string-to-Date conversion and null/empty string clearing (lines 143-149) |
| 7 | Security.stripInaccessible | PASS | Applied before DML at line 167 |
| 8 | 200+ record bulk testing | PASS | Test class creates 250 facilities in @TestSetup |

---

## Files Reviewed

### Apex Controller: `/force-app/main/default/classes/FacilityEditorController.cls`

**Security:** PASS
- Uses `with sharing` (line 1)
- Uses `Security.stripInaccessible(AccessType.UPDATABLE, ...)` before DML (lines 167-171)
- No string concatenation in SOQL with user input

**Governor Limits:** PASS
- Single SOQL query using dynamic field list from FieldSet (lines 60-67)
- Single DML statement for bulk updates (line 171)
- No SOQL or DML in loops

**Error Handling:** PASS
- Catches and re-throws `AuraHandledException` (lines 98-100, 179-181)
- Wraps unexpected exceptions with user-friendly message (lines 101-105, 182-186)
- Validates null accountId with clear error message (lines 11-13)

**Date Handling:** PASS
- Handles string-to-Date conversion (line 148)
- Handles null and empty string to clear dates (lines 145-146)
- Uses `Date.valueOf()` for proper conversion

### Apex Test Class: `/force-app/main/default/classes/FacilityEditorControllerTest.cls`

**Test Quality:** PASS (with caveat)
- Uses `@TestSetup` with 250 records (bulk testing) (lines 4-35)
- Tests positive, negative, and edge cases
- Tests for null accountId, empty list, invalid JSON
- Tests boolean field conversion (string and native)
- Tests date field conversion, clearing, and bulk updates
- Assertions include descriptive messages

**Coverage:** 86%

**Test Failures:** 7 tests failing due to FLS configuration issue (see Known Issues)

### LWC Component: `/force-app/main/default/lwc/facilityEditor/`

**facilityEditor.js:**
- PROGRAM_CONFIG properly defines all 7 programs with checkbox, launchDate, onHoldDate mappings (lines 7-15)
- `getEnabledProgramsForRow()` correctly filters programs based on checkbox value (lines 557-572)
- `handleProgramDateChange()` handles date input changes (lines 582-594)
- `handleFieldChange()` clears dates when program is unchecked (lines 354-360)
- Bulk edit shows warning for skipped facilities (lines 319-323)

**facilityEditor.html:**
- Expandable row pattern implemented with chevron toggle (lines 128-141)
- Program dates grid renders with proper structure (lines 206-237)
- Date inputs use `type="date"` for proper browser handling

**facilityEditor.css:**
- Proper styling for expanded detail row (lines 231-266)
- Responsive grid layout for program dates (lines 305-324)
- Animation for expand/collapse (lines 289-303)

### Field Metadata

All 14 fields confirmed present with correct configuration:
- CCM_Launch_Date__c, CCM_On_Hold_Date__c
- RPM_Launch_Date__c, RPM_On_Hold_Date__c
- TCM_Launch_Date__c, TCM_On_Hold_Date__c
- COCM_Launch_Date__c, COCM_On_Hold_Date__c
- AHTH_Launch_Date__c, AHTH_On_Hold_Date__c
- APCM_Launch_Date__c, APCM_On_Hold_Date__c
- BHI_Launch_Date__c, BHI_On_Hold_Date__c

All fields are of type `Date`, not required, with proper labels.

---

## Test Results

```
Test Run Summary:
- Total Tests: 28
- Passing: 21 (75%)
- Failing: 7 (25%)
- Coverage: 86% (exceeds 75% minimum)
```

### Failing Tests (All FLS-Related)

| Test Method | Failure Reason |
|-------------|----------------|
| testUpdateFacilities_DateFieldAsString | Date field stripped by Security.stripInaccessible |
| testUpdateFacilities_DateFieldToNull | Date field update stripped |
| testUpdateFacilities_DateFieldEmptyString | Date field update stripped |
| testUpdateFacilities_MultipleDateFields | Date fields stripped |
| testUpdateFacilities_BulkDateUpdates | Date fields stripped |
| testUpdateFacilities_AllProgramDates | All date fields stripped |
| testUpdateFacilities_DateAndBooleanMixed | Date fields stripped (booleans work) |

**Root Cause:** The new date fields are deployed to the org, but the running test user does not have Field-Level Security (FLS) edit access to them. `Security.stripInaccessible()` correctly strips fields the user cannot update.

**Resolution Required:** Grant FLS Edit access to the 14 new date fields on the appropriate Profile or Permission Set for users who will use the Facility Editor.

---

## Known Issues

### Issue 1: FLS Access for New Date Fields

**Severity:** Medium (Configuration, not Code)

**Description:** The 14 new program date fields are deployed but users do not have FLS edit access. This causes:
1. Test failures where date updates are stripped
2. Production users will not be able to save date values until FLS is configured

**Fix Required:**
1. Update the Profile(s) or Permission Set(s) used by Facility Editor users to grant Edit access to:
   - CCM_Launch_Date__c, CCM_On_Hold_Date__c
   - RPM_Launch_Date__c, RPM_On_Hold_Date__c
   - TCM_Launch_Date__c, TCM_On_Hold_Date__c
   - COCM_Launch_Date__c, COCM_On_Hold_Date__c
   - AHTH_Launch_Date__c, AHTH_On_Hold_Date__c
   - APCM_Launch_Date__c, APCM_On_Hold_Date__c
   - BHI_Launch_Date__c, BHI_On_Hold_Date__c

2. Re-run tests after FLS is configured

---

## Code Quality Checklist

| Category | Check | Status |
|----------|-------|--------|
| **Security** | with sharing | PASS |
| | FLS enforcement | PASS |
| | SOQL injection prevention | PASS |
| | No hardcoded credentials | PASS |
| **Performance** | No SOQL in loops | PASS |
| | No DML in loops | PASS |
| | Bulkified operations | PASS |
| **Test Quality** | @testSetup used | PASS |
| | 200+ record bulk test | PASS |
| | Positive/negative/edge tests | PASS |
| | Descriptive assertion messages | PASS |
| | Coverage >= 75% | PASS (86%) |
| **Best Practices** | Descriptive naming | PASS |
| | Error handling | PASS |
| | Comments for complex logic | PASS |
| **LWC** | Proper reactivity | PASS |
| | Event handling | PASS |
| | Accessibility (labels) | PASS |

---

## Recommendations

1. **Create Permission Set for Date Field Access**
   Consider creating a Permission Set specifically for Facility Editor users that grants access to all 14 program date fields. This is cleaner than modifying profiles directly.

2. **Add Field Metadata to Field Set**
   If users need to see/edit date fields in the main table (not just expanded row), add them to the `Facility_LWC` field set on the Facility__c object.

3. **Consider Date Validation**
   Add validation to ensure On Hold Date is not before Launch Date (if business logic requires this).

---

## Conclusion

**Final Status: CONDITIONAL PASS**

The code implementation is correct and follows all Salesforce best practices for security, performance, and test coverage. The 7 failing tests are due to an expected FLS enforcement behavior - the new date fields need to have Edit access granted to users.

**Action Required Before Production:**
1. Configure FLS for the 14 new date fields
2. Re-run tests to confirm 100% pass rate
3. Deploy with validated FLS configuration

---

## Appendix: Files Modified

| File | Type | Changes |
|------|------|---------|
| FacilityEditorController.cls | Apex | Added Date field type handling |
| FacilityEditorControllerTest.cls | Apex Test | Added 7 date-related test methods |
| facilityEditor.js | LWC JS | Added PROGRAM_CONFIG, expand/collapse, date handling |
| facilityEditor.html | LWC HTML | Added expandable row detail UI |
| facilityEditor.css | LWC CSS | Added styling for program date cards |
| *_Launch_Date__c.field-meta.xml (7) | Field | New date fields |
| *_On_Hold_Date__c.field-meta.xml (7) | Field | New date fields |
