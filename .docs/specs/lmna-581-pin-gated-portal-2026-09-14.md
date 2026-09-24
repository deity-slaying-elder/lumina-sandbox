# LMNA-581 phase two: a report page on a Salesforce Site, opened by a ten-minute code

Written 2026-09-14, rewritten 2026-09-15 after the build. Supersedes the delivery half of
`lmna-581-expiring-link-2026-09-09.md`; the attribution, resend and purge halves carry over.

**Status: built, deployed to lumDev and live-tested 2026-09-15. Production is untouched and
remains a human deploy.** See "Production checklist" at the end.

## Why this exists

Chris raised two concerns about the shipped design: that someone could guess another facility's
URL, and that a link on its own is not enough protection for patient data. The first was not
true of the phase-one build, but the second is fair. A URL is a bearer token: anyone holding it
is in, and a URL leaks easily through browser history, a forwarded message or a screenshot.

The first answer was a PIN sent in the same email as the link, valid as long as the link. Chayim
then asked for the stronger option, a one-time code that dies after ten minutes. That code
cannot ride in the report email, because the job sends at 8am and people open the email hours
later. So the code is requested at the moment of viewing instead, and sent to the address the
link was issued to. That also closes the forwarded-email gap the same-email PIN left open.

## What changed, in one line

The public file link is gone. The email carries a link to a page we own; that page emails a
six-digit code to the address on file when asked, and shows the report only after the code.

### What this does and does not protect against

- **Protects:** a URL alone. Copied from history, pasted into a chat, captured in a proxy log or
  a screenshot, the link is useless without a fresh code sent to the mailbox it was issued to.
- **Protects:** a forwarded email. The forwardee can ask for a code, but it goes to the original
  address. Unless they also control that mailbox, they see nothing.
- **Protects:** guessing. The token is 256 bits of randomness, and the page answers identically
  for a made-up token, an expired link and a closed one. Five wrong codes lock the link.
- **Does not protect:** a compromised mailbox. Whoever reads that inbox gets both the link and
  the code. That is the trust boundary and it is the same boundary any emailed report has.

## Which rows and which facilities are reported

Added 2026-09-16 at James's request. Two filters, one of them already present.

**Rows.** An admission is reported when the patient was discharged home from the facility, is
not on hospice, the admission falls inside the window, and `Patient_Class__c` contains the word
named by `Required_Patient_Class__c`, which is set to `Inpatient`. Patient Class is free text
holding a comma separated list, so the match is "contains", not equality. Production holds
`Emergency`, `Emergency, Inpatient`, `Inpatient`, `Emergency, Observation, Inpatient`,
`Emergency, Observation`, `Observation`, `Observation, Inpatient` and blank. The four containing
`Inpatient` are reported; the rest, and blank, are not. Leave the config blank to report every
class.

**Facilities.** A facility is reported when its parent company has TCM ticked, the facility is
not excluded from TCM reporting, and, while `Require_Facility_TCM__c` is on, the facility itself
has TCM ticked. That filter already existed in the nightly job. It did **not** exist on the
Resend button, which queried the facility by id alone, so the button could send a report for a
facility the job would never touch. The button now applies the same three rules and says which
one it failed.

All three callers, the nightly batch, the Resend button and the page the PDF is rendered from,
now read one definition in `TCMReadmissionAdmissionScope`, rather than three copies of the same
WHERE clause. The run digest states the scope it used, so a change is visible in the mail rather
than only in the code.

Measured against production, last 30 days, for facilities already in TCM scope: rows fall from
555 to 268, and facilities receiving an email fall from 128 to 102.

## Architecture

### Components

| Component | State | Role |
|---|---|---|
| `Readmission_Report_Link__c` | exists, 8 new fields | One row per recipient per report. The row is the link: it holds the token hash, the code state, the unlock window and the counts. |
| `ContentVersion` on the Facility | exists, unchanged | The rendered PDF. Still filed against the facility, so purge and the resend's file reuse are untouched. |
| `ContentDistribution` | **removed** | No public file URL is created any more. This is the change that makes the code meaningful rather than decorative. |
| Site `TCM_Readmission_Portal` | new | Visualforce site, path prefix `/report`. Hosts the gate page and the PDF endpoint for unauthenticated recipients. |
| `TCMReadmissionReportGate` page + `TCMReadmissionGateController` | new | The only door. Request a code, enter it, see the report. The controller holds no logic. |
| `TCMReadmissionGateService` | new, `without sharing` | Every rule: live check, code issue and throttle, strikes and lockout, open cap, unlock window, PDF fetch. |
| `TCMReadmissionReportGateApi` | new, Apex REST `/tcm/report` | Streams the PDF inline or as a download, only inside the unlock window. |
| `TCMReadmissionAccessToken` | new | Token and code minting, SHA-256 hashing, constant-time comparison, shape checks. |
| `TCMReadmissionPortal` | new | Where the site lives: derived from the `Site` and `DomainSite` records, or overridden by `Portal_Base_Url__c`. |
| `TCMReadmissionPortalError`, `...Maintenance`, `...Unauthorized` pages | new | The site's error pages. Static, no controller. |
| `TCM_Readmission_Portal_Guest` permission set + guest profile | new | Page and class access for the guest user. No object, no field. |
| `TCMReadmissionLinkPublisher` | exists, changed | Mints a token per recipient, writes the row, supersedes the previous live link to the same address. |
| `TCMReadmissionEmailBuilder` | exists, changed | New body: the link plus "choose Email me a code" instructions. |
| `TCMReadmissionLinkAudit` | exists, simplified | Totals come from our rows. Closes rows left open at the cap. Counts locked links. |
| `TCMReadmissionReportPurge` | exists, changed | Reads `Content_Version_Id__c` instead of distributions. Same rule: one live link keeps the file. |
| `TCMDailyReadmissionBatch`, `TCMReadmissionResend`, LWC `tcmResendReadmissionReport` | exist, unchanged in shape | Same orchestration, different delivery primitive underneath. |

### New fields on `Readmission_Report_Link__c`

| Field | Type | Notes |
|---|---|---|
| `Access_Token_Hash__c` | Text(64), unique, external id, case sensitive | SHA-256 of the 32-byte random token. The raw token exists only in the URL in the recipient's email. |
| `Content_Version_Id__c` | Text(18), external id | The stored PDF this link serves. Shared by every recipient of the same report. |
| `Code_Hash__c` | Text(64) | SHA-256 of `token:code`. Salted with the token so a copy of the table cannot be tested offline without the URL. Cleared when the code is used. |
| `Code_Expires_At__c` | DateTime | Ten minutes after the code was sent. |
| `Code_Sent_At__c` | DateTime | A new code is refused for sixty seconds after this. |
| `Codes_Sent__c` | Number(2,0) | Five, then the row is locked. |
| `Failed_Attempts__c` | Number(2,0) | Cumulative across codes. Five, then the row is locked. Reset on success. |
| `Unlocked_Until__c` | DateTime | Ten minutes after a correct code. The PDF endpoint serves only inside this window. |

`Closed_Reason__c` gains `Locked` and `Superseded`. `Distribution_Id__c` is legacy, blank on
every row issued since. Nothing stores the raw token or the raw code, and neither is written to
a log or a debug statement.

### Access log: `Readmission_Report_Access__c` (new object, added 2026-09-15)

Master-detail child of the link row, one record per event, so a disclosure can be traced to a
device and a moment, not only to a mailbox and a count. Written by the site in system mode.
Staff read it through the two report permission sets; the guest has no access to it.

| Field | Notes |
|---|---|
| `Event__c` | Code sent, Code throttled, Code refused, Wrong code, Code expired, Locked, Opened, View limit reached, PDF fetched, Downloaded, Fetch refused |
| `IP_Address__c` | Caller IP as Sites reports it (`X-Salesforce-SIP`), falling back to `True-Client-IP`, then the first `X-Forwarded-For` hop |
| `User_Agent__c` | Browser or client, truncated to 255 |
| `Occurred_At__c` | When |
| `Detail__c` | Short note such as "Attempt 3 of 5", "Open 2 of 10", "Outside the unlock window". Never a code, never a token |

A made-up token has no row to log against and leaves no trace, which is deliberate: the log is
a record of what happened to real links, not a guest-writable table. Live-checked in lumDev:
an inline fetch and a download landed with the caller's public IP and two different user
agents. Field history on the link row stays on for the counters.

### Request flow

1. Recipient opens `https://<site>/report?t=<64-hex token>`.
2. The service hashes the token and looks up exactly one row by `Access_Token_Hash__c`.
3. No match, expired, or closed: one generic page, "This report is no longer available." The
   cases are deliberately indistinguishable. The REST endpoint answers the same text as a 404.
4. Live: the page shows the facility name, the report date, the link expiry and the masked
   address (`j***@example.com`), with one button, **Email me a code**.
5. Click: a six-digit code goes to `Recipient_Email__c`. The row stores the hash, the expiry and
   the send time only after the send succeeded. Asking again inside sixty seconds is refused
   with "A code was sent less than a minute ago". The sixth code request locks the row.
6. Enter the code. Wrong: `Failed_Attempts__c` goes up, "That code is not right. N attempts
   left." The fifth wrong code closes the row as `Locked`. Expired: "That code has expired. Ask
   for a new one.", no strike. Malformed input is rejected before comparison, no strike.
7. Right: if `Opens__c` already equals the cap, the row closes as `View limit reached` and the
   open is refused. Otherwise one open is counted, the code is cleared, `Unlocked_Until__c` is
   set ten minutes out, and the browser is redirected back to the link URL, which now renders
   the report page: PDF inline, **Download PDF**, **Open in a new tab**, and the time the view
   closes. A reload inside the window shows the report without another code.
8. The PDF is fetched from `/services/apexrest/tcm/report?t=<token>`; `&dl=1` counts a download
   and sets `Content-Disposition: attachment`. Fetches inside the window do not add opens. Once
   the window passes the endpoint answers 404 and the page goes back to step 4.

### Sandbox rule

In a sandbox a code is emailed only to an address on the sandbox redirect list. The rows a
sandbox run issues already point at the testers, so this only bites a row created by hand, and
the page then says so instead of sending.

### Why the guest user is safe here

The service runs `without sharing` because a guest user cannot hold record access through
org-wide defaults and the row must be reachable. That widens nothing: the only path to a row is
presenting the token whose hash it stores. The guest permission set and profile grant the two
pages and the six classes, and nothing on any object or field. The service reads the row and the
stored `ContentVersion` in system mode. Nothing on the site queries `Facility__c`, `Patient__c`
or `Hospital_Admission__c`; the PDF was rendered by the job inside the org. A test runs the whole
flow under `System.runAs` as the real site guest user.

## Changes to existing code

- **Publisher:** one token and one row per recipient, the row written before any email is built,
  so a row that could not be written is a recipient who is not emailed. Before the insert it
  closes every live link to the same address for the same facility as `Superseded`, so only the
  newest link works. No site URL means no links and no stored file, reported per facility.
- **Email builder:** the button links to the site; the body explains the code step; the cap and
  the expiry are stated as before; "reply to this email for a new link" stays.
- **Audit:** the platform view query is gone. Opens and downloads are written by the site at the
  moment they happen, so the sync adds up recent rows for the digest, closes a row left open at
  the cap once its unlock window has passed, and counts locked rows. The digest gains a "Links
  locked after wrong codes" line.
- **Purge:** unchanged in logic. "Every link to this file is dead" is read from our rows: a row
  that is expired or closed is dead; one live row keeps the file for everyone.
- **Resend:** unchanged. Reissuing mints new links and the publisher supersedes the old ones.

## Edge cases

| Case | Behaviour | Live-tested |
|---|---|---|
| Made-up, expired, locked or superseded link | Generic unavailable page; endpoint 404 | yes |
| Second code inside sixty seconds | Refused, first code still valid | yes |
| Sixth code request | Row locked | unit test |
| Wrong code | Strike, attempts left shown | yes |
| Fifth wrong code | Row locked, right code no longer helps | yes |
| Strikes across codes | Carry over; a new code is not a fresh start | unit test |
| Expired code, entered correctly | Refused, no strike, back to request | yes |
| Correct code | One open, code cleared, ten-minute unlock, PDF inline | yes |
| Reload inside the window | Report again, no new code | yes |
| Reload after the window | Request screen; endpoint 404 | yes |
| Download | Counted separately; refused when config says no | yes / unit test |
| Cap reached | Next correct code refused, `View limit reached` | yes |
| Cap unset (0) | No cap | unit test |
| File purged, row still live | Endpoint 404, row survives | unit test |
| Reissue by Resend button or daily job | New rows live, previous rows `Superseded` | yes, both |
| Sandbox row pointing at a non-tester address | Code refused with a sandbox message | yes |
| Two tabs open at once | Two fetches, one open | by design |
| Site not registered in the org | Every page shows the maintenance page | yes, see checklist |

## Testing

139 Apex tests across 13 classes pass in lumDev. New: `TCMReadmissionAccessTokenTest`,
`TCMReadmissionGateServiceTest` (service, controller, REST endpoint, guest `runAs`). Rewritten:
publisher, audit and purge tests. Patched: resend and batch tests. 7 Jest tests unchanged.

Live in lumDev on 2026-09-15, in an isolated browser with no Salesforce session: every row in
the edge-case table marked "yes", plus the Resend button and a full `Database.executeBatch` run
that issued links to the two testers and superseded the button's links.

## Operating notes

- `Portal_Base_Url__c` on `TCM_Report_Config__mdt` is optional. Blank means the URL is derived
  from the `TCM_Readmission_Portal` site and its domain in whatever org the code runs in.
- The code email is sent from the configured org-wide address when the guest user may use it,
  and as the site guest user otherwise. In lumDev the org-wide address is not open to all
  profiles, so codes go out as the guest user.
- The scheduled job `TCM Email Readmission` holds a deploy lock on the whole chain. Abort it,
  deploy, reschedule `0 0 8 ? * 2,3,4,5,6`. Done that way today; it is rescheduled.
- `TCMReadmissionReportPurge` is still not scheduled. Schedule once in each org:
  `System.schedule('TCM Readmission Report Purge', '0 0 3 ? * *', new TCMReadmissionReportPurge());`

## Production checklist

Every step is a human action.

1. Register Salesforce Sites in production once: Setup > Sites, tick the terms, **Register My
   Salesforce Site Domain**. The domain `data-efficiency-9627.my.salesforce-sites.com` already
   exists. Until this is done every site page shows the maintenance page (this is exactly what
   happened in lumDev and was fixed by registering).
2. Edit `sites/TCM_Readmission_Portal.site-meta.xml`: `subdomain` from
   `data-efficiency-9627--partialsb` to `data-efficiency-9627`.
3. Deploy in this order, or as one deploy with the site last: fields and picklist values,
   classes, pages, permission sets, the guest profile file, then the site.
4. Assign `TCM_Readmission_Portal_Guest` to the site's guest user (`Site.GuestUserId`).
5. Set the org-wide address `tcm@luminacare.com` to allow all profiles, or the code email will be
   sent as the guest user.
6. Schedule the purge job. Confirm `TCM Email Readmission` is scheduled and `Is_Active__c` is
   the intended value.
7. Open one real link in a private window and walk the flow once before telling facilities.

## Out of scope

Experience Cloud with per-facility logins, a report history list, per-facility passwords stored
on the record, SMS codes, and IP capture. Each is additive on top of this.
