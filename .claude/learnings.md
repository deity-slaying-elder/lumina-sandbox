# Project Learnings

Rolling log of recent discoveries. Entries older than 30 days are cleaned unless still relevant.
Patterns used 3+ times promote to steering docs.

---

## Promotion Candidates
Patterns that may be ready to promote to steering docs:
- (none yet - LWC patterns promoted to structure.md on 2026-01-13)

---

## Recent Learnings

### 2026-01-12 - Project Initialized
- **Context:** Initial Claude documentation setup via /setup-salesforce-project
- **Discovery:** Project has 50+ custom objects, 33 Apex classes, 3 LWC components, 7 triggers
- **Pattern:** Use /update-learnings after each task to maintain context
- **Note:** Several [To be filled] sections need manual completion in steering/product.md and docs/business-operations.md

### 2026-01-13 - LMNA-419 QA Review Passed
- **Context:** Pre-production QA review of facilityEditor LWC
- **Discovery:** Component passed all security, performance, and code quality checks
- **Result:** 28/28 tests passed, 86% code coverage, QA approved for production
- **QA Report:** `.claude/qa-reports/LMNA-419-facilityEditor-qa-report.md`

### 2026-01-13 - Always Deploy After Code Changes
- **Context:** User had to manually deploy after LWC changes were made
- **Discovery:** Code changes are not automatically deployed to the org
- **Pattern:** ALWAYS run `sf project deploy start` after completing code changes before reporting "done"
- **Avoid:** Telling user changes are complete without deploying to the target org

### 2026-01-14 - FacilityEditor Date Clearing Logic
- **Context:** User requested that unchecking program checkboxes should clear corresponding Launch Date and On Hold Date fields
- **Discovery:** Original logic reset dates to DB values instead of clearing them when programs were unchecked
- **Pattern:** When implementing "uncheck clears data" logic, use `field = null` instead of `field = originalValue || null`
- **Avoid:** Resetting to original values when user intent is to clear data
- **Files Modified:** facilityEditor.js (4 methods: handleToggleAllPrograms, handleSelectAllProgramsForAllRows, handleProgramToggle, handleApplyDates)
- **QA Report:** `.claude/qa-reports/2026-01-14-facilityEditor-date-clearing-qa.md`
