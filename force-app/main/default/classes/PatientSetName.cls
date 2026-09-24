/**
 * Trigger action: keep Patient Name as "First Last", truncated to 80.
 *
 * Apex port of THREE flows at once:
 *   Patient_TF_On_Create_Update_Name                       (create,  LEFT 80)
 *   Patient_TF_On_Update_Update_Name                       (update,  no LEFT - defect)
 *   Patient_TF_On_Update_of_First_or_Last_Name_Update_Name (update,  LEFT 80)
 *
 * The two update flows were an exact-duplicate pair with identical entry criteria and
 * one meaningful difference: one truncated to 80 characters and one did not, so a name
 * over 80 characters made the untruncated one throw STRING_TOO_LONG while the other
 * saved - and which ran last was undefined. This action replaces both with the
 * truncating behaviour, which is also what the create flow always did. That resolves
 * the nondeterminism in favour of the version that cannot fail. Named delta, signed
 * off by Chayim with the "convert them all" call.
 *
 * Before-save on purpose: the after-save originals spent a whole extra save pass per
 * record to write one field on themselves. Production already moved its Patient
 * self-write flows to before-save; this matches that direction.
 *
 * SYSTEM MODE, DELIBERATELY - see any TCM action header for the full rationale.
 *
 * Registered in Trigger_Action__mdt for Before Insert and Before Update on Patient__c.
 */
public without sharing class PatientSetName implements TriggerAction.BeforeInsert, TriggerAction.BeforeUpdate {

    public void beforeInsert(List<SObject> triggerNew) {
        for (Patient__c patient : (List<Patient__c>) triggerNew) {
            patient.Name = buildName(patient);
        }
    }

    public void beforeUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        Map<Id, Patient__c> oldById = new Map<Id, Patient__c>((List<Patient__c>) triggerOld);
        for (Patient__c patient : (List<Patient__c>) triggerNew) {
            Patient__c prior = oldById.get(patient.Id);
            // Flow entry criteria: first OR last name changed.
            if (prior != null
                && prior.First_Name__c == patient.First_Name__c
                && prior.Last_Name__c == patient.Last_Name__c) {
                continue;
            }
            patient.Name = buildName(patient);
        }
    }

    private static String buildName(Patient__c patient) {
        // Formula semantics: null concatenates as empty, then LEFT(..., 80).
        String name = (patient.First_Name__c == null ? '' : patient.First_Name__c)
            + ' '
            + (patient.Last_Name__c == null ? '' : patient.Last_Name__c);
        return name.left(80);
    }
}
