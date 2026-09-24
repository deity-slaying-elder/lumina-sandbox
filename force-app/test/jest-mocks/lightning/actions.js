/**
 * Stub for lightning/actions, which sfdx-lwc-jest does not ship. Only the close event is used.
 */
export class CloseActionScreenEvent extends CustomEvent {
    constructor() {
        super('lightning__closeactionscreen', { bubbles: true, composed: true });
    }
}
