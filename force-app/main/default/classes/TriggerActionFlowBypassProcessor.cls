// Trigger Actions Framework. Copyright 2022 Google LLC. Apache License 2.0.
// Vendored from github.com/mitchspano/apex-trigger-actions-framework
// Full licence: LICENSE-trigger-actions-framework.txt in the repo root.
/**
 * @group Trigger Actions Framework
 * @description  This abstract class provides a framework for processing bypass requests for
 * trigger action flows, Apex classes, and Object triggers.
 *
 * To use this class, you must first create a subclass that implements the
 * `processApexBypasses`, `processFlowBypasses`, and `processObjectBypasses` methods.
 * You can then use the `execute` method to process bypass requests for the specified
 *  type of bypass.
 */
public inherited sharing abstract class TriggerActionFlowBypassProcessor {
	/**
	 * @description This method processes a bypass request for the specified type of bypass.
	 *
	 * @param requestType The type of bypass to process. Valid values are `Apex`, `Flow`, or `Object`.
	 * @param requestName The name of the trigger action flow, Apex class, or Object trigger to bypass.
	 */
	public void execute(String requestType, String requestName) {
		if (!TriggerActionConstants.REQUEST_TYPES.contains(requestType)) {
			throw new IllegalArgumentException(TriggerActionConstants.INVALID_TYPE);
		} else if (requestType == TriggerActionConstants.FLOW_STRING) {
			this.processFlowBypasses(requestName);
		} else if (requestType == TriggerActionConstants.APEX_STRING) {
			this.processApexBypasses(requestName);
		} else if (requestType == TriggerActionConstants.OBJECT_STRING) {
			this.processObjectBypasses(requestName);
		}
	}

	protected abstract void processApexBypasses(String requestType);
	protected abstract void processFlowBypasses(String requestType);
	protected abstract void processObjectBypasses(String requestType);
}
