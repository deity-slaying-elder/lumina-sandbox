// Trigger Actions Framework. Copyright 2021 Google LLC. Apache License 2.0.
// Vendored from github.com/mitchspano/apex-trigger-actions-framework
// Full licence: LICENSE-trigger-actions-framework.txt in the repo root.
@SuppressWarnings('PMD.ApexDoc, PMD.ApexUnitTestClassShouldHaveRunAs')
@IsTest(IsParallel=true)
private class TriggerActionFlowAddErrorTest {
	private static final String MY_STRING = 'MY_STRING';
	private static final String NAME = 'Name';
	private static List<TriggerActionFlowAddError.Request> requests = new List<TriggerActionFlowAddError.Request>();
	private static TriggerActionFlowAddError.Request request = new TriggerActionFlowAddError.Request();

	@IsTest
	private static void addErrorShouldSucceedWithValidRequest() {
		Account account = new Account();
		request.errorMessage = MY_STRING;
		request.record = account;
		requests.add(request);

		TriggerActionFlowAddError.addError(requests);

		System.Assert.isTrue(
			account.hasErrors(),
			'The Account should have an error'
		);
		System.Assert.areEqual(
			1,
			account.getErrors().size(),
			'There should only be one error'
		);
		System.Assert.areEqual(
			MY_STRING,
			account.getErrors()[0].getMessage(),
			'The error should contain the message we are looking for'
		);
	}

	@IsTest
	private static void addErrorShouldAddAnErrorAtTheFieldSpecified() {
		Account account = new Account();
		request.errorMessage = MY_STRING;
		request.fieldName = NAME;
		request.record = account;
		requests.add(request);

		TriggerActionFlowAddError.addError(requests);

		System.Assert.isTrue(
			account.hasErrors(),
			'The Account should have an error'
		);
		System.Assert.areEqual(
			1,
			account.getErrors().size(),
			'There should only be one error'
		);
		System.Assert.areEqual(
			MY_STRING,
			account.getErrors()[0].getMessage(),
			'The error should contain the message we are looking for'
		);
	}
}
