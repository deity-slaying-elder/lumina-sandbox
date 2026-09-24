// Trigger Actions Framework. Copyright 2020 Google LLC. Apache License 2.0.
// Vendored from github.com/mitchspano/apex-trigger-actions-framework
// Full licence: LICENSE-trigger-actions-framework.txt in the repo root.
/**
 * @group Trigger Actions Framework
 * @description This class contains constants used by the TriggerAction framework.
 */
public class TriggerActionConstants {
	public static final String APEX_STRING = 'Apex';
	public static final String FLOW_STRING = 'Flow';
	public static final String OBJECT_STRING = 'Object';
	public static final String RECORD_PRIOR_VARIABLE = 'recordPrior';
	public static final String RECORD_VARIABLE = 'record';
	public static final String INVALID_FLOW_NAME = 'You must provide the name of a flow to execute';
	public static final String INVALID_TYPE = 'The bypassType must equal Object, Apex, or Flow';
	public static final Set<String> REQUEST_TYPES = new Set<String>{
		TriggerActionConstants.APEX_STRING,
		TriggerActionConstants.FLOW_STRING,
		TriggerActionConstants.OBJECT_STRING
	};
}
