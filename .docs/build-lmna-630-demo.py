#!/usr/bin/env python3
"""
Builds the LMNA-630 facility scheduling feature demo: a self-contained Propela-branded
HTML page answering the five questions Chayim asked, each with the screenshot that shows
the answer.

Presentation follows the LMNA-581 walkthroughs: real screenshots inside CSS macOS window
frames, everything base64-embedded so the file travels on its own.

The screenshots were captured in lumDev at 1440x980 and cropped below the workspace tab
strip, because those tabs carry the names of unrelated records.

Re-runnable. Usage: python3 .docs/build-lmna-630-demo.py
"""
import base64, html, pathlib

DOCS = pathlib.Path(__file__).resolve().parent
SHOTS = DOCS / "shots-lmna-630"
BRAND = pathlib.Path.home() / ".claude" / "brand"
OUT = DOCS / "lmna-630-scheduling-demo-2026-10-01.html"
WIDTH = 1120

SLATE, NAVY, YELLOW, BLUE = "#24323f", "#0C263B", "#f5fd7e", "#b9d8f5"


def b64(path):
    return base64.b64encode(pathlib.Path(path).read_bytes()).decode()


def img(name):
    return f"data:image/png;base64,{b64(SHOTS / name)}"


def logo():
    p = BRAND / "logos" / "main" / "propela-main-yellow-white-900.png"
    return f"data:image/png;base64,{b64(p)}"


def mac(title, shot, caption):
    return f"""
    <figure class="macwrap">
      <div class="mac">
        <div class="macbar">
          <span class="dot r"></span><span class="dot y"></span><span class="dot g"></span>
          <span class="mactitle">{html.escape(title)}</span>
        </div>
        <img src="{img(shot)}" alt="{html.escape(caption)}">
      </div>
      <figcaption>{caption}</figcaption>
    </figure>"""


# ----------------------------------------------------------------- the five questions
QUESTIONS = [
    dict(
        n=1,
        q="Can we attach more than one program?",
        verdict="Yes",
        tone="ok",
        body="""
      <p>A visit now carries a list of programmes rather than one. The booking dialog shows every
      programme as a checkbox and tallies the selection underneath, and the calendar prints the
      full list on the event.</p>
      <p>Underneath, the visit holds the whole set. The first programme is still written to the
      single-value field the existing automation reads, so nothing downstream had to change, and
      the complete list is written to the description.</p>""",
        shot="03-modal-programs.png",
        shotcap="Two programmes on one visit. The line under the checkboxes reads "
        "<b>2 programs on this visit: TCM, BHI</b>, and the calendar event for the same "
        "booking prints both.",
        shottitle="Edit facility onboarding, lumDev",
    ),
    dict(
        n=2,
        q="Are we able to have notifications sent out if changes to the schedule are made?",
        verdict="Built, not yet proven end to end",
        tone="warn",
        body="""
      <p>The notifier is written, deployed and unit tested. It emails the facilitator and every
      provider on the visit when the booking is created, moved, cancelled, or when someone is added
      to or removed from the roster. A save that touches nothing anyone cares about stays silent.</p>
      <p>It deliberately buffers. Creating a visit and writing its provider rows happen in the same
      transaction and both fire triggers, so without the buffer a provider would get two emails for
      one booking. Four Apex tests cover this: one for a new booking, one for a reschedule, one
      proving a visit cancelled twice over only emails once, and one proving an unrelated save
      emails nobody.</p>
      <p class="note warn"><b>What is not proven.</b> No email has been watched arriving in an
      inbox yet. I have not triggered a live send, and on purpose: lumDev is a Partial Copy, so the
      provider and facilitator records carry real email addresses from production. Firing the
      notifier against them would email real clinicians about a test booking.</p>
      <p>The safe way to prove it is a controlled test. Put your own address on one of the seeded
      test provider records, move that test visit by an hour, and watch the mail arrive. That sends
      to you and nobody else. Say the word and I will run it.</p>""",
        shot=None,
    ),
    dict(
        n=3,
        q="Can the programs automatically populate with what is active with the selected facility?",
        verdict="Yes",
        tone="ok",
        body="""
      <p>Pick a facility and the programmes it runs are ticked for you. The rest stay available but
      are labelled, so the dialog tells you why a box is empty instead of leaving you guessing.</p>
      <p>There are two different reasons a programme is not ticked, and the dialog distinguishes
      them. <b>Not active at this facility</b> means the facility record says the programme is off.
      <b>Not tracked on the facility record</b> means there is no field for it at all, which is the
      case for Community Full-Time and IPV Onboarding. You can still tick either one by hand, since
      the facility record is not always ahead of reality.</p>""",
        shot=None,
        note="The screenshot under question 1 shows this. TCM and BHI arrived ticked because the facility "
        "runs them. CCM, CoCM, Telepsych and After Hours Telehealth are marked "
        "<i>Not active at this facility</i>, and Community Full-Time and IPV Onboarding are marked "
        "<i>Not tracked on the facility record</i>.",
    ),
    dict(
        n=4,
        q="Will it show only providers licensed in that facility state as available to schedule?",
        verdict="Yes",
        tone="ok",
        body="""
      <p>The provider picker is filtered to people who hold a current state licence for the
      facility's state and who are approved for every programme on the visit. The filter explains
      itself in a line under the picker rather than silently shortening the list, so nobody is left
      wondering where a colleague went.</p>
      <p>In the example below the facility is in Ohio and the visit covers TCM and BHI. Two providers
      qualify. The line underneath accounts for all 321 who do not: 318 are not licensed in Ohio and
      3 are licensed but not approved for every programme on the visit.</p>""",
        shot="04-provider-filter.png",
        shotcap="The picker offers two providers. The line underneath reads <b>0 of 4 slots used. "
        "Showing providers licensed in Ohio and approved for TCM and BHI. 321 hidden: 318 not "
        "licensed here, 3 not approved for every program.</b>",
        shottitle="Provider eligibility, lumDev",
    ),
    dict(
        n=5,
        q="Will it automatically populate patient counts for the attached facility?",
        verdict="Yes",
        tone="ok",
        body="""
      <p>Counts come from the facility and are drawn, not printed, so a coordinator reads the shape
      of a facility at a glance instead of comparing three columns of numbers. Each row shows the
      census with how many have been seen and how many have consented laid over it.</p>
      <p>The same three numbers appear in the booking dialog, so you have them in front of you while
      you decide who to send and for how long.</p>""",
        shot="01-worklist.png",
        shotcap="Census, seen and consented per facility, filled in from the facility record. The "
        "booking dialog repeats them as Census, Seen and Consented tiles.",
        shottitle="Onboarding worklist, lumDev",
    ),
]

qs = []
for q in QUESTIONS:
    shot = (
        mac(q["shottitle"], q["shot"], q["shotcap"])
        if q.get("shot")
        else ""
    )
    note = f'<p class="note">{q["note"]}</p>' if q.get("note") else ""
    qs.append(
        f"""
    <div class="step">
      <div class="snum">{q['n']:02d}</div>
      <div class="sbody">
        <h3>{html.escape(q['q'])}</h3>
        <p class="verdict {q['tone']}">{q['verdict']}</p>
        {q['body']}
        {note}
        {shot}
      </div>
    </div>"""
    )

QBLOCKS = "\n".join(qs)

HTML = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>LMNA-630 Facility Scheduling, feature demo</title>
<style>
  * {{ box-sizing:border-box }}
  body {{ margin:0; color:#1a1a1a; font-size:14px; line-height:1.55;
    font-family:'DM Sans',-apple-system,'SF Pro Text',Tahoma,Helvetica,Arial,sans-serif;
    background:#f4f6f8; }}
  .page {{ width:{WIDTH}px; margin:0 auto }}
  h1,h2,h3 {{ font-family:'Antonia Variable',Georgia,'Times New Roman',serif; font-weight:400 }}

  header {{ background:{SLATE}; color:#fff; padding:32px 40px 36px; border-bottom:4px solid {YELLOW} }}
  .htop {{ display:flex; justify-content:space-between; align-items:flex-start; gap:24px }}
  header img.logo {{ height:36px }}
  .meta {{ font-family:'SF Mono',Menlo,monospace; font-size:10.5px; letter-spacing:.09em;
    text-transform:uppercase; color:{BLUE}; text-align:right; line-height:1.75 }}
  header h1 {{ margin:22px 0 10px; font-size:33px; line-height:1.14; letter-spacing:-.01em }}
  header p.sub {{ margin:0; max-width:76ch; color:#cfe0ee; font-size:15px }}

  .bluf {{ background:{NAVY}; color:#fff; padding:22px 40px 24px; border-bottom:1px solid #0a1e30 }}
  .bluf p.big {{ margin:0 0 10px; font-size:17px; font-weight:700; line-height:1.4 }}
  .bluf ul {{ margin:0; padding-left:20px; color:#cfe0ee; font-size:14px }}
  .bluf li {{ margin:3px 0 }}

  .strip {{ display:grid; grid-template-columns:1fr 1fr 1fr; background:#fff; border-bottom:1px solid #dde2e7 }}
  .strip > div {{ padding:16px 40px; border-right:1px solid #eceef1 }}
  .strip > div:last-child {{ border-right:0 }}
  .strip b {{ display:block; font-family:'SF Mono',Menlo,monospace; font-size:10px; letter-spacing:.09em;
    text-transform:uppercase; color:#7b8794; margin-bottom:4px }}
  .strip span {{ font-size:13px; color:#2b3743 }}

  main {{ padding:30px 40px 40px }}
  h2.sh {{ font-size:21px; margin:40px 0 3px; color:{SLATE}; display:flex; align-items:center; gap:11px }}
  h2.sh:before {{ content:''; width:5px; height:22px; background:{YELLOW}; border-radius:3px }}
  p.intro {{ margin:9px 0 0; max-width:84ch; color:#4d5a66 }}

  .step {{ display:flex; gap:18px; padding:22px 24px; margin-top:16px; border-radius:6px;
    background:#fff; border:1px solid #dde2e7 }}
  .snum {{ flex:0 0 34px; height:34px; border-radius:4px; color:{YELLOW}; background:{SLATE};
    font-family:'SF Mono',Menlo,monospace; font-size:13.5px; font-weight:700;
    display:flex; align-items:center; justify-content:center }}
  .sbody {{ flex:1; min-width:0 }}
  .sbody h3 {{ margin:3px 0 6px; font-size:18px; color:{SLATE} }}
  .sbody p {{ margin:0 0 11px }}
  p.verdict {{ display:inline-block; font-family:'SF Mono',Menlo,monospace; font-size:11px;
    letter-spacing:.05em; text-transform:uppercase; padding:5px 10px; border-radius:3px; margin:0 0 12px }}
  p.verdict.ok {{ background:#e8f5ee; color:#1a5c37; border:1px solid #bfe0cd }}
  p.verdict.warn {{ background:#fdfbe8; color:#6b5a0e; border:1px solid #e3e2b4 }}

  .macwrap {{ margin:14px 0 0 }}
  .mac {{ border-radius:8px; overflow:hidden; background:#fff; border:1px solid #c9d0d8 }}
  .macbar {{ display:flex; align-items:center; gap:7px; padding:9px 13px;
    background:linear-gradient(180deg,#f6f6f7,#e8e9ec); border-bottom:1px solid #d8dade }}
  .dot {{ width:11px; height:11px; border-radius:50%; display:inline-block }}
  .dot.r {{ background:#ff5f57 }} .dot.y {{ background:#febc2e }} .dot.g {{ background:#28c840 }}
  .mactitle {{ margin-left:9px; font-size:11.5px; color:#5f6672;
    font-family:'SF Mono',Menlo,monospace; letter-spacing:.02em }}
  .mac img {{ display:block; width:100%; height:auto }}
  figcaption {{ font-size:12.5px; color:#5b6b7a; margin-top:9px; line-height:1.5 }}
  figure {{ margin:0 }}

  p.note {{ margin:10px 0 13px; font-size:12.5px; padding:11px 14px; border-radius:4px;
    background:#eef4fb; color:{NAVY}; border:1px solid #cddff0; border-left:3px solid #7ea9d0 }}
  p.note.warn {{ background:#fdfbe8; border-color:#e3e2b4; border-left-color:#c9c96a; color:#5a5310 }}

  .gap {{ padding:20px 24px; margin-top:16px; border-radius:6px; background:#fff;
    border:1px solid #dde2e7; border-left:4px solid #c23934 }}
  .gap h3 {{ margin:0 0 7px; font-size:17px; color:#a62f26 }}
  .gap p {{ margin:0 0 8px }}
  .gap p:last-child {{ margin-bottom:0 }}

  table {{ width:100%; border-collapse:separate; border-spacing:0; margin:14px 0 0; font-size:13px;
    background:#fff; border:1px solid #dde2e7; border-radius:5px; overflow:hidden }}
  th {{ background:{SLATE}; color:#fff; text-align:left; padding:10px 12px; font-size:10.5px;
    letter-spacing:.06em; text-transform:uppercase; font-weight:500 }}
  td {{ padding:10px 12px; border-top:1px solid #eceef1; vertical-align:top }}
  tr:nth-child(even) td {{ background:#fafbfc }}
  code {{ font-family:'SF Mono',Menlo,monospace; font-size:12px; background:#eef1f4;
    padding:1.5px 5px; border-radius:4px }}
  .ok {{ color:#1e6b3f; font-weight:700 }} .bad {{ color:#c23934; font-weight:700 }}

  p.vid {{ margin:0; background:#eef4fb; border-bottom:1px solid #cddff0; color:{NAVY};
    padding:13px 40px; font-size:13px }}
  footer {{ background:{SLATE}; color:#9fb3c4; padding:18px 40px 22px; font-size:12px }}
</style></head>
<body><div class="page">

<header>
  <div class="htop">
    <img class="logo" src="{logo()}" alt="Propela">
    <div class="meta">LMNA-630<br>Facility scheduling<br>1 October 2026</div>
  </div>
  <h1>Facility Scheduling, feature demo</h1>
  <p class="sub">Answering the five questions raised on the scheduling component, each with the
  screen that shows the answer. Everything here is running in the Lumina development sandbox.</p>
</header>

<div class="bluf">
  <p class="big">Four of the five are built and working. The fifth is built but has not been proven
  end to end, and two gaps in production data will make two of the answers look wrong until they
  are filled.</p>
  <ul>
    <li>Multiple programmes per visit, programmes pre-filled from the facility, provider filtering
    by state licence and patient counts are all live in the sandbox.</li>
    <li>Change notifications are written, deployed and unit tested, but no email has been watched
    arriving. Proving it needs a controlled test, because this sandbox holds real addresses.</li>
    <li>Production has no state licence records at all, and the programme checkboxes are empty on
    all 194 onboarding facilities. Until both are filled, the provider filter and the programme
    pre-fill will show nothing in production even though they work.</li>
  </ul>
</div>

<p class="vid">A 53 second screen recording of this same walkthrough, taken in lumDev, is in
<b>lmna-630-scheduling-demo-2026-10-01.mp4</b> alongside this file.</p>

<div class="strip">
  <div><b>Where</b><span>lumDev, Facility Scheduling tab</span></div>
  <div><b>Status</b><span>In the sandbox, not in production</span></div>
  <div><b>Tests</b><span>91 Jest and 45 Apex for this feature, all passing</span></div>
</div>

<main>

  <h2 class="sh">The five questions</h2>
  <p class="intro">Taken in the order they were asked.</p>
  {QBLOCKS}

  <h2 class="sh">The calendar</h2>
  <p class="intro">The component opens on a list of facilities awaiting onboarding and switches to a
  month, week or day calendar. The most recent change puts the programmes on their own line under
  the time, with the status beside the time.</p>
  {mac("Facility Scheduling, month view, lumDev", "02-calendar.png",
       "Each event reads facility, then time and status, then the programmes on the visit. "
       "A cancelled visit is struck through. Month cells show the start time, because the full "
       "range and the status chip together did not fit. The full range is on the day view and in "
       "the hover tooltip.")}

  <h2 class="sh">Two gaps in production data</h2>
  <p class="intro">Both of these are data, not code. The features work; in production they would
  currently have nothing to work with.</p>

  <div class="gap">
    <h3>There are no state licence records in production</h3>
    <p>Question 4 filters providers by a current licence for the facility's state. Production holds
    no <code>State License</code> records at all, so that filter would hide every provider.</p>
    <p>The sandbox demo above works because the test data includes licences. Before this goes live
    somebody needs to decide where licence data comes from and load it.</p>
  </div>

  <div class="gap">
    <h3>The programme checkboxes are empty on all 194 onboarding facilities</h3>
    <p>Question 3 pre-ticks the programmes a facility runs by reading the checkboxes on the facility
    record. In production those checkboxes are false on every onboarding facility, so nothing would
    pre-tick and every programme would read <i>Not active at this facility</i>.</p>
    <p>Coordinators can still tick by hand, so the dialog is usable either way, but the convenience
    the question was asking for only appears once the facility records are filled in.</p>
  </div>

  <h2 class="sh">Seeing it yourself</h2>
  <p class="intro">Two minutes in lumDev, in this order.</p>
  <table>
    <tr><th style="width:34px">#</th><th style="width:230px">Do this</th><th>What it shows</th></tr>
    <tr><td>1</td><td>Open the Facility Scheduling tab</td>
      <td>The worklist, with patient counts drawn per facility. Question 5.</td></tr>
    <tr><td>2</td><td>Type <code>TST</code> in the search box</td>
      <td>Narrows to the seeded test facilities, so nothing real is in the way.</td></tr>
    <tr><td>3</td><td>Click <b>Calendar</b></td>
      <td>The month grid. Events carry every programme on the visit. Question 1.</td></tr>
    <tr><td>4</td><td>Click any event</td>
      <td>The edit dialog opens, programmes already ticked from the facility. Questions 1 and 3.</td></tr>
    <tr><td>5</td><td>Open <b>Add a provider</b></td>
      <td>Only providers licensed in that state, with the hidden ones accounted for. Question 4.</td></tr>
  </table>

  <h2 class="sh">Still open</h2>
  <p class="intro">Decisions needed from Dorothy or Chayim before this is finished.</p>
  <table>
    <tr><th style="width:230px">Question</th><th>Why it matters</th></tr>
    <tr><td>Which programmes genuinely conflict?</td>
      <td>The conflict check currently treats BHI and CoCM as the only pair that cannot share a
      visit. That was a provisional guess and needs confirming.</td></tr>
    <tr><td>Community Full-Time, IPV Onboarding, RPM, PCM, APCM</td>
      <td>These can be put on a visit but there is no field for them on the facility record, so they
      can never pre-fill. Either they need fields or they should come off the list.</td></tr>
    <tr><td>Who should the notifications go to?</td>
      <td>Today it is the facilitator and the providers on the visit. If coordinators or a shared
      mailbox should also be copied, that is a small change.</td></tr>
  </table>

</main>

<footer>Propela Tech, prepared for the Lumina team. Screenshots taken in the Lumina development
sandbox against seeded test data. No patient information appears in this document.</footer>

</div></body></html>
"""

OUT.write_text(HTML, encoding="utf-8")
print(f"wrote {OUT} ({OUT.stat().st_size:,} bytes)")
