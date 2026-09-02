@isTest
private class TriggerContextTest {

    @isTest
    static void notBypassedByDefault() {
        // All four shipped Trigger_Bypass__mdt records are false on purpose.
        Assert.isFalse(TriggerContext.isBypassed('VisitTrigger'),
            'Shipped metadata must leave every trigger running');
    }

    @isTest
    static void unknownTriggerNameFailsSafe() {
        // No metadata record and no runtime override: a typo must NOT bypass.
        Assert.isFalse(TriggerContext.isBypassed('NoSuchTrigger'),
            'An unrecognised name must fail closed, leaving the trigger running');
    }

    @isTest
    static void runtimeBypassAppliesToOneTriggerOnly() {
        TriggerContext.bypass('VisitTrigger');

        Assert.isTrue(TriggerContext.isBypassed('VisitTrigger'), 'Named trigger should be bypassed');
        Assert.isFalse(TriggerContext.isBypassed('FacilityMapperTrigger'),
            'A per-trigger bypass must not leak to other triggers');
    }

    @isTest
    static void allTriggersOverrideBypassesEverything() {
        TriggerContext.bypass('All_Triggers');

        Assert.isTrue(TriggerContext.isBypassed('VisitTrigger'), 'All_Triggers should cover Visit');
        Assert.isTrue(TriggerContext.isBypassed('HospitalAdmissionTrigger'), 'and Hospital Admission');
        Assert.isTrue(TriggerContext.isBypassed('AnythingElse'), 'and anything else');
    }

    @isTest
    static void clearBypassRestoresNormalRunning() {
        TriggerContext.bypass('VisitTrigger');
        Assert.isTrue(TriggerContext.isBypassed('VisitTrigger'), 'precondition');

        TriggerContext.clearBypass('VisitTrigger');
        Assert.isFalse(TriggerContext.isBypassed('VisitTrigger'), 'clearBypass should restore running');
    }

    @isTest
    static void claimUnprocessedReturnsEachIdOnlyOnce() {
        Id a = Patient__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
        Id b = Patient__c.SObjectType.getDescribe().getKeyPrefix() + '000000000002AAA';

        Set<Id> first = TriggerContext.claimUnprocessed('k', new Set<Id>{ a, b });
        Set<Id> second = TriggerContext.claimUnprocessed('k', new Set<Id>{ a, b });

        Assert.areEqual(2, first.size(), 'First claim returns both ids');
        Assert.areEqual(0, second.size(), 'Re-entry returns nothing, which is what stops recursion');
    }

    @isTest
    static void claimsAreIndependentPerKey() {
        Id a = Patient__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';

        TriggerContext.claimUnprocessed('featureOne', new Set<Id>{ a });
        Set<Id> other = TriggerContext.claimUnprocessed('featureTwo', new Set<Id>{ a });

        // A single shared set here would silently suppress the second feature.
        Assert.areEqual(1, other.size(), 'A claim under one key must not block another key');
    }

    @isTest
    static void resetClearsBothClaimsAndOverrides() {
        Id a = Patient__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
        TriggerContext.bypass('VisitTrigger');
        TriggerContext.claimUnprocessed('k', new Set<Id>{ a });

        TriggerContext.reset();

        Assert.isFalse(TriggerContext.isBypassed('VisitTrigger'), 'reset clears runtime overrides');
        Assert.areEqual(1, TriggerContext.claimUnprocessed('k', new Set<Id>{ a }).size(),
            'reset clears claimed ids');
    }
}
