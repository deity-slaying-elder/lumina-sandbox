# Technical Context

## Salesforce Org
- **Dev Org:** [To be filled - run `sf org list` to find aliases]
- **API Version:** 65.0

## Key Objects
| Object | Purpose |
|--------|---------|
| Patient__c | Core patient records |
| Encounter__c | Patient encounters/visits |
| Facility__c | Healthcare facilities |
| Agency__c | Partner agencies |
| Physician__c | Healthcare providers |
| Insurance__c | Insurance records |
| Insurance_Authorization__c | Auth tracking |
| Admission_Discharge__c | Hospital admissions |
| Equipment__c | Medical equipment |
| Equipment_Order__c | Equipment orders |
| ICD_10__c | Diagnosis codes |
| Procedure__c | Medical procedures |
| Community_Episode__c | Community care episodes |
| Hospice__c | Hospice care tracking |
| ISNP__c | Institutional SNP records |

## Integrations
| System | Purpose | Auth Method |
|--------|---------|-------------|
| Thoroughcare | Patient sync | Named Credential (verify) |
| Gehrimed | File uploads | [To be filled] |

## Technical Constraints
- No @future in triggers - use Queueable
- All queries must be bulkified
- Security: Always use `with sharing`
- Round robin assignment uses Public Groups

## Environment Notes
- Uses DLRS (Declarative Lookup Rollup Summaries)
- Custom metadata for API configuration (API_Configration__mdt)
