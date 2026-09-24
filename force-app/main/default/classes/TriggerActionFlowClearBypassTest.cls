// Trigger Actions Framework. Copyright 2021 Google LLC. Apache License 2.0.
// Vendored from github.com/mitchspano/apex-trigger-actions-framework
// Full licence: LICENSE-trigger-actions-framework.txt in the repo root.
@SuppressWarnings('PMD.ApexDoc, PMD.ApexUnitTestClassShouldHaveRunAs')
@IsTest(IsParallel=true)
private class TriggerActionFlowClearBypassTest {
	private static final String MY_STRING = 'MY_STRING';
	private static List<TriggerActionFlowClearBypass.Request> requests = new List<TriggerActionFlowClearBypass.Request>();
	private static TriggerActionFlowClearBypass.Request request = new TriggerActionFlowClearBypass.Request();
	private static Exception myException;

	@IsTest
	private static void clearBypassObjecthouldSucceedWithValidRequest() {
		TriggerBase.bypass(MY_STRING);
		request.Name = MY_STRING;
		request.bypassType = TriggerActionConstants.OBJECT_STRING;
		requests.add(request);

		TriggerActionFlowClearBypass.clearBypass(requests);

		System.Assert.isFalse(
			TriggerBase.isBypassed(MY_STRING),
			'The Object should not be bypassed'
		);
	}

	@IsTest
	private static void clearBypassApexShouldSucceedWithValidRequest() {
		MetadataTriggerHandler.bypass(MY_STRING);
		request.Name = MY_STRING;
		request.bypassType = TriggerActionConstants.APEX_STRING;
		requests.add(request);

		TriggerActionFlowClearBypass.clearBypass(requests);

		System.Assert.isFalse(
			MetadataTriggerHandler.isBypassed(MY_STRING),
			'The Apex should be not bypassed'
		);
	}

	@IsTest
	private static void clearBypassFlowShouldSucceedWithValidRequest() {
		TriggerActionFlow.bypass(MY_STRING);
		request.Name = MY_STRING;
		request.bypassType = TriggerActionConstants.FLOW_STRING;
		requests.add(request);

		TriggerActionFlowClearBypass.clearBypass(requests);

		System.Assert.isFalse(
			TriggerActionFlow.isBypassed(MY_STRING),
			'The Flow should not be bypassed'
		);
	}

	@IsTest
	private static void clearBypassShouldFailWithInvalidType() {
		request.Name = MY_STRING;
		request.bypassType = MY_STRING;
		requests.add(request);

		try {
			TriggerActionFlowClearBypass.clearBypass(requests);
		} catch (Exception e) {
			myException = e;
		}

		System.Assert.areNotEqual(
			null,
			myException,
			'We should have an exception thrown in this scenario'
		);
		System.Assert.isInstanceOfType(
			myException,
			IllegalArgumentException.class,
			'The exception should be of the correct type'
		);
		System.Assert.areEqual(
			myException.getMessage(),
			TriggerActionConstants.INVALID_TYPE,
			'The exeption should contain the message we are looking for'
		);
	}
}
