/**
 * Stub for lightning/modal, which sfdx-lwc-jest does not ship.
 *
 * It supplies the two things the real base class contributes to a modal component: a
 * LightningElement to extend, and close(). The focus trap, Escape handling and focus
 * return to the trigger are platform behaviour, so they are verified in the org rather
 * than here.
 */
import { LightningElement } from 'lwc';

export default class LightningModal extends LightningElement {
    static open = jest.fn();

    close(result) {
        this.dispatchEvent(new CustomEvent('close', { detail: result }));
        return result;
    }
}
