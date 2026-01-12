public with sharing class OpportunityTriggerHandler {

    /**
     * Before Insert Handler
     */
    public static void beforeInsert(List<Opportunity> newOpportunities) {
        preventDuplicateTypePerFacility(newOpportunities, null);
    }

    /**OpportunityTrigger
     * Before Update Handler
     */
    public static void beforeUpdate(List<Opportunity> newOpportunities, Map<Id, Opportunity> oldOpportunitiesMap) {
        preventDuplicateTypePerFacility(newOpportunities, oldOpportunitiesMap);
    }

    /**
     * Prevents duplicate Opportunity Types for the same Account + Facility combination
     * when an open (non-closed) opportunity of that type already exists.
     * Allows duplicates if all existing opportunities of that type are closed.
     */
    private static void preventDuplicateTypePerFacility(List<Opportunity> newOpportunities, Map<Id, Opportunity> oldOpportunitiesMap) {
        // Get closed stages
        Set<String> closedStages = getClosedStages();

        // Collect Account + Facility + Type combinations to check
        Set<String> accountFacilityTypeCombos = new Set<String>();
        Map<String, Opportunity> comboToOpportunityMap = new Map<String, Opportunity>();

        for (Opportunity opp : newOpportunities) {
            // Skip if no Type or Facility
            if (String.isBlank(opp.Type) || opp.Facility__c == null) {
                continue;
            }

            // For updates, only check if Type, Facility, or Account changed
            if (oldOpportunitiesMap != null) {
                Opportunity oldOpp = oldOpportunitiesMap.get(opp.Id);
                if (opp.Type == oldOpp.Type &&
                    opp.Facility__c == oldOpp.Facility__c &&
                    opp.AccountId == oldOpp.AccountId) {
                    continue; // No relevant changes, skip validation
                }
            }

            // Build unique key: AccountId + FacilityId + Type
            String comboKey = String.valueOf(opp.AccountId) + '_' +
                             String.valueOf(opp.Facility__c) + '_' +
                             opp.Type;
            accountFacilityTypeCombos.add(comboKey);
            comboToOpportunityMap.put(comboKey, opp);
        }

        // If nothing to check, exit early
        if (accountFacilityTypeCombos.isEmpty()) {
            return;
        }

        // Build sets for querying
        Set<Id> accountIds = new Set<Id>();
        Set<Id> facilityIds = new Set<Id>();
        Set<String> types = new Set<String>();

        for (Opportunity opp : comboToOpportunityMap.values()) {
            accountIds.add(opp.AccountId);
            facilityIds.add(opp.Facility__c);
            types.add(opp.Type);
        }

        // Query existing opportunities with the same Account + Facility + Type
        List<Opportunity> existingOpps = [
            SELECT Id, AccountId, Facility__c, Type, StageName
            FROM Opportunity
            WHERE AccountId IN :accountIds
            AND Facility__c IN :facilityIds
            AND Type IN :types
            AND Id NOT IN :comboToOpportunityMap.keySet()
        ];

        // Group existing opportunities by combo key
        Map<String, List<Opportunity>> comboToExistingOpps = new Map<String, List<Opportunity>>();
        for (Opportunity existingOpp : existingOpps) {
            String comboKey = String.valueOf(existingOpp.AccountId) + '_' +
                             String.valueOf(existingOpp.Facility__c) + '_' +
                             existingOpp.Type;

            if (!comboToExistingOpps.containsKey(comboKey)) {
                comboToExistingOpps.put(comboKey, new List<Opportunity>());
            }
            comboToExistingOpps.get(comboKey).add(existingOpp);
        }

        // Check for duplicates and add errors
        for (String comboKey : comboToOpportunityMap.keySet()) {
            Opportunity newOpp = comboToOpportunityMap.get(comboKey);

            if (comboToExistingOpps.containsKey(comboKey)) {
                List<Opportunity> existingOppsForCombo = comboToExistingOpps.get(comboKey);

                // Check if any existing opportunity is NOT closed
                Boolean hasOpenOpportunity = false;
                for (Opportunity existingOpp : existingOppsForCombo) {
                    if (!closedStages.contains(existingOpp.StageName)) {
                        hasOpenOpportunity = true;
                        break;
                    }
                }

                // If there's an open opportunity, prevent the duplicate
                if (hasOpenOpportunity) {
                    newOpp.addError('An open opportunity of type "' + newOpp.Type +
                                   '" already exists for this Account and Facility. ' +
                                   'Please close or update the existing opportunity instead.');
                }
            }
        }
    }

    /**
     * Gets all closed stage names from OpportunityStage
     */
    private static Set<String> getClosedStages() {
        Set<String> closedStages = new Set<String>();

        for (OpportunityStage stage : [SELECT MasterLabel FROM OpportunityStage WHERE IsClosed = true]) {
            closedStages.add(stage.MasterLabel);
        }

        return closedStages;
    }
}