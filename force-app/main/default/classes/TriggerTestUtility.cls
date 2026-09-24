// Trigger Actions Framework. Copyright 2020 Google LLC. Apache License 2.0.
// Vendored from github.com/mitchspano/apex-trigger-actions-framework
// Full licence: LICENSE-trigger-actions-framework.txt in the repo root.
/**
 * @group Trigger Actions Framework
 * @description The `TriggerTestUtility` class is a utility class that provides helper methods for writing
 * Apex test classes for trigger handlers.
 *
 * The `TriggerTestUtility` class provides the following helper methods:
 *
 * - `getFakeId`: This method generates a fake ID for the specified sObject type.
 */
@IsTest
public class TriggerTestUtility {
	private static Integer myNumber = 1;

	/**
	 * @description This method generates a fake ID for the specified sObject type.
	 *
	 * @param sObjectType The sObject type to generate a fake ID for.
	 * @return A fake ID for the specified sObject type.
	 */
	public static Id getFakeId(Schema.SObjectType sObjectType) {
		String result = String.valueOf(myNumber++);
		return (Id) (sObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
			.getKeyPrefix() +
		'0'.repeat(12 - result.length()) +
		result);
	}
}
