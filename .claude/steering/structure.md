# Code Structure

## File Organization
```
force-app/main/default/
├── classes/          # Apex classes (33 files)
├── lwc/              # Lightning Web Components (3 components)
├── triggers/         # Apex triggers (7 triggers)
├── objects/          # Custom objects (50+ objects)
└── pages/            # Visualforce pages
```

## Naming Conventions
| Type | Pattern | Example |
|------|---------|---------|
| Service | [Object]Service | PatientService.cls |
| Test | [Class]Test | PatientTriggerHandlerTest.cls |
| Trigger | [Object]Trigger | PatientTrigger.trigger |
| Handler | [Object]TriggerHandler | PatientTriggerHandler.cls |
| Controller | [Feature]Controller | FacilityEditorController.cls |
| LWC | camelCase | bulkOpportunityEditor |
| Callout | [Feature]Callout | PatientThoroughcareCreateCallout.cls |

## Code Patterns

### Trigger Pattern
Single trigger per object → Handler class
- PatientTrigger → PatientTriggerHandler
- OpportunityTrigger → OpportunityTriggerHandler

### Test Pattern
- @testSetup with 200+ records
- Positive, negative, edge, bulk tests
- Specific assertions with messages
- Governor limits assertions (Limits class)
- Use MockHttpCallout/MockHttpResponseGenerator for HTTP tests

### Security Pattern
- Always `with sharing`
- Use `Security.stripInaccessible()` before DML
- Use binding variables in SOQL (no string concat)

### Error Handling Pattern
- Use custom exceptions for business logic errors
- Never catch generic Exception without re-throwing
- Log errors before throwing
- Return user-friendly messages to LWC

### Callout Pattern
- Separate callout classes (e.g., PatientThoroughcareCreateCallout)
- Use MockHttpResponseGenerator for testing
- Handle in trigger via Queueable (not @future)

## LWC Components
| Component | Purpose |
|-----------|---------|
| bulkOpportunityCreatorModal | Bulk create opportunities |
| bulkOpportunityEditor | Edit opportunities in bulk |
| facilityEditor | Facility management UI |

## LWC Patterns

### Wire vs Imperative
- **Wire:** Use for read-only data that auto-refreshes
- **Imperative:** Use for DML operations or conditional calls

### Reactivity Pattern
- Tracked objects/arrays need new references for re-render
- Use spread operator: `this.data = { ...this.data, key: value }`
- Never mutate tracked properties directly

### Validation Pattern
- Always validate against `allData`, not `filteredData`
- Hidden rows (from search/filter) must still be validated
- Inline validation + on-save validation for best UX

### Computed Property Pattern
- Cache expensive getters with dirty flag
- Set `_isDirty = true` on data mutations
- Recompute only when dirty, then reset flag

### Modal Pattern
- Add Escape key handler in `connectedCallback`
- Remove listener in `disconnectedCallback`
- Include: `role="dialog"`, `aria-describedby`, backdrop

### Field Set Pattern
- When LWC hardcodes field API names, ensure backing field set includes ALL referenced fields
- Controller dynamically queries fields from field set - missing fields return undefined
- **Example:** `facilityEditor.js` PROGRAM_CONFIG references date fields → `Facility_LWC` field set must include them
- Check field set whenever LWC shows empty/missing data despite database having values

## Import/Dependency Rules
- Controllers call Services/Handlers, never direct SOQL
- Services are stateless, handle bulkification
- Handlers coordinate trigger logic
- LWC calls @AuraEnabled methods, never direct SOQL
- Callout classes handle external integrations

## DLRS Triggers
Auto-generated triggers for rollup summaries:
- dlrs_Opportunity_FacilityTrigger
- dlrs_TaskTrigger
- dlrs_VisitTrigger

Do not modify DLRS triggers directly - configure via DLRS app.
