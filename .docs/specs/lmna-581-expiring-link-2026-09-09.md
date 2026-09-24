# LMNA-581 - Readmission report via expiring link

Date: 2026-09-09. Status: approved by Lumina (client chose the link over encrypted email).

## Decision

The daily TCM readmission report stops travelling as a CSV attachment. Each facility email
carries only a count and a link. The link points at a Salesforce `ContentDistribution`
(native public link) over a **PDF** of the report, expiring after a configurable number of
hours. Views and downloads are recorded natively on `ContentDistributionView`.

Why PDF, not CSV: live-tested 2026-09-09, Salesforce's public file viewer shows "No preview
available" for CSV, so a recipient could only download, never read. It renders PDF inline. The
PDF is produced by `TCMReadmissionReportPdf` (Visualforce, `renderAs="pdf"`) via
`getContentAsPDF()` inside the batch, which therefore implements `Database.AllowsCallouts` and
renders before any DML. Cell formatting is shared with the CSV builder. Attachment mode still
sends the CSV.

No relay, no Graph, no vendor. The notification email holds no PHI, so ordinary Salesforce
mail is sufficient.

## What already exists (lumDev, retrieved into the repo 2026-09-09)

`TCMDailyReadmissionScheduler`, `TCMDailyReadmissionBatch`, `TCMReadmissionCsvBuilder`,
`TCMReadmissionRecipientResolver`, `TCMReadmissionWindow`, `TCMReportConfig`, tests, and the
`TCM_Report_Config__mdt` type with its `Default` record. Facility fields `Admin_Email__c`,
`DON_Email__c`, `Exclude_from_TCM_Reporting__c`. None of this had been in git.

Prod has none of it. Prod also has zero Org-Wide Email Addresses and zero
`ContentDistribution` records.

## Changes

### Config (`TCM_Report_Config__mdt`)

| Field | Type | Default | Purpose |
|---|---|---|---|
| `Delivery_Mode__c` | Picklist `Link` / `Attachment` | `Link` | Flip back to attachment without a redeploy |
| `Link_Expiry_Hours__c` | Number | 24 | Link lifetime. James set 24 on 2026-09-09; the code falls back to 72 if blank. Note a Monday link then dies Tuesday morning, before some staff return |
| `Allow_Download__c` | Checkbox | true | Export button on the file page. Pending Lumina's explicit yes; toggle |
| `Notify_On_Visit__c` | Checkbox | false | Salesforce emails the file owner on each open |

`Digest_Recipients__c` gains `kevingrayson@luminacare.com` (confirmed by Kevin via Chayim).
`Internal_CC_Email__c` stays blank by design: Kevin gets the digest, not a copy of each email.

### New class `TCMReadmissionLinkPublisher`

Bulk per chunk. Inserts one `ContentVersion` per sendable facility
(`FirstPublishLocationId` = the Facility, so the file sits on the facility record), then one
`ContentDistribution` per version with:

- `PreferencesExpires = true`, `ExpiryDate = now + Link_Expiry_Hours__c`
- `PreferencesAllowOriginalDownload = Allow_Download__c`, `PreferencesAllowPDFDownload = false`
- `PreferencesAllowViewInBrowser = true`, `PreferencesLinkLatestVersion = true`
- `PreferencesPasswordRequired = false`, `PreferencesNotifyOnVisit = Notify_On_Visit__c`

Requeries `DistributionPublicUrl`. Partial-success DML; a facility whose link cannot be
created is reported as a failure and its email is not sent (never send a broken link).

### `TCMDailyReadmissionBatch`

- Link mode: publish links for the chunk, build message with count + link, no attachment.
- Attachment mode: unchanged behaviour.
- Digest itemises every send: facility, row count, To, CC, expiry. Skips listed after, as now.

### `TCMReadmissionResend` and `tcmResendReadmissionReport` (added 2026-09-09)

On-demand reissue from the Facility record, as a Lightning Web Component quick action.

- `preview(facilityId)` reports the window, the row count and every recipient with their role,
  and performs no DML and no send. Drives the confirm dialog.
- `send(facilityId)` reuses the report already filed on the record when one exists for that
  window (`ContentVersion` matched on title), so a reissue does not store a second copy and
  needs no PDF render. Falls back to rendering, and reports the reason if that is refused.
- One brand new `ContentDistribution` and one new `Readmission_Report_Link__c` row per
  recipient. Nothing is edited in place, so the disclosure trail keeps every delivery.
- `TCMReadmissionEmailBuilder` was extracted so the resend and the daily job send the same
  message. The resend adds one line saying the link was reissued.
- `sandboxOverride` is a test seam: whether the org is a sandbox decides where mail goes, and
  the assertions must not depend on which org the suite runs in.

Platform behaviour worth knowing: Salesforce rejects a second batch of `ContentDistribution`
inserts against the same `ContentVersion` inside one transaction with `DUPLICATE_VALUE`. Each
button click is its own transaction, so this only ever shows up in a test that sends twice.

### Not in scope (phase two, only if asked)

Custom "expired, send me a new link" page and recipient self-service. Salesforce's own expired
page is used, and the reissue is a Lumina action, not a recipient action. Name/role capture on
open. Custom domain for the link. Revoking the previous link when a new one is issued: today
both stay live until they expire, which is worth a decision.

## Preconditions the human must confirm before deploy

1. Setup > Salesforce Files > Content Deliveries and Public Links: **Content Deliveries enabled**.
   Zero `ContentDistribution` records exist in either org, so this is unverified.
2. Org-Wide Email Address `tcm@luminacare.com` created and verified in the target org.
3. Compliance sign off in writing (link authenticates by possession of the mailbox).
4. Lumina's yes on the export button, or set `Allow_Download__c = false`.

## Deploy

`lumDev` was deployed and live-tested with the user's explicit approval for this project. The
scheduled job holds a deploy lock on its whole dependency chain, so the order is: abort the
`TCM Email Readmission` cron, deploy, reschedule `0 0 8 ? * 2,3,4,5,6`.

Production remains a human deploy.

## Tests

Existing suite kept green in attachment mode. Link mode adds: no attachments on messages, body
carries the public URL, one distribution per sent facility with expiry in the configured
window, distribution preferences reflect config, skipped facility gets no distribution,
digest entries carry facility, count and recipients.

## Decisions and measurements, 2026-09-10

Confirmed by the client contact:

- **Download stays on.** `Allow_Download__c = true` is deliberate. Staff need to work the list
  rather than read it on screen. The consequence is stated plainly: a downloaded copy outlives
  the link's expiry and the view cap, and only the link is time boxed.
- **Expiry should purge the file.** When a link expires, the stored PDF for that report should be
  deleted too, so the data does not outlive the delivery window on the Facility record. Not built
  yet. Needs a scheduled job over `Readmission_Report_Link__c` and the `ContentDocument` behind
  each expired distribution, plus a rule for what to do when several recipients share one file
  and only some links have expired.

The view cap was proven end to end for the first time, against real platform view rows rather
than a test seam:

- 11 real opens were driven through one recipient's link, `Max_Opens__c = 10`.
- `TCMReadmissionLinkAudit.sync()` reported `examined=8 updated=1 opens=11 capped=1`.
- The row was stamped `Closed_Reason__c = 'View limit reached'` with `Opens__c = 11`, first open
  and last activity four minutes apart.
- Reloading that URL returns Salesforce's "This content delivery has expired." page.
- The second recipient's link for the same report stayed open with zero opens, which is the proof
  that the cap is per recipient and not per file.

Known limits confirmed by the same test: the cap is enforced when the audit runs, not at the
tenth open, so a burst can exceed the cap before it closes. The audit runs only from the batch's
finish today, so with the scheduled job disabled nothing caps anything, and links issued by the
resend button are never audited. Both are on the fix list.

## Review fixes, 2026-09-10

A five-way review of the whole feature, verified claim by claim against the code and both orgs.
What it found and what changed:

- **The report page trusted its own URL.** It took the window start and end as epoch
  milliseconds, so a caller could turn one day's report into a facility's entire history, while
  the heading still claimed one day. It now receives only the facility and a report date, and
  derives the window with `TCMReadmissionWindow.forLastCoveredDate`, the same rule the job uses.
  Queries run in `AccessLevel.USER_MODE`, so field-level security and sharing apply to whoever
  renders it, and an id belonging to another object is refused rather than bound into the query.
- **The disclosure log was writable and org-wide readable.** `TCM_Readmission_Reports` is now
  read-only with `viewAllRecords` off, which restores the master-detail scoping. Field history is
  on. A separate `TCM_Readmission_Report_Operator` set carries what actually sending needs: the
  Apex class, the report page and create on the link rows. `Recipient_Email__c` is required on
  the object, so Salesforce refuses field permissions for it; it is visible regardless.
- **The cap could claim a link was closed when it was not.** The row is now stamped only for
  links the platform confirmed closed, the rest are reported in the digest and in the resend
  dialog, `Expires_At__c` keeps the expiry the link was issued with, and the new `Closed_At__c`
  records the early close. A link already past its own expiry is no longer relabelled as capped.
- **The cap depended entirely on the nightly job.** The resend now refreshes the audit itself, so
  links issued by the button are counted and capped even while the schedule is off.
- **First-open followed row order, not time.** The query sorted ascending, so it was correct by
  luck; a dropped ORDER BY would have put the wrong time in a disclosure record. It now takes the
  minimum and maximum timestamps explicitly.
- **Every sync rewrote every row forever.** Datetime fields drop milliseconds on save while a
  platform view timestamp carries them, so the comparison never matched. Derived timestamps are
  truncated to whole seconds. This mattered more once field history was enabled.
- **The digest under-reported opens.** Totals counted only rows that changed, so a quiet day
  reported zero opens, which reads as nobody opening it. Totals now describe the links.
- **Attachment mode marked all but the first recipient unsent** although one email reached them
  all. It now shares the single send result across every row.
- **Failures overwrote each other** in the publisher, including a line that assigned a field to
  itself. `Published.note()` appends instead.

Added: `TCMReadmissionReportPurge`, a schedulable that deletes a stored report once every link to
it is dead and the grace period has passed, which is Lumina's decision from 2026-09-10. It never
deletes attribution rows, so the disclosure trail outlives the file.

Not scheduled. The purge runs on demand until someone decides the cadence:
`System.schedule('TCM Readmission Report Purge', '0 0 3 ? * *', new TCMReadmissionReportPurge());`

Verified after the fixes: 100 Apex tests and 7 Jest tests pass in lumDev, and a live resend with
no stored file for the window rendered a fresh PDF through the hardened page, showing the correct
single day and the correct facility.
