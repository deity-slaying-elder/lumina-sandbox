/**
 * Trigger action: name the Admission/Discharge record and point the Patient's
 * Latest Admission / Latest Discharge lookup at it.
 *
 * Apex port of the flow Admission_Discharge_TF_On_Create_Set_Latest_A_D_on_Patient.
 * Despite "On Create" in its name the flow was CreateAndUpdate, so this runs on
 * both.
 *
 * Flow behaviour, preserved:
 *   1. Always set $Record.Name to
 *        LEFT(Patient.Name & " - " & TEXT(Type__c) & " - " & TEXT(DATEVALUE(Census_Date__c)), 80)
 *   2. If Type__c = 'Admission'
 *        set Patient.Latest_Admission__c = this record, when the patient has no
 *        latest admission OR this Census_Date__c is later than the current one.
 *      Otherwise (the flow's DEFAULT branch, so any value that is not
 *      'Admission', including blank)
 *        same test against Patient.Latest_Discharge__c.
 *
 * Two parity details that are easy to get wrong:
 *
 * - DATEVALUE() on a DateTime converts in GMT, while Apex Datetime.date() uses
 *   the running user's timezone. formatGmt('yyyy-MM-dd') reproduces the flow
 *   exactly and also matches TEXT(Date) which renders ISO, not locale.
 * - The discharge branch is the flow's default, NOT a test for
 *   Type__c = 'Discharge'. A blank or unexpected Type therefore lands on the
 *   discharge branch in both implementations.
 *
 * Bulk. The flow ran one interview per record, so a second record for the same
 * patient saw the first interview's write. The pending patient state is carried
 * forward in memory here to reproduce that, otherwise two admissions saved
 * together would both compare against the pre-save value and the later one
 * could lose.
 *
 * Cost. The flow did one Name update plus up to one Patient update PER record.
 * This does one of each for the whole save.
 *
 * Registered for After Insert and After Update on Admission_Discharge__c.
 *
 * SYSTEM MODE, DELIBERATELY. The flow this replaces ran in system context and wrote
 * what it needed regardless of who saved the record. Running-user enforcement here
 * (WITH USER_MODE, stripInaccessible) makes the same save silently drop writes for
 * lower-privilege profiles - in production, Lumina Manager No Edit Access can create
 * discharges without Patient edit, and Latest_Community_Episode__c carries no field
 * permissions for anyone - and a silently dropped TCM timestamp is a billing defect
 * nobody sees. Automation runs as the system, exactly as the flow did. User-facing
 * controllers are different and keep user-mode enforcement.
 */
public without sharing class AdmissionDischargeSetLatest implements TriggerAction.AfterInsert, TriggerAction.AfterUpdate {

    private static final String GUARD_KEY = 'AdmissionDischarge.setLatest';
    private static final String TYPE_ADMISSION = 'Admission';
    private static final Integer NAME_MAX = 80;

    public void afterInsert(List<SObject> triggerNew) {
        run((List<Admission_Discharge__c>) triggerNew);
    }

    public void afterUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        run((List<Admission_Discharge__c>) triggerNew);
    }

    private void run(List<Admission_Discharge__c> records) {

        Set<Id> candidateIds = new Set<Id>();
        for (Admission_Discharge__c rec : records) {
            candidateIds.add(rec.Id);
        }

        // This action writes its own object (the Name), so it re-enters. Guard it.
        candidateIds = TriggerContext.claimUnprocessed(GUARD_KEY, candidateIds);
        if (candidateIds.isEmpty()) {
            return;
        }

        // The trigger record carries neither Patient__r.Name nor the two Latest_*
        // lookups' Census_Date__c, so re-read what the decisions need.
        Map<Id, Admission_Discharge__c> loaded = new Map<Id, Admission_Discharge__c>([
            SELECT Id, Type__c, Census_Date__c, Name, Patient__c,
                   Patient__r.Name,
                   Patient__r.Latest_Admission__c, Patient__r.Latest_Admission__r.Census_Date__c,
                   Patient__r.Latest_Discharge__c, Patient__r.Latest_Discharge__r.Census_Date__c
            FROM Admission_Discharge__c
            WHERE Id IN :candidateIds
        ]);

        List<Admission_Discharge__c> nameUpdates = new List<Admission_Discharge__c>();
        Map<Id, Patient__c> patientUpdates = new Map<Id, Patient__c>();

        // Pending view of each patient's latest admission/discharge, seeded from the
        // query and advanced as the batch is walked.
        Map<Id, Datetime> pendingAdmissionDate = new Map<Id, Datetime>();
        Map<Id, Datetime> pendingDischargeDate = new Map<Id, Datetime>();
        Map<Id, Boolean> hasAdmission = new Map<Id, Boolean>();
        Map<Id, Boolean> hasDischarge = new Map<Id, Boolean>();

        for (Admission_Discharge__c rec : records) {
            Admission_Discharge__c full = loaded.get(rec.Id);
            if (full == null) {
                continue;
            }

            // ---- 1. Name, always recomputed. Only written when it actually changes,
            // which also stops the re-entrant save from doing a pointless DML.
            String patientName = full.Patient__r == null ? null : full.Patient__r.Name;
            String newName = buildName(patientName, full.Type__c, full.Census_Date__c);
            if (newName != full.Name) {
                nameUpdates.add(new Admission_Discharge__c(Id = full.Id, Name = newName));
            }

            // ---- 2. Point the patient at this record, if it is the later one.
            if (full.Patient__c == null || full.Census_Date__c == null) {
                continue;
            }
            Id patientId = full.Patient__c;

            if (!hasAdmission.containsKey(patientId)) {
                hasAdmission.put(patientId, full.Patient__r.Latest_Admission__c != null);
                hasDischarge.put(patientId, full.Patient__r.Latest_Discharge__c != null);
                pendingAdmissionDate.put(patientId,
                    full.Patient__r.Latest_Admission__r == null ? null : full.Patient__r.Latest_Admission__r.Census_Date__c);
                pendingDischargeDate.put(patientId,
                    full.Patient__r.Latest_Discharge__r == null ? null : full.Patient__r.Latest_Discharge__r.Census_Date__c);
            }

            Boolean isAdmission = full.Type__c == TYPE_ADMISSION;
            Boolean currentlyBlank = isAdmission ? !hasAdmission.get(patientId) : !hasDischarge.get(patientId);
            Datetime currentDate = isAdmission ? pendingAdmissionDate.get(patientId) : pendingDischargeDate.get(patientId);

            // The flow's GreaterThan against a null relationship field is false, so a
            // populated lookup whose Census_Date__c is null never gets replaced.
            Boolean isLater = currentDate != null && full.Census_Date__c > currentDate;

            if (!currentlyBlank && !isLater) {
                continue;
            }

            Patient__c pending = patientUpdates.get(patientId);
            if (pending == null) {
                pending = new Patient__c(Id = patientId);
                patientUpdates.put(patientId, pending);
            }

            if (isAdmission) {
                pending.Latest_Admission__c = full.Id;
                hasAdmission.put(patientId, true);
                pendingAdmissionDate.put(patientId, full.Census_Date__c);
            } else {
                pending.Latest_Discharge__c = full.Id;
                hasDischarge.put(patientId, true);
                pendingDischargeDate.put(patientId, full.Census_Date__c);
            }
        }

        if (!nameUpdates.isEmpty()) {
        update nameUpdates;
        }
        if (!patientUpdates.isEmpty()) {
            update patientUpdates.values();
        }
    }

    /**
     * Reproduces the flow formula:
     *   LEFT(Patient.Name & " - " & TEXT(Type__c) & " - " & TEXT(DATEVALUE(Census_Date__c)), 80)
     * A blank component concatenates as empty in a flow formula, so nulls become ''.
     */
    @TestVisible
    private static String buildName(String patientName, String type, Datetime censusDate) {
        String datePart = censusDate == null ? '' : censusDate.formatGmt('yyyy-MM-dd');
        String raw = (patientName == null ? '' : patientName)
            + ' - ' + (type == null ? '' : type)
            + ' - ' + datePart;
        return raw.length() > NAME_MAX ? raw.substring(0, NAME_MAX) : raw;
    }
}
