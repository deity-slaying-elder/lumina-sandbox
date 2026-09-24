/**
 * Constants shared by the converted TCM trigger actions.
 *
 * RECLAIM OWNER
 * -------------
 * Two flows hardcode the same user Id as the owner a patient is handed back to:
 * `Admission_Discharge_TF_On_Create_Create_Community_Episode` and
 * `Patient_TF_On_Update_Set_Community_Status_For_Discharge`. In production that Id
 * belongs to the System Administrator account, and it is the reason roughly three
 * quarters of all patients sit under that one user - a patient with no call outcome
 * for 30 days is reclaimed from whoever held it.
 *
 * The Id is kept here rather than in each action because a hardcoded Id does not
 * survive a move between orgs: deploy the Apex to a sandbox and the assignment
 * fails on an Id that does not exist there. One constant means one edit.
 *
 * This should become a Custom Metadata setting so it can be changed without a
 * deploy. It is a constant for now only because new custom metadata records cannot
 * currently be inserted into this org by a metadata deploy.
 */
public with sharing class TcmSettings {

    /** System Administrator in lumProd. Patients with no recent contact return here. */
    private static final Id RECLAIM_OWNER_ID = '005Hr00000GbQozIAF';

    /** Test override, so a test does not depend on that user existing in the org. */
    @TestVisible
    private static Id reclaimOwnerOverride;

    /**
     * Test override for the opposite case: the configured user does NOT exist here.
     * Needed because in this sandbox the configured user genuinely exists AND is the
     * user running the tests, so "owner unchanged" would otherwise pass vacuously.
     */
    @TestVisible
    private static Boolean forceNoReclaimOwner = false;

    /**
     * Owner a stale patient is reassigned to.
     *
     * Returns null when the configured user is absent or inactive in this org, and
     * every caller treats null as "leave the owner alone". Silently keeping the
     * current owner is the safe failure: the alternative is INVALID_CROSS_REFERENCE_KEY
     * rolling back the whole save, including the episode the patient needs.
     */
    public static Id reclaimOwnerId() {
        if (forceNoReclaimOwner) {
            return null;
        }
        if (reclaimOwnerOverride != null) {
            return reclaimOwnerOverride;
        }
        List<User> owners = [SELECT Id FROM User WHERE Id = :RECLAIM_OWNER_ID AND IsActive = TRUE LIMIT 1];
        return owners.isEmpty() ? null : owners[0].Id;
    }
}
