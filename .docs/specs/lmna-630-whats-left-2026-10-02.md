# LMNA-630 — what is left

State of the facility scheduling work as of 2026-10-02, written so a session on any
machine can answer "is anything still outstanding here" without the original context.

Shipped: `6cf762a` (feature) and `35bd3c1` (sandbox scripts) on `main`. Branch
`LMNA-630-scheduling-ui` points at the same work. Deployed to **lumDev only**; nothing in
this ticket has gone to production.

---

## 1. The DLRS back-fill was never verified — do this first

Patient counts moved from live aggregate queries to three DLRS rollups (Patient to
Facility, into `Census__c`, `Seen__c`, `Consented__c`), at Chayim's request, for reporting
and compute time.

The rollups and the `dlrs_PatientTrigger` child trigger are deployed to lumDev and the
back-fill was queued with `.docs/scripts/lmna-630/calc.apex`. **Its results were never
compared against the numbers the screen used to compute.** If the criteria are wrong, the
stored counts are quietly wrong everywhere, including on any report built on them.

What to check: for a sample of facilities, the stored fields should equal

- Census: `Patient__c` where `Status__c = 'Active'`
- Seen: the above with `Count_of_Initial_VIsits__c > 0` (the API typo is real)
- Consented: the above with `Consent_Status__c LIKE 'Approved%'`

scoped so `Consented <= Seen <= Census` always holds. Definitions agreed 2026-09-16 and
mirrored in `FacilitySchedulingController.countsFor`.

Two things to know before changing anything here. `Patient__c.Facility__c` is a **lookup,
not master-detail**, in both dev and prod, so native roll-up summary fields were never an
option. And DLRS realtime only maintains the fields from the next Patient DML onwards, so
the back-fill has to be run by hand once per org.

## 2. No notification email has ever been watched arriving

`OnboardingVisitNotifier` is deployed and has four Apex tests, but delivery has never been
observed end to end.

It was not tested on purpose: lumDev is a Partial Copy and its provider and facilitator
records carry **real production email addresses**, so firing the notifier against them
would email actual clinicians about a test booking.

The safe test: put your own address on `Email__c` of one seeded `TST ` provider, move that
provider's test visit by an hour, and watch for the mail. That sends to you and nobody
else.

## 3. Two drafts to Chayim are written but unsent

Both are in the session transcript, neither has been sent anywhere. One confirms the chip
layout change (programmes under the time, status beside it). The other answers his four
follow-up questions: who notifications go to, that patient counts are rollups now, that a
provider needs a licence covering **every** programme on a visit rather than one, and that
Community Full-Time and IPV Onboarding do exist as licence programme values.

## 4. The demo film is unfinished

Source is vendored at `.docs/video/lmna-630/`, working copy is the sibling folder
`LUMINA/LMNA-630-demo-video/`. Its README has the detail. Short version: chapters one, two
and five all open on the same worklist screen; marker boxes can clip at frame edges when
the camera is zoomed; there is no sound on individual UI actions; and the ship gates (cut
rate, dead air, loudness, type floor) were never run.

Narrate with **local Kokoro** for every preview and review take. Gemini is for the final
cut only, and only when asked, because the free tier is about ten calls a day.

## 5. The v1 spec is stale

`.docs/specs/LMNA-630-scheduling-ui-and-round-two-qa-2026-09-30.md` still describes the
datatable design that was replaced. Either rewrite it against the shipped component or
delete it, because right now it contradicts the code.

## 6. Nine fixes are owed to the video skill

Found by using it. They live in `~/.claude/skills/building-demo-walkthrough-videos/`,
which a Claude session cannot edit (the harness treats it as self-modification), so a
human applies them. The headline ones: the voice rule is backwards (it says Gemini first,
Kokoro as fallback; practice is the reverse), `kit/setup-assets.sh` dies partway and never
copies the UI kit, the kit hardcodes 30fps in three files which silently desyncs captions
and sound in a 60fps film, and the annotation guidance recommends an outline around letters
where a highlighter swipe behind them is what actually reads.

---

## Two production data gaps that make this inert in prod

Not defects in this ticket, but it does not deliver value until both are fixed.

- There are **no `State License` records at all** in production, so the provider filter
  returns nobody.
- The programme checkboxes are **false on all 194 onboarding facilities**, so nothing
  pre-fills and every programme reads "not active at this facility".

Raised, not yet actioned. Someone needs to decide where licence data comes from and load
it, and the facility records need filling in.

## Open questions for Dorothy or Chayim

- Which programmes genuinely conflict? Only BHI/CoCM is wired, and that was a provisional
  guess.
- Community Full-Time, IPV Onboarding, RPM, PCM and APCM can be put on a visit but have no
  field on the facility record, so they can never pre-fill. Either they need fields or
  they should come off the list.
- Should notifications also copy coordinators or a shared mailbox? Today it is the
  facilitator and the providers on the visit.
