// Trigger Actions Framework. Copyright 2024 Google LLC. Apache License 2.0.
// Vendored from github.com/mitchspano/apex-trigger-actions-framework
// Full licence: LICENSE-trigger-actions-framework.txt in the repo root.
/**
 * @description An abstract class that provides a base structure for trigger context records.
 */
@SuppressWarnings('PMD.AvoidGlobalModifier')
global abstract class TriggerRecord {
	/**
	 * @description The new version of the SObject that triggered the current execution context.
	 */
	global SObject newSobject;

	/**
	 * @description The previous version of the SObject that triggered the current execution context.
	 */
	global SObject oldSobject;
}
