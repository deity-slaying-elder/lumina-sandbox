/**
 * Bypass check and recursion guard shared by the converted TCM triggers.
 *
 * BYPASS
 * ------
 * Backed by `Trigger_Bypass__mdt`, one record per trigger, keyed on DeveloperName.
 * Tick `Is_Bypassed__c` in Setup (Custom Metadata Types > Trigger Bypass > Manage
 * Records) and that trigger stops doing work on the next save. No deploy.
 * The `All_Triggers` record is the org-wide lever for an incident.
 *
 * Every record ships `false`. Custom metadata records deploy between orgs, so a
 * record left `true` in a sandbox would ride a deploy into production and silently
 * disable automation. Flip them in Setup, never in the repo.
 *
 * Custom metadata cannot be inserted in an Apex test and is org-wide only, so
 * `bypass()` / `clearBypass()` provide a transaction-scoped override. That covers
 * the two cases the metadata cannot: a test proving the trigger is what did the
 * work, and a batch or data-load job skipping automation for its own run only.
 *
 * RECURSION
 * ---------
 * Guarded per key, never with one shared flag. An after-save trigger that updates
 * its own records re-enters, and a single global `processed` set would let the
 * first feature silently suppress a second, legitimate pass.
 */
public with sharing class TriggerContext {

    /** Org-wide kill switch record. Checked before any per-trigger record. */
    private static final String ALL_TRIGGERS = 'All_Triggers';

    /** Transaction-scoped overrides for tests and batch jobs. Never persisted. */
    private static final Set<String> RUNTIME_BYPASS = new Set<String>();

    /** Ids already handled, keyed by feature. Claimed via Set.add() as an atomic test-and-set. */
    private static final Map<String, Set<Id>> CLAIMED = new Map<String, Set<Id>>();

    /**
     * True when this trigger should not run.
     *
     * @param triggerName DeveloperName of the Trigger_Bypass__mdt record,
     *                    which is also the trigger's own name, e.g. 'VisitTrigger'
     */
    public static Boolean isBypassed(String triggerName) {
        // Runtime override wins, so a test or a batch job does not depend on org config.
        if (RUNTIME_BYPASS.contains(ALL_TRIGGERS) || RUNTIME_BYPASS.contains(triggerName)) {
            return true;
        }
        // getInstance() reads the metadata cache. It is not a SOQL query and does
        // not count against limits, so there is nothing to gain by caching it here.
        if (isRecordBypassed(ALL_TRIGGERS)) {
            return true;
        }
        return isRecordBypassed(triggerName);
    }

    private static Boolean isRecordBypassed(String developerName) {
        Trigger_Bypass__mdt record = Trigger_Bypass__mdt.getInstance(developerName);
        // A missing record means "not bypassed". Adding a trigger without adding its
        // record therefore fails safe: the trigger keeps running.
        return record != null && record.Is_Bypassed__c == true;
    }

    /** Skip a trigger for the rest of this transaction. Use 'All_Triggers' for everything. */
    public static void bypass(String triggerName) {
        RUNTIME_BYPASS.add(triggerName);
    }

    /** Undo a runtime bypass. */
    public static void clearBypass(String triggerName) {
        RUNTIME_BYPASS.remove(triggerName);
    }

    /**
     * Claims the ids this feature has not yet processed and returns them.
     * Ids already claimed under the same key are filtered out, so a re-entrant
     * save is a no-op rather than an infinite loop.
     */
    public static Set<Id> claimUnprocessed(String key, Set<Id> candidateIds) {
        if (!CLAIMED.containsKey(key)) {
            CLAIMED.put(key, new Set<Id>());
        }
        Set<Id> alreadyDone = CLAIMED.get(key);

        Set<Id> fresh = new Set<Id>();
        for (Id candidate : candidateIds) {
            // Set.add() returns false when the id was already present, which makes
            // this a test-and-set in one operation rather than a contains/add pair.
            if (alreadyDone.add(candidate)) {
                fresh.add(candidate);
            }
        }
        return fresh;
    }

    /** Test-only reset so one test method's state does not leak into the next. */
    @TestVisible
    private static void reset() {
        CLAIMED.clear();
        RUNTIME_BYPASS.clear();
    }
}
