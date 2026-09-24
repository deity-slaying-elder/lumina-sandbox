/**
 * Trigger action: text a patient discharged home, if their region is in scope.
 *
 * Apex port of the flow Discharge_TF_Send_SMS, production version 10.
 *
 * This is TCM interactive-contact work. CPT 99495 and 99496 both require contact
 * within two business days of discharge, so this message is billing-relevant.
 *
 * Flow behaviour, preserved exactly. The flow is a chain of gates and stops at the
 * first one that fails:
 *
 *   entry - Admission/Discharge CREATED (not updated), Type__c = 'Discharge'
 *   1. dischargedHome is true AND Patient.No_Texts__c is false
 *   2. textLast2Days is FALSE  (see the defect note - the name is backwards)
 *   3. the patient's facility's parent company routes to a region check:
 *        name contains 'GHC'           -> region must be MD, DE or NJ
 *        name contains 'Complete Care' -> region must be PA or NJ
 *        name contains 'Infinity'      -> region must be IL, checked inline
 *        anything else                 -> stop
 *      Rules are evaluated in that order and the first match wins, as in the flow.
 *   4. a phone number resolves from the patient
 *   then  - send the SMS, and only if that succeeded, stamp
 *           Patient.Last_SMS_Sent_Date__c with the current time
 *
 * The stamp is deliberately after the send, because the flow's connector ran in that
 * order. A failed send leaves the timestamp alone, so the patient stays eligible.
 *
 * WHY THIS IS ASYNCHRONOUS AND THE FLOW WAS NOT
 * --------------------------------------------
 * Sending is an HTTP callout to Twilio. Apex cannot make a callout in the same
 * transaction as a trigger, so the send is handed to DischargeSendSmsQueueable. The
 * decision tree still runs synchronously, so what gets sent and to whom is decided at
 * exactly the point the flow decided it; only the delivery moves. That is the one
 * intended behaviour change in this port and it needs to be signed off, not assumed.
 *
 * TWO FLOW DEFECTS REPRODUCED DELIBERATELY, NOT FIXED
 * --------------------------------------------------
 * A port that also changes output cannot be verified against the flow it replaces, so
 * both are carried forward and raised as their own bugs.
 *
 *  1. The recency test is inverted. The flow's formula is
 *     `today() - datevalue(Last_SMS_Sent_Date__c) > 3`, which is TRUE when the patient
 *     has NOT been texted recently - and the branch that matches TRUE has no connector,
 *     so it stops. The default branch, meaning texted within the last three days,
 *     continues and sends. So patients texted in the last three days get texted again,
 *     and patients not contacted for longer are skipped. Backwards, on the TCM contact
 *     path. Preserved here as `!textedMoreThanThreeDaysAgo`.
 *     A blank Last_SMS_Sent_Date__c makes the formula null, which the decision read as
 *     false, so a never-texted patient continues and is sent to. That is correct
 *     behaviour arriving by accident, and it is preserved.
 *  2. 'Deleware' is misspelled in the MD/DE/NJ state list, so records carrying
 *     Delaware spelled out never match. Preserved, misspelling included, alongside the
 *     correct spelling being absent.
 *
 * A third defect from the original audit turned out not to exist in production: the
 * dischargedHome formula is correctly parenthesised there and gated on
 * Type__c = 'Discharge'. Only the sandbox had the broken version. Nothing to reproduce.
 *
 * Registered in Trigger_Action__mdt for the After Insert context on
 * Admission_Discharge__c. Deactivate by ticking Bypass Execution
 * on that record in Setup - the framework reads it live - or at runtime with
 * MetadataTriggerHandler.bypass in a test or batch job.
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
public without sharing class DischargeSendSms implements TriggerAction.AfterInsert {

    private static final String TYPE_DISCHARGE = 'Discharge';

    /** Flow's textLast2Days threshold, in days, despite what the name says. */
    private static final Integer SMS_RECENCY_DAYS = 3;

    /** The flow's smsTemplate text template, reproduced verbatim including the en dash. */
    @TestVisible
    private static final String SMS_TEMPLATE =
        'Hi, this is the Lumina Care Team. You were recently discharged. Please expect a call '
        + 'within 24–48 hours to schedule a telehealth follow-up with your provider. If you '
        + 'have any questions, feel free to call us at (929) 650-3990.';

    /** dischargedHome: any of these in To_From_Type__c qualifies. */
    private static final List<String> DISCHARGED_HOME_TERMS =
        new List<String>{ 'home', 'alf', 'assisted' };

    /** dischargedHome: any of these disqualifies, even if a term above matched. */
    private static final List<String> DISCHARGED_HOME_EXCLUSIONS =
        new List<String>{ 'funeral', 'nursing', 'hospice' };

    /** MDDENJ. 'Deleware' is the flow's misspelling and is intentional - see the notes. */
    private static final Set<String> STATES_MD_DE_NJ =
        new Set<String>{ 'NJ', 'MD', 'DE', 'New Jersey', 'Maryland', 'Deleware' };

    /** PANJ. */
    private static final Set<String> STATES_PA_NJ =
        new Set<String>{ 'NJ', 'PA', 'New Jersey', 'Pennsylvania' };

    /** IL. */
    private static final Set<String> STATES_IL = new Set<String>{ 'IL', 'Illinois' };

    public void afterInsert(List<SObject> triggerNew) {
        sendDischargeMessages((List<Admission_Discharge__c>) triggerNew);
    }

    private void sendDischargeMessages(List<Admission_Discharge__c> newRecords) {

        Set<Id> dischargeIds = new Set<Id>();
        for (Admission_Discharge__c record : newRecords) {
            if (TYPE_DISCHARGE.equals(record.Type__c)) {
                dischargeIds.add(record.Id);
            }
        }
        if (dischargeIds.isEmpty()) {
            return;
        }

        // Everything the gates need, in one query. The flow read these as cross-object
        // references per interview; this is the same data fetched once.
        List<Admission_Discharge__c> discharges = [
            SELECT Id, Type__c, To_From_Type__c, Patient__c,
                   Patient__r.No_Texts__c, Patient__r.Facility_State__c,
                   Patient__r.Last_SMS_Sent_Date__c,
                   Patient__r.Phone_Number__c, Patient__r.Mobile_Number__c,
                   Patient__r.Main_Phone_Number__c, Patient__r.Phone_1__c,
                   Patient__r.Phone_2__c, Patient__r.Phone_3__c,
                   Patient__r.Facility__r.Parent_Company__r.Name
            FROM Admission_Discharge__c
            WHERE Id IN :dischargeIds
        ];

        Date today = Date.today();
        List<DischargeSendSmsQueueable.Message> messages =
            new List<DischargeSendSmsQueueable.Message>();

        for (Admission_Discharge__c discharge : discharges) {
            Patient__c patient = discharge.Patient__r;
            if (patient == null) {
                continue;
            }

            // Gate 1 - If_Discharged_Home.
            if (!isDischargedHome(discharge) || patient.No_Texts__c == true) {
                continue;
            }
            // Gate 2 - If_Text_Sent_Within_2_Days. Inverted in the flow; see the notes.
            if (textedMoreThanThreeDaysAgo(patient.Last_SMS_Sent_Date__c, today)) {
                continue;
            }
            // Gate 3 - If_GHC and the region check it routes to.
            if (!isRegionInScope(patient)) {
                continue;
            }
            // Gate 4 - If_No_Phone_Number.
            String phoneNumber = resolvePhoneNumber(patient);
            if (String.isBlank(phoneNumber)) {
                continue;
            }

            messages.add(new DischargeSendSmsQueueable.Message(
                discharge.Patient__c, phoneNumber, SMS_TEMPLATE
            ));
        }

        if (messages.isEmpty()) {
            return;
        }

        // Chunked so one job never exceeds the callout allowance for a transaction.
        // The binding limit is the 120 second total callout time, not the count, so the
        // chunk is deliberately well below the hundred-callout ceiling.
        for (Integer start = 0; start < messages.size(); start += DischargeSendSmsQueueable.CHUNK_SIZE) {
            Integer stop = Math.min(start + DischargeSendSmsQueueable.CHUNK_SIZE, messages.size());
            List<DischargeSendSmsQueueable.Message> chunk =
                new List<DischargeSendSmsQueueable.Message>();
            for (Integer i = start; i < stop; i++) {
                chunk.add(messages[i]);
            }
            System.enqueueJob(new DischargeSendSmsQueueable(chunk));
        }
    }

    /**
     * dischargedHome. Type must be Discharge, To_From_Type__c must contain one of the
     * home-like terms, and must contain none of the exclusions. Comparison is on
     * LOWER(TRIM(...)) exactly as the formula does.
     */
    @TestVisible
    private static Boolean isDischargedHome(Admission_Discharge__c discharge) {
        if (!TYPE_DISCHARGE.equals(discharge.Type__c)) {
            return false;
        }
        if (discharge.To_From_Type__c == null) {
            return false;
        }
        String toFrom = discharge.To_From_Type__c.trim().toLowerCase();

        Boolean matchesHome = false;
        for (String term : DISCHARGED_HOME_TERMS) {
            if (toFrom.contains(term)) {
                matchesHome = true;
                break;
            }
        }
        if (!matchesHome) {
            return false;
        }
        for (String exclusion : DISCHARGED_HOME_EXCLUSIONS) {
            if (toFrom.contains(exclusion)) {
                return false;
            }
        }
        return true;
    }

    /**
     * textLast2Days. True when the last SMS was more than three days ago, which in the
     * flow is the branch that STOPS. A null timestamp makes the flow formula null, read
     * as false, so a never-texted patient continues - preserved here by returning false.
     *
     * datevalue() on a Datetime converts in GMT, so formatGmt is used rather than
     * Datetime.date(), which would use the running user's zone and shift the boundary.
     */
    @TestVisible
    private static Boolean textedMoreThanThreeDaysAgo(Datetime lastSms, Date today) {
        if (lastSms == null) {
            return false;
        }
        Date lastSmsDate = Date.valueOf(lastSms.formatGmt('yyyy-MM-dd'));
        return lastSmsDate.daysBetween(today) > SMS_RECENCY_DAYS;
    }

    /**
     * If_GHC, plus whichever region decision it routes to. The three rules are checked
     * in the flow's own order and the first match decides the outcome, including when
     * that outcome is a failing region check.
     */
    @TestVisible
    private static Boolean isRegionInScope(Patient__c patient) {
        String parentCompany;
        if (patient.Facility__r != null && patient.Facility__r.Parent_Company__r != null) {
            parentCompany = patient.Facility__r.Parent_Company__r.Name;
        }
        if (String.isBlank(parentCompany)) {
            return false;
        }
        String state = patient.Facility_State__c;

        if (parentCompany.contains('GHC')) {
            return STATES_MD_DE_NJ.contains(state);
        }
        if (parentCompany.contains('Complete Care')) {
            return STATES_PA_NJ.contains(state);
        }
        if (parentCompany.contains('Infinity')) {
            // The flow put the state test in the rule's own conditions rather than in a
            // following decision, so a non-Illinois Infinity facility falls through to
            // the default outcome and stops. Same result either way.
            return STATES_IL.contains(state);
        }
        return false;
    }

    /**
     * phoneNumber. First non-blank in the flow's order. Contains uses a case-sensitive
     * Set for the state checks above, but this is a straight blank test, so no case
     * concern applies.
     */
    @TestVisible
    private static String resolvePhoneNumber(Patient__c patient) {
        List<String> candidates = new List<String>{
            patient.Phone_Number__c,
            patient.Mobile_Number__c,
            patient.Main_Phone_Number__c,
            patient.Phone_1__c,
            patient.Phone_2__c,
            patient.Phone_3__c
        };
        for (String candidate : candidates) {
            if (String.isNotBlank(candidate)) {
                return candidate;
            }
        }
        return null;
    }
}
