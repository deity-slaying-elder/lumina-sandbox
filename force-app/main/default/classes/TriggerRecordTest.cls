// Trigger Actions Framework. Copyright 2024 Google LLC. Apache License 2.0.
// Vendored from github.com/mitchspano/apex-trigger-actions-framework
// Full licence: LICENSE-trigger-actions-framework.txt in the repo root.
@SuppressWarnings('PMD.CatchSpecificExceptionType')
@IsTest(isParallel=true)
private class TriggerRecordTest {
	@IsTest
	private static void shouldBeAbleToConstructATriggerRecord() {
		Exception caught;
		try {
			AccountTriggerRecord triggerRecord = new AccountTriggerRecord();
			triggerRecord.newSobject = new Account();
			triggerRecord.oldSObject = new Account();
		} catch (Exception e) {
			caught = e;
		}
		System.Assert.isNull(
			caught,
			'Caught an unexpected Exception when constructing a TriggerRecord.'
		);
	}

	private class AccountTriggerRecord extends TriggerRecord {
	}
}
