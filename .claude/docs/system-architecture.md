# System Architecture

## Component Inventory

### Apex Classes (33 total)

#### Controllers
| Class | Purpose | Lines |
|-------|---------|-------|
| BulkOpportunityCreatorController | Bulk opportunity creation | [scan] |
| BulkOpportunityEditorController | Bulk opportunity editing | [scan] |
| FacilityEditorController | Facility management | [scan] |
| ThoroughcareCreateController | Thoroughcare integration | [scan] |
| UploadConsentFileController | Consent file uploads | [scan] |
| UploadGehrimedFileController | Gehrimed file uploads | [scan] |
| UploadLongevityFileController | Longevity file uploads | [scan] |
| UserLogin | User authentication | [scan] |

#### Trigger Handlers
| Class | Trigger | Purpose |
|-------|---------|---------|
| PatientTriggerHandler | PatientTrigger | Patient record automation |
| OpportunityTriggerHandler | OpportunityTrigger | Opportunity automation |

#### Services/Utilities
| Class | Purpose |
|-------|---------|
| RoundRobinAssignmentWithPublicGroup | TCM assignment via public groups |
| roundRobinAssigner | Round robin logic |
| EnvironmentMetadataSelector | Environment metadata queries |

#### Callouts
| Class | External System | Purpose |
|-------|-----------------|---------|
| PatientThoroughcareCreateCallout | Thoroughcare | Patient sync |
| SendPatientIdToThoroughCare | Thoroughcare | ID transmission |

#### Test Classes
| Class | Tests |
|-------|-------|
| BulkOpportunityCreatorControllerTest | BulkOpportunityCreatorController |
| BulkOpportunityEditorControllerTest | BulkOpportunityEditorController |
| FacilityEditorControllerTest | FacilityEditorController |
| OpportunityTriggerHandlerTest | OpportunityTriggerHandler |
| PatientTriggerHandlerTest | PatientTriggerHandler |
| PatientThoroughcareCreateCalloutTest | PatientThoroughcareCreateCallout |
| RoundRobinAssignmentWithPublicGroupTest | RoundRobinAssignmentWithPublicGroup |
| SendPatientIdToThoroughCareTest | SendPatientIdToThoroughCare |
| TestPatientTriggerAndService | Patient trigger/service |
| UploadConsentFileCOntrollerTest | UploadConsentFileController |
| UploadGehrimedFileCOntrollerTest | UploadGehrimedFileController |
| UploadLongevityFileControllerTest | UploadLongevityFileController |
| UserLoginTest | UserLogin |
| roundRobinTests | roundRobinAssigner |
| dlrs_Opportunity_FacilityTest | DLRS trigger |
| dlrs_TaskTest | DLRS trigger |
| dlrs_VisitTest | DLRS trigger |

#### Mock Classes
| Class | Purpose |
|-------|---------|
| MockHttpCallout | HTTP callout mocking |
| MockHttpResponseGenerator | HTTP response generation |

### Lightning Web Components (3 total)
| Component | Purpose |
|-----------|---------|
| bulkOpportunityCreatorModal | Modal for bulk opportunity creation |
| bulkOpportunityEditor | Inline editing for opportunities |
| facilityEditor | Facility record management |

### Triggers (7 total)
| Trigger | Object | Handler |
|---------|--------|---------|
| PatientTrigger | Patient__c | PatientTriggerHandler |
| OpportunityTrigger | Opportunity | OpportunityTriggerHandler |
| PatientThoroughcareCreateTrigger | Patient__c | PatientThoroughcareCreateCallout |
| ThoroughcareTriggerController | [verify] | ThoroughcareCreateController |
| dlrs_Opportunity_FacilityTrigger | Opportunity_Facility__c | DLRS |
| dlrs_TaskTrigger | Task | DLRS |
| dlrs_VisitTrigger | Visit__c | DLRS |

## Object Model

### Core Objects
```
Patient__c
├── Patient_Facility__c (junction)
├── Patient_Insurance__c (junction)
├── Patient_ICD_10__c (junction)
├── Encounter__c
│   ├── Encounter_Diagnosis__c
│   └── Encounter_Service__c
├── Hospital_Admission__c
├── Admission_Discharge__c
└── Equipment_Order__c
```

### Facility Objects
```
Facility__c
├── Facility_Alias__c
├── Facility_Mapper__c
├── Region_Facility__c
├── FEU_Facility__c
└── Opportunity_Facility__c
```

### User/Access Objects
```
Front_End_User__c
├── FE_User_Role__c
├── Agency_Front_End_User__c
└── Agency_AFE_User__c

Agency__c
├── Agency_Front_End_User__c
└── Community_Provider__c
```

### Reference Data
```
ICD_10__c (diagnosis codes)
Procedure__c (medical procedures)
Insurance__c
├── Payer_Alias__c
├── Payer_Verification__c
└── Physician_Insurance__c
```

## Integration Architecture

### Thoroughcare Integration
- **Direction:** Salesforce → Thoroughcare
- **Trigger:** Patient__c insert/update
- **Classes:** PatientThoroughcareCreateCallout, SendPatientIdToThoroughCare
- **Auth:** [To be filled - check Named Credentials]
- **Pattern:** Queueable callout from trigger

### Gehrimed Integration
- **Direction:** File upload
- **Classes:** UploadGehrimedFileController
- **Storage:** Gehrimed_File__c

## Data Flow

### Patient Creation Flow
1. Patient__c record created
2. PatientTrigger fires → PatientTriggerHandler
3. PatientThoroughcareCreateTrigger → Queueable callout
4. Patient synced to Thoroughcare

### Opportunity Assignment Flow
1. Opportunity created
2. OpportunityTrigger → OpportunityTriggerHandler
3. RoundRobinAssignmentWithPublicGroup assigns TCM

## Custom Metadata
| Metadata Type | Purpose |
|---------------|---------|
| API_Configration__mdt | API endpoint configuration |
| In_App_Checklist_Settings__c | Checklist configuration |
| LastAssignedTCM__c | Round robin state |
