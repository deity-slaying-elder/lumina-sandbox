# Facility Scheduling sandbox scripts

Anonymous Apex used to stand this feature up in lumDev. Kept because a later ticket will
want to reseed, and because the DLRS back-fill has to be run by hand once per org.

Run in order. Everything is scoped to a `TST ` name prefix so it can be removed again
without touching anything real.

| Script | What it does |
|---|---|
| `seed.apex` | Parent companies, facilities, providers, state licences, facilitators and patients. Shapes follow production: names like "<Place> Health Care Center", states across IL, KS, MO and OH, census in the low hundreds. Every patient is invented; none is copied from production. |
| `visits.apex` | Books visits across the current month, deliberately uneven so empty days, single days and the "+n more" overflow path are all visible. |
| `calc.apex` | Back-fills the three DLRS rollups. Realtime mode only maintains them from the next Patient DML onwards, so existing facilities stay at zero until this runs. |
| `cleanup.apex` | Removes everything the seed created, so it can be run again from clean. |

## Two things that will bite

Programme status fields are formulas. `TCM_Status__c` reads `IF(TCM__c, "Active", ...)`,
so the seed sets the checkbox underneath, never the status.

The notifier fires on visit insert, but the seeded facilitators and providers carry no
email address, so nothing is actually sent. That is deliberate: lumDev is a Partial Copy
and the real provider records in it hold real addresses, so a careless seed would email
actual clinicians. To test delivery, put your own address on one seeded `TST ` provider
and move that visit.
