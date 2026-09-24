// Trigger Actions Framework. Copyright 2023 Google LLC. Apache License 2.0.
// Vendored from github.com/mitchspano/apex-trigger-actions-framework
// Full licence: LICENSE-trigger-actions-framework.txt in the repo root.
@IsTest(isParallel=true)
@SuppressWarnings('PMD.ApexDoc')
private with sharing class FlowChangeEventHeaderTest {
	private static FlowChangeEventHeader header = new FlowChangeEventHeader(
		new EventBus.ChangeEventHeader()
	);

	@IsTest
	private static void shouldBeAbleToConstruct() {
		System.Assert.isNotNull(
			header,
			'Unable to construct a FlowChangeEventHeader'
		);
	}

	@IsTest
	private static void shouldBeAbleToGenerateHashCode() {
		System.Assert.isNotNull(header.hashCode(), 'Hash code was not generated');
	}

	@IsTest
	private static void shouldBeAbleToCompare() {
		FlowChangeEventHeader other = new FlowChangeEventHeader(
			new EventBus.ChangeEventHeader()
		);
		other.changeType = 'CREATE';

		System.Assert.areEqual(
			new FlowChangeEventHeader(new EventBus.ChangeEventHeader()),
			header,
			'Unable to detect identical FlowChangeEventHeader objects'
		);
		System.Assert.areNotEqual(
			header,
			other,
			'Unable to detect different FlowChangeEventHeader objects'
		);
		System.Assert.areNotEqual(
			header,
			null,
			'Unable to detect difference between FlowChangeEventHeader and null'
		);
	}
}
