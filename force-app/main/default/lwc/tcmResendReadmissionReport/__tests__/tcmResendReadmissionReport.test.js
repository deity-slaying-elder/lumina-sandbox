import { createElement } from 'lwc';
import TcmResendReadmissionReport from 'c/tcmResendReadmissionReport';
import preview from '@salesforce/apex/TCMReadmissionResend.preview';
import sendReport from '@salesforce/apex/TCMReadmissionResend.send';

jest.mock(
    '@salesforce/apex/TCMReadmissionResend.preview',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/TCMReadmissionResend.send',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const SENDABLE = {
    sendable: true,
    sent: false,
    facilityName: 'Sample Care Center',
    windowLabel: 'Tuesday, September 8, 2026',
    rowCount: 3,
    expiryHours: 24,
    maxOpens: 10,
    redirected: false,
    deliveries: [
        { email: 'admin@sample.test', role: 'Administrator', sent: false },
        { email: 'don@sample.test', role: 'Director of Nursing', sent: false }
    ],
    problems: []
};

const RECORD_ID = 'a01000000000001AAA';

/**
 * Attaches first and sets the record id afterwards, which is the order a quick action actually
 * uses. Setting it before attaching hid a real bug: the component used to call Apex from
 * connectedCallback, so in the org it asked about a null facility and the dialog said "No
 * facility was supplied", while a test that pre-set the id passed.
 */
function build() {
    const element = createElement('c-tcm-resend-readmission-report', {
        is: TcmResendReadmissionReport
    });
    document.body.appendChild(element);
    element.recordId = RECORD_ID;
    return element;
}

function settled() {
    return Promise.resolve().then(() => Promise.resolve());
}

describe('c-tcm-resend-readmission-report', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('waits for the record id before calling Apex, and asks only once', async () => {
        preview.mockResolvedValue(SENDABLE);
        const element = createElement('c-tcm-resend-readmission-report', {
            is: TcmResendReadmissionReport
        });
        document.body.appendChild(element);
        await settled();

        // Attached, but the quick action has not handed over the record yet.
        expect(preview).not.toHaveBeenCalled();

        element.recordId = RECORD_ID;
        await settled();
        expect(preview).toHaveBeenCalledTimes(1);
        expect(preview).toHaveBeenCalledWith({ facilityId: RECORD_ID });

        // The framework can set the same value again; that must not re-ask.
        element.recordId = RECORD_ID;
        await settled();
        expect(preview).toHaveBeenCalledTimes(1);
    });

    it('lists every recipient before anything is sent', async () => {
        preview.mockResolvedValue(SENDABLE);
        const element = build();
        await settled();

        expect(preview).toHaveBeenCalledWith({ facilityId: RECORD_ID });
        expect(sendReport).not.toHaveBeenCalled();

        const rows = element.shadowRoot.querySelectorAll('.resend__row');
        expect(rows).toHaveLength(2);
        expect(rows[0].textContent).toContain('admin@sample.test');
        expect(rows[1].textContent).toContain('Director of Nursing');

        const labels = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).map((button) => button.label);
        expect(labels).toEqual(['Cancel', 'Send new link']);
    });

    it('states the expiry and the view cap', async () => {
        preview.mockResolvedValue(SENDABLE);
        const element = build();
        await settled();

        expect(element.shadowRoot.textContent).toContain(
            'expires 24 hours after it is sent, and closes after 10 views'
        );
    });

    it('sends only when the confirm button is clicked, then reports each result', async () => {
        preview.mockResolvedValue(SENDABLE);
        sendReport.mockResolvedValue({
            ...SENDABLE,
            sent: true,
            summary: 'Sent to 2 recipient(s), each with their own new link.',
            deliveries: [
                {
                    email: 'admin@sample.test',
                    role: 'Administrator',
                    sent: true,
                    expiresAt: 'Thursday, September 10, 2026 2:12 PM EDT'
                },
                {
                    email: 'don@sample.test',
                    role: 'Director of Nursing',
                    sent: false,
                    problem: 'Invalid address'
                }
            ]
        });
        const element = build();
        await settled();

        const toasts = [];
        element.addEventListener('lightning__showtoast', (event) => toasts.push(event.detail));

        const confirm = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((button) => button.label === 'Send new link');
        confirm.click();
        await settled();

        expect(sendReport).toHaveBeenCalledWith({ facilityId: RECORD_ID });
        expect(toasts).toHaveLength(1);
        expect(toasts[0].variant).toBe('success');

        const text = element.shadowRoot.textContent;
        expect(text).toContain('Sent');
        expect(text).toContain('Invalid address');

        // Once it has sent, the only way out is Close, so it cannot be sent twice by accident.
        const labels = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).map((button) => button.label);
        expect(labels).toEqual(['Close']);
    });

    it('explains why a resend is not possible instead of offering the button', async () => {
        preview.mockResolvedValue({
            sendable: false,
            blockedReason: 'No readmissions for this facility during Tuesday, September 8, 2026.',
            deliveries: [],
            problems: []
        });
        const element = build();
        await settled();

        expect(element.shadowRoot.textContent).toContain('No readmissions for this facility');
        const labels = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).map((button) => button.label);
        expect(labels).toEqual(['Close']);
    });

    it('surfaces an Apex failure rather than failing silently', async () => {
        preview.mockRejectedValue({ body: { message: 'You do not have access.' } });
        const element = build();
        await settled();

        expect(element.shadowRoot.textContent).toContain('You do not have access.');
    });

    it('warns that a sandbox redirects delivery away from the facility', async () => {
        preview.mockResolvedValue({ ...SENDABLE, redirected: true });
        const element = build();
        await settled();

        expect(element.shadowRoot.textContent).toContain('Sandbox org');
    });
});
