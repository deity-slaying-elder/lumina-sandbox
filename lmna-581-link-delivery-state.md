---
name: lmna-581-link-delivery-state
description: "LMNA-581 state as of 2026-09-23: phase two (Site gate page + ten-minute code) built and unlock now bound to the reader's browser; prod untouched; operational gotchas (Apex REST sees no cookies, Sites registration, cron lock, guest access)."
metadata: 
  node_type: memory
  type: project
  originSessionId: 3f272bcd-13de-4637-9d77-3d2cbf2a6eda
  modified: 2026-09-22T23:11:31.284Z
---

Phase one (expiring public link, resend button, purge job) shipped 2026-09-10. Phase two
replaced the public link on 2026-09-15 after Chris and Chayim pushed on link security: the
email now carries a link to a Salesforce Site page (`TCM_Readmission_Portal`, prefix `/report`)
which emails a six-digit code to the address on file when asked; the code lives 10 minutes, a
correct code counts one open and unlocks the PDF for 10 minutes. Chayim chose the 10-minute
request-at-view code over the same-email PIN. James then asked for audit logging with IP:
`Readmission_Report_Access__c` (child of the link row) logs every event with IP, user agent,
time and a short detail. Site pages, PDF header and email buttons use Lumina's own branding
(static resource `Lumina_Welcome_Header`, blue #1f5fe0, navy #30385c), never Propela's. Everything is on branch `lmna-581-expiring-link`,
deployed to lumDev, live-tested in a clean browser. Spec:
`.docs/specs/lmna-581-pin-gated-portal-2026-09-14.md` (has the production checklist).

The unlock is bound to the reader's browser as of 2026-09-23, commit 20758c8. Before that an
unlock was ten minutes of time alone, so the emailed link opened the report for anyone holding
it inside the window. A correct code now mints a 256-bit key, stores its hash in
`Readmission_Report_Link__c.Unlock_Browser_Hash__c` and hands it to that browser.

**Apex REST never receives the Cookie header.** Proven in lumDev 2026-09-23 against a staged
unlock: the correct cookie value was refused exactly as no cookie was, four ways, all 404. So
the key rides as a cookie for the Visualforce page (where `getCookies()` does work, under an
`apex__` prefix) and as a `k` query parameter for `/services/apexrest/tcm/report`. The page
writes `k` into the PDF URL it renders; the post-verify redirect carries `k` too so a
cookie-blocked browser does not loop back to the code form; a small script in the page strips
`k` from the address bar wherever the cookie was accepted.

Production is untouched and stays a human deploy. Prod prerequisites: register Salesforce
Sites once in Setup, change the site subdomain in the metadata, assign
`TCM_Readmission_Portal_Guest` to the guest user, open the org-wide address to all profiles.

Operational facts that cost time to learn:

- A Salesforce Site shows only its maintenance page (HTTP 503 on every VF page, while Apex
  REST still works) until Sites is registered in Setup > Sites. lumDev had the domain but not
  the registration; I registered it on 2026-09-15.
- The scheduled job `TCM Email Readmission` holds a deploy lock on its whole dependency chain.
  Abort, deploy, reschedule `0 0 8 ? * 2,3,4,5,6`. `Is_Active__c` is false; a manual
  `Database.executeBatch` still sends (redirected to the testers in a sandbox).
- `UserInfo.getSessionId()` returns nothing for a Site guest user, so session binding is not
  available. That attempt was built, proven dead in a live two-browser test, and removed.
- Fields created during a failed deploy persist without FLS for the deployer; queries then say
  "No such column". Fix by granting the field in a permission set.
- CustomSite metadata at API 65: no `referrerPolicy`, no `cspUpgradeInsecureRequests`;
  `referrerPolicyOriginWhenCrossOrigin` is required.
- Lightning caches LWC modules hard; verify in an isolated browser context.
- Test data in lumDev: `ZZ Claude Test Facility` (a01Ou00000slDi4IAE) with fake patients
  "ClaudeTest"; link RRL-00000044 is the one used for gate testing.
- 158 TCM tests pass in lumDev. A full `RunLocalTests` run there also shows 13 failures in
  other teams' classes (`PatientIntakeWorklistControllerTest` MIXED_DML,
  `BulkOpportunityCreatorControllerTest`, `ThoroughCareEmailQueueableTest`). They are unrelated
  to TCM but will block a prod deploy run at `RunLocalTests` if they fail there too.
- Production has 326 enrolled facilities, 159 with no administrator or DON email. Nobody owns
  that gap yet. See [[propela-jira-project-keys]].

Drift is real on this project. On 2026-09-18 someone changed five classes directly in lumDev,
a global Cc, the report's TCM Program column, and the code-request cap from 5 to 10, and the
branch knew nothing about it, so the production payload would have reverted their work. Diff
every TCM class against the org before trusting the branch or building a deploy payload. A
retrieve with repeated `--metadata` flags silently returns only package.xml; use a manifest and
compare after stripping CRLF, or every file falsely reads as changed.

Production facts checked read-only 2026-09-17: prod holds Facility, Patient and Hospital
Admission with every field this code reads, including `Patient_Class__c`, and none of this
feature. No Site registered, no org-wide email address at all, and org-wide Apex coverage reads
8 percent off a partial run, which gates any Apex deploy at 75 percent. The branch's Facility
layout is older than prod's and would strip 13 fields, so it stays out of the payload and the
Resend button and related list go on by hand. The custom metadata record cannot deploy in this
org at all, so it is created by the Apex Metadata API after the first deploy, and the config
test skips itself while that record is absent.

Prod digest test: `scripts/apex/lmna-581-prod-digest-{1-arm,2-check,3-run,4-restore}.apex` are
committed and ready but have never been run. Prod writes are James's to execute. Step 2 refuses
to continue unless exactly one facility is in scope, and the arm step points
`Required_Patient_Class__c` at the `ZZSMOKE` marker so no real facility qualifies.
