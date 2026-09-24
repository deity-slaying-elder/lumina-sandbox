import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import preview from '@salesforce/apex/TCMReadmissionResend.preview';
import sendReport from '@salesforce/apex/TCMReadmissionResend.send';

/**
 * Quick action on Facility: reissue the readmissions report link and email it again.
 *
 * Two steps on purpose. The first call reports what would be sent and to which addresses, and
 * sends nothing. Only the confirm button sends, because this puts a link to patient data in
 * someone's inbox and the person clicking should see the address list first.
 */
export default class TcmResendReadmissionReport extends LightningElement {
    /**
     * A quick action can hand the record id over after the component has already connected, so
     * the load is kicked off from the setter rather than from connectedCallback. Doing it on
     * connect asked Apex for a null facility and the dialog said "No facility was supplied".
     */
    @api
    get recordId() {
        return this.privateRecordId;
    }

    set recordId(value) {
        this.privateRecordId = value;
        if (value && !this.requested) {
            this.requested = true;
            this.load();
        }
    }

    privateRecordId;
    requested = false;
    loading = true;
    working = false;
    done = false;
    result;
    error;

    load() {
        this.loading = true;
        preview({ facilityId: this.privateRecordId })
            .then((result) => {
                this.result = result;
            })
            .catch((error) => {
                this.error = this.messageFrom(error);
            })
            .finally(() => {
                this.loading = false;
            });
    }

    handleSend() {
        this.working = true;
        this.error = undefined;
        sendReport({ facilityId: this.privateRecordId })
            .then((result) => {
                this.result = result;
                this.done = true;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: result.sent ? 'Report resent' : 'Nothing was sent',
                        message: result.sent ? result.summary : result.blockedReason || result.summary,
                        variant: result.sent ? 'success' : 'warning',
                        mode: 'sticky'
                    })
                );
            })
            .catch((error) => {
                this.error = this.messageFrom(error);
            })
            .finally(() => {
                this.working = false;
            });
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    get blocked() {
        return !this.loading && !this.error && this.result && !this.result.sendable;
    }

    get showDetail() {
        return !this.loading && !!this.result && this.result.sendable === true;
    }

    get ready() {
        return !this.loading && !this.error && this.result && this.result.sendable && !this.done;
    }

    get expiryLabel() {
        if (!this.result) {
            return '';
        }
        const hours = this.result.expiryHours;
        const cap = this.result.maxOpens;
        const parts = [`expires ${hours} hour${hours === 1 ? '' : 's'} after it is sent`];
        if (cap > 0) {
            parts.push(`closes after ${cap} views`);
        }
        return `Each new link ${parts.join(', and ')}.`;
    }

    get recipientRows() {
        if (!this.result || !this.result.deliveries) {
            return [];
        }
        return this.result.deliveries.map((delivery) => ({
            ...delivery,
            key: delivery.email,
            statusLabel: this.done ? (delivery.sent ? 'Sent' : delivery.problem || 'Not sent') : '',
            statusClass: delivery.sent
                ? 'slds-text-color_success slds-text-body_small'
                : 'slds-text-color_error slds-text-body_small'
        }));
    }

    get hasProblems() {
        return this.result && this.result.problems && this.result.problems.length > 0;
    }

    messageFrom(error) {
        if (!error) {
            return 'Something went wrong.';
        }
        if (error.body && error.body.message) {
            return error.body.message;
        }
        return error.message || String(error);
    }
}