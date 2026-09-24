# LMNA-581 production runbook

Written 2026-09-17. Every step here is a human action. Nothing in this ticket has ever touched
production, and the checks below were made read-only against `lumProd` on 2026-09-17.

Branch: `lmna-581-expiring-link`. Validated against `lumDev` as a check-only deploy: stage 1
resolves to 91 components with zero errors.

## Stop before you start

**Production org-wide Apex coverage reads 8 percent.** Salesforce refuses any production Apex
deploy below 75 percent. That 8 percent is computed from a partial test run, only 46 of the
org's 704 classes have coverage rows at all, so the true figure is unknown until a full
validation runs. **Run step 2 before you plan a window.** If it comes back under 75 percent,
this feature cannot ship until the org's existing untested Apex is covered, and that is a
separate piece of work.

## What is not in the payload, and why

| Left out | Reason |
|---|---|
| `Facility__c-Facility Layout` | Production's copy was changed on 2026-09-10 by Dorothy Amador and carries **13 fields the repo copy does not have**, including `Exclude_from_TCM_Reporting__c`, `Facility_Type__c`, `Leadership_Group__c` and `Dozee__c`. Deploying the repo version would strip them. Add the two new pieces by hand instead, step 7. |
| `customMetadata/TCM_Report_Config.Default` | This org rejects a customMetadata record inside a deploy with a bare `UNKNOWN_EXCEPTION`. Proven on 2026-09-16 against the unchanged committed file, so it is the org, not our edit. Created by Apex instead, step 4. |
| `TcmSettings`, `TcmAutomationPermissionsTest` | These belong to LMNA-580, not this ticket. No LMNA-581 class references them. |
| `Lumina_Welcome_Header` | Already in production, same file, 10,759 bytes. The gate page resolves it there. |

## What production already has

Checked read-only: `Facility__c`, `Patient__c` and `Hospital_Admission__c` all exist with every
field this code reads, `Hospital_Admission__c.Patient_Class__c` included. No TCM Apex class, no
Visualforce page, **no Salesforce Site registered**, and **no org-wide email address at all**.

## The steps

**1. Check out the branch.**

```bash
git checkout lmna-581-expiring-link
```

**2. Validate against production. Do this first, on its own day.**

```bash
sf project deploy start --target-org lumProd \
  --manifest manifest/lmna-581-prod-1-main.xml \
  --dry-run --test-level RunLocalTests --wait 60 --verbose
```

This deploys nothing. It reports the real org-wide coverage. If it fails on coverage, stop and
raise it, the rest of this runbook is blocked.

**3. Deploy stage 1.**

```bash
sf project deploy start --target-org lumProd \
  --manifest manifest/lmna-581-prod-1-main.xml \
  --test-level RunLocalTests --wait 60
```

91 components: 31 Apex classes, 5 pages, 3 objects, 1 layout, 1 quick action, 1 Lightning
component, 3 permission sets. Nothing runs on its own: no trigger, no flow, and no class
schedules itself.

**4. Create the config record.**

```bash
sf apex run --target-org lumProd --file scripts/apex/lmna-581-create-prod-config.apex
```

`Is_Active__c` is false in that script on purpose. Until the record exists, any attempt to run
the job throws a named error rather than sending anything, which is the intended failure.

Then prove the record landed:

```bash
sf apex run test --target-org lumProd --class-names TCMReportConfigTest --wait 10
```

`TCMReportConfigTest.deployedRecordSuppliesTheExpectedValues` checks the real record, which
cannot exist during step 3 because the record is created here, after it. The test skips itself
with a warning while the record is absent and asserts in full once it is present, so it passes
in step 3 and actually verifies the values here.

**5. Create and verify the sending address.** Setup, Organisation-Wide Addresses, add
`tcm@luminacare.com`, have someone with that mailbox click the verification link, and allow all
profiles so the site guest user can send the one-time code from it. Production currently has
none. Without it the report still sends, as the running user, and says so in the digest.

**6. Register Salesforce Sites, once.** Setup, Sites, tick the terms, **Register My Salesforce
Site Domain**. The domain `data-efficiency-9627.my.salesforce-sites.com` already exists. Skip
this and every page of the site returns a maintenance message, which is exactly what happened in
the sandbox until it was registered there.

**7. Edit the production Facility layout by hand.** Setup, Object Manager, Facility, Page
Layouts, Facility Layout. Add both:

- the **Resend Readmissions Report** action to the Salesforce Mobile and Lightning Experience
  Actions section,
- the **Readmission Report Links** related list.

Do not deploy the repo's layout file. See the table above.

**8. Point the site at production and deploy it.**

```bash
# change the subdomain from the sandbox one to production
sed -i '' 's|<subdomain>data-efficiency-9627--partialsb</subdomain>|<subdomain>data-efficiency-9627</subdomain>|' \
  force-app/main/default/sites/TCM_Readmission_Portal.site-meta.xml

sf project deploy start --target-org lumProd \
  --manifest manifest/lmna-581-prod-2-site.xml --wait 30
```

Then the guest profile the site just created:

```bash
sf project deploy start --target-org lumProd \
  --manifest manifest/lmna-581-prod-3-guest-profile.xml --wait 30
```

**9. Assign the guest permission set.** Setup, Sites, TCM Readmission Portal, Public Access
Settings, or assign `TCM_Readmission_Portal_Guest` to the site's guest user directly. Until this
is done the site pages fail closed for visitors.

**10. Assign the staff permission sets.** `TCM_Readmission_Report_Operator` to whoever may press
Resend, `TCM_Readmission_Reports` to anyone who only needs to read the audit trail.

**11. Prove one link by hand before anyone relies on it.** Pick one facility, press Resend, open
the link in a private window, request a code, enter it, download the report, then check the
link record's Access Log shows the open and the download with an IP address.

**12. Schedule the jobs.**

```bash
sf apex run --target-org lumProd --file scripts/apex/lmna-581-schedule-prod-jobs.apex
```

The daily job still sends nothing while `Is_Active__c` is false.

**13. Turn it on.** Edit the `Default` custom metadata record in Setup and tick `Is_Active__c`.
This is the only step that starts real mail to real facilities. Do it when Lumina is ready, not
as part of the deploy.

## Redeploying later

The scheduled job holds a deploy lock on its whole dependency chain. Abort `TCM Email
Readmission` in Setup, Scheduled Jobs, deploy, then re-run step 12.

## Confirm before you turn it on

Both filters change who receives mail. Measured against production, last 30 days, for facilities
already inside TCM scope: rows fall from 555 to 268, and facilities receiving an email fall from
128 to 102. Twenty-six facilities that get a daily readmissions email today would stop. Chayim
should confirm that is intended before step 13.
