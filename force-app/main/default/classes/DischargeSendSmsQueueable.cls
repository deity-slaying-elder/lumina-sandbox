/**
 * Delivers the discharge SMS decided by DischargeSendSms, then stamps the patients.
 *
 * Separate from the decision logic because Apex cannot make a callout in a trigger's
 * transaction. The trigger decides who gets a message; this job sends and stamps.
 *
 * Ordering matches the flow: Send_Message ran first and Set_Last_SMS_Message second.
 * Precisely: the stamp is skipped only when the invocable THROWS. The Twilio package
 * does not throw on a delivery failure - it logs a failed TwilioSF__Message__c record
 * (verified live: auth error 20003 produced a failed record, a normal return, and a
 * stamp). The flow stamped in exactly the same situation, so this is parity, but it
 * means a stamped patient is "the send was attempted", not "the text arrived".
 * Checking the TwilioSF__Message__c status before stamping would be an improvement;
 * it is a behaviour change and needs sign-off, so it is not smuggled in here.
 *
 * Failures are rethrown after the stamping DML rather than swallowed. The existing
 * ThoroughCare callout swallows its exceptions into System.debug and that pattern has
 * already hidden a production integration problem once; failing loudly means the job
 * shows as failed in Setup > Apex Jobs where somebody can see it.
 *
 * SYSTEM MODE, DELIBERATELY. The flow this replaces ran in system context and wrote
 * what it needed regardless of who saved the record. Running-user enforcement here
 * (WITH USER_MODE, stripInaccessible) makes the same save silently drop writes for
 * lower-privilege profiles - in production, Lumina Manager No Edit Access can create
 * discharges without Patient edit, and Latest_Community_Episode__c carries no field
 * permissions for anyone - and a silently dropped TCM timestamp is a billing defect
 * nobody sees. Automation runs as the system, exactly as the flow did. User-facing
 * controllers are different and keep user-mode enforcement.
 */
public without sharing class DischargeSendSmsQueueable implements Queueable, Database.AllowsCallouts {

    /**
     * Messages per job. The binding limit for a transaction is 120 seconds of total
     * callout time rather than the count of callouts, so this stays well below the
     * hundred-callout ceiling to keep slow Twilio responses from timing the job out.
     */
    public static final Integer CHUNK_SIZE = 50;

    /** One decided send: who, where, and what. */
    public class Message {
        public final Id patientId;
        public final String phoneNumber;
        public final String body;

        public Message(Id patientId, String phoneNumber, String body) {
            this.patientId = patientId;
            this.phoneNumber = phoneNumber;
            this.body = body;
        }
    }

    private final List<Message> messages;

    public DischargeSendSmsQueueable(List<Message> messages) {
        this.messages = messages;
    }

    public void execute(QueueableContext context) {
        Set<Id> sentPatientIds = new Set<Id>();
        Exception firstFailure;

        for (Message message : messages) {
            try {
                send(message);
                sentPatientIds.add(message.patientId);
            } catch (Exception failure) {
                // Keep sending to the rest; one bad number must not block the batch.
                if (firstFailure == null) {
                    firstFailure = failure;
                }
            }
        }

        stampPatients(sentPatientIds);

        if (firstFailure != null) {
            throw firstFailure;
        }
    }

    private void send(Message message) {
        // The same invocable the flow called, with the same two inputs. Tests replace
        // the callout with an HttpCalloutMock, so this line itself is exercised only
        // against the mock; the live path is verified in the org, not in a test run.
        TwilioSF.TwilioSendSMS.SmsDetail detail = new TwilioSF.TwilioSendSMS.SmsDetail();
        detail.message = message.body;
        detail.toNumber = message.phoneNumber;
        TwilioSF.TwilioSendSMS.sendSMSToNumber(
            new List<TwilioSF.TwilioSendSMS.SmsDetail>{ detail }
        );
    }

    private void stampPatients(Set<Id> patientIds) {
        if (patientIds.isEmpty()) {
            return;
        }
        Datetime now = Datetime.now();
        List<Patient__c> updates = new List<Patient__c>();
        for (Id patientId : patientIds) {
            updates.add(new Patient__c(Id = patientId, Last_SMS_Sent_Date__c = now));
        }
        update updates;
    }
}
