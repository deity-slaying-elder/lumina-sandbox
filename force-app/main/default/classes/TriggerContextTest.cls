@isTest
private class TriggerContextTest {

    // A real record is not needed - claimUnprocessed only ever compares ids.
    // An Id must be exactly 15 or 18 characters: 3-char key prefix + 12.
    private static Id fakeId(Integer i) {
        String suffix = String.valueOf(i).leftPad(12, '0');
        return Id.valueOf(Patient__c.SObjectType.getDescribe().getKeyPrefix() + suffix);
    }

    @isTest
    static void claimsEachIdOnlyOnce() {
        Id a = fakeId(1);
        Id b = fakeId(2);

        Set<Id> first = TriggerContext.claimUnprocessed('k', new Set<Id>{ a, b });
        Set<Id> second = TriggerContext.claimUnprocessed('k', new Set<Id>{ a, b });

        Assert.areEqual(2, first.size(), 'First pass should claim both ids');
        Assert.areEqual(0, second.size(),
            'A re-entrant pass should claim nothing, which is what stops the loop');
    }

    @isTest
    static void claimsArePerKeyNotGlobal() {
        Id a = fakeId(1);

        TriggerContext.claimUnprocessed('featureOne', new Set<Id>{ a });
        Set<Id> other = TriggerContext.claimUnprocessed('featureTwo', new Set<Id>{ a });

        Assert.areEqual(1, other.size(),
            'One feature claiming an id must not suppress a different feature. A single '
            + 'shared set is exactly the bug this keying prevents');
    }

    @isTest
    static void partiallyClaimedSetReturnsOnlyTheFreshIds() {
        Id a = fakeId(1);
        Id b = fakeId(2);

        TriggerContext.claimUnprocessed('k', new Set<Id>{ a });
        Set<Id> fresh = TriggerContext.claimUnprocessed('k', new Set<Id>{ a, b });

        Assert.areEqual(1, fresh.size(), 'Only the unclaimed id should come back');
        Assert.isTrue(fresh.contains(b), 'and it should be the one not seen before');
    }

    @isTest
    static void emptyInputIsSafe() {
        Assert.areEqual(0, TriggerContext.claimUnprocessed('k', new Set<Id>()).size(),
            'An empty candidate set should return empty, not throw');
    }

    @isTest
    static void resetClearsClaims() {
        Id a = fakeId(1);
        TriggerContext.claimUnprocessed('k', new Set<Id>{ a });

        TriggerContext.reset();

        Assert.areEqual(1, TriggerContext.claimUnprocessed('k', new Set<Id>{ a }).size(),
            'reset should clear claimed ids so one test does not leak into the next');
    }
}
