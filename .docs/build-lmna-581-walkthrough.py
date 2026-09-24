#!/usr/bin/env python3
"""
Builds the LMNA-581 client walkthrough: self-contained Propela-branded HTML plus a
single-continuous-page PDF.

Presentation: screenshots sit inside CSS-drawn macOS window frames on a soft gradient ground,
and the facility email is rendered as a CSS Outlook reading pane rather than a screenshot, so
it stays crisp at print resolution.

Re-runnable. Reads the PNGs in .docs/shots-lmna-581/ and the logo from ~/.claude/brand/,
base64-embeds everything, then measures the rendered raster and sizes @page to it so the PDF
is ONE continuous page with no pagination lines.

Usage: python3 .docs/build-lmna-581-walkthrough.py
"""
import base64, hashlib, pathlib, re, subprocess, sys

DOCS = pathlib.Path(__file__).resolve().parent
SHOTS = DOCS / "shots-lmna-581"
BRAND = pathlib.Path.home() / ".claude" / "brand"
OUT_HTML = DOCS / "lmna-581-delivery-walkthrough-2026-09-09.html"
OUT_PDF = DOCS / "lmna-581-delivery-walkthrough-2026-09-09.pdf"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WIDTH = 1120

SB = "https://data-efficiency-9627--partialsb.sandbox.lightning.force.com"
FACILITY_ID = "a01Ou00000slDi4IAE"

SLATE, NAVY, YELLOW, BLUE = "#24323f", "#0C263B", "#f5fd7e", "#b9d8f5"
INK, GREY = "#1a1a1a", "#eef0f3"


def b64(path):
    return "data:image/png;base64," + base64.b64encode(pathlib.Path(path).read_bytes()).decode()


def shot(name):
    p = SHOTS / name
    if not p.exists():
        sys.exit(f"missing screenshot: {p}")
    return b64(p)


DERIVED = SHOTS / ".derived"
ARIAL = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def derive(name, crop=None, marks=()):
    """
    Crop a screenshot and draw annotations on it, caching the result under .derived/.

    Cropping is not cosmetic: the raw captures include a browser window, a personal bookmark
    bar, open tabs belonging to unrelated records and a tester's own mailbox address, none of
    which belong in a client document. Everything outside the region of interest is removed
    rather than blurred, so there is nothing to un-blur.

    A mark is (box, label, side) where side is 'above', 'below', 'left' or 'right' and the box
    is in coordinates of the ALREADY CROPPED image.
    """
    from PIL import Image, ImageDraw, ImageFont
    src = SHOTS / name
    if not src.exists():
        sys.exit(f"missing screenshot: {src}")
    DERIVED.mkdir(exist_ok=True)
    # The cache key carries the crop and the marks, because one screenshot is derived more than
    # once: a zoomed strip of the header and the whole record are the same source file.
    variant = hashlib.sha1(repr((crop, marks)).encode()).hexdigest()[:10]
    out = DERIVED / f"{pathlib.Path(name).stem}-{variant}.png"
    if out.exists() and out.stat().st_mtime > max(src.stat().st_mtime,
                                                  pathlib.Path(__file__).stat().st_mtime):
        return b64(out)

    im = Image.open(src).convert("RGB")
    if crop:
        im = im.crop(crop)

    if marks:
        # Annotations are drawn in a white margin around the shot rather than on top of it, so a
        # label never covers the interface it is pointing at. The margin is widest on the left
        # because that is where the longest leader lines land.
        padl, padt, padr, padb = 210, 104, 28, 28
        canvas = Image.new("RGB", (im.width + padl + padr, im.height + padt + padb), "#ffffff")
        canvas.paste(im, (padl, padt))
        im = canvas
        d = ImageDraw.Draw(im, "RGBA")
        size = max(17, round((im.width - padl - padr) / 62))
        font = ImageFont.truetype(ARIAL, size)
        th = size + 16
        for box, label, side in marks:
            x0, y0, x1, y1 = box[0] + padl, box[1] + padt, box[2] + padl, box[3] + padt
            d.rectangle([x0, y0, x1, y1], fill=(245, 253, 126, 70), outline="#d94f3d", width=4)
            tw = d.textlength(label, font=font) + 22
            if side == "above":
                lx, ly = min(max(x0, 8), im.width - tw - 8), y0 - th - 22
            elif side == "below":
                lx, ly = min(max(x0, 8), im.width - tw - 8), y1 + 22
            elif side == "left":
                lx, ly = max(x0 - tw - 34, 8), (y0 + y1) // 2 - th // 2
            else:
                lx, ly = min(x1 + 34, im.width - tw - 8), (y0 + y1) // 2 - th // 2
            d.rounded_rectangle([lx, ly, lx + tw, ly + th], 5, fill="#d94f3d")
            d.text((lx + 11, ly + 7), label, font=font, fill="#ffffff")
            if side in ("left", "right"):
                a = (lx + tw if side == "left" else lx, ly + th / 2)
                b = (x0 if side == "left" else x1, (y0 + y1) / 2)
            else:
                a = (lx + tw / 2, ly if side == "below" else ly + th)
                b = ((x0 + x1) / 2, y1 if side == "below" else y0)
            d.line([a, b], fill="#d94f3d", width=3)

    im.save(out)
    return b64(out)


def logo():
    p = BRAND / "logos" / "main" / "propela-main-yellow-white-900.png"
    if not p.exists():
        sys.exit(f"missing brand logo: {p}")
    return b64(p)


def mac(img, title, caption, note=None, width=None):
    """Screenshot inside a macOS window frame."""
    w = f' style="max-width:{width}px"' if width else ""
    n = f'<p class="note">{note}</p>' if note else ""
    return f"""<figure class="macwrap">
  <div class="mac"{w}>
    <div class="macbar"><span class="dot r"></span><span class="dot y"></span><span class="dot g"></span>
      <span class="mactitle">{title}</span></div>
    <img src="{img}" alt="">
  </div>
  <figcaption>{caption}</figcaption>{n}
</figure>"""


def pane(title, inner, caption, note=None, width=None):
    """Arbitrary HTML inside a macOS window frame. Used where a screenshot would have carried a
    tester's own mailbox address, and because CSS stays crisp at print resolution."""
    w = f' style="max-width:{width}px"' if width else ""
    n = f'<p class="note">{note}</p>' if note else ""
    return f"""<figure class="macwrap">
  <div class="mac"{w}>
    <div class="macbar"><span class="dot r"></span><span class="dot y"></span><span class="dot g"></span>
      <span class="mactitle">{title}</span></div>
    {inner}
  </div>
  <figcaption>{caption}</figcaption>{n}
</figure>"""


def step(num, title, lede, body):
    return f"""<section class="step">
  <div class="snum">{num}</div>
  <div class="sbody"><h3>{title}</h3><p class="lede">{lede}</p>{body}</div>
</section>"""


def outlook(expiry):
    """The facility email as a CSS Outlook reading pane. Crisp at print resolution."""
    return f"""<figure class="macwrap">
  <div class="mac" style="max-width:900px">
    <div class="macbar"><span class="dot r"></span><span class="dot y"></span><span class="dot g"></span>
      <span class="mactitle">Outlook &mdash; Inbox</span></div>
    <div class="ol">
      <div class="ol-hd">
        <div class="ol-subj">Readmissions Report &mdash; Sample Care Center &mdash; 2026-09-08</div>
        <div class="ol-row">
          <div class="ol-av">LC</div>
          <div class="ol-who">
            <div><b>Lumina Care</b> <span class="ol-addr">&lt;tcm@luminacare.com&gt;</span></div>
            <div class="ol-to">To: Maria Santos (Administrator)</div>
          </div>
          <div class="ol-when">Wed 09/09/2026 8:00 AM</div>
        </div>
      </div>
      <div class="ol-body">
        <p><b>3 hospital admissions</b> for Sample Care Center during Tuesday, September 8, 2026.</p>
        <p>These are patients discharged home from your facility who were subsequently admitted
           to a hospital.</p>
        <p><span class="ol-btn">View report</span></p>
        <p class="ol-fine">This link expires on {expiry}. It also closes after 10 views,
           whichever comes first. It was issued to maria.santos@samplecarecenter.com and should
           not be forwarded. No patient information is included in this email.</p>
        <p class="ol-fine">Link expired or stopped working? Reply to this email and we will send
           a new one.</p>
      </div>
    </div>
  </div>
  <figcaption>The facility email as an administrator sees it in Outlook, rendered from the
    template the code produces, with a representative facility and contact.</figcaption>
  <p class="note">Nothing in this message is protected health information. That is the whole
    reason no encrypted mail relay is needed: there is nothing in the email to protect.</p>
</figure>"""


ATTRIBUTION_ROWS = """<table class="attr">
  <tr><th>Link</th><th>Delivered to (attribution target)</th><th>Representing</th>
      <th class="n">Opens</th><th class="n">Downloads</th><th>First opened (ET)</th>
      <th>Expires (ET)</th></tr>
  <tr><td class="m">RRL-00000001</td>
      <td><b>tester1@propela.tech</b><span class="role">Sandbox Tester</span></td>
      <td class="m">admin@samplecarecenter.com</td>
      <td class="n">0</td><td class="n">0</td><td class="m">&ndash;</td>
      <td class="m">10 Sep 14:51</td></tr>
  <tr><td class="m">RRL-00000002</td>
      <td><b>tester2@propela.tech</b><span class="role">Sandbox Tester</span></td>
      <td class="m">admin@samplecarecenter.com</td>
      <td class="n hit">1</td><td class="n">0</td><td class="m">09 Sep 14:51</td>
      <td class="m">10 Sep 14:51</td></tr>
</table>"""

DIGEST_PANE = """<div class="ol">
  <div class="ol-hd">
    <div class="ol-subj">Readmissions Report run &mdash; 2026-09-08 &mdash; 2 sent, 0 skipped</div>
    <div class="ol-row">
      <div class="ol-av">LC</div>
      <div class="ol-who">
        <div><b>Lumina Care</b> <span class="ol-addr">&lt;tcm@luminacare.com&gt;</span></div>
        <div class="ol-to">To: Kevin Grayson</div>
      </div>
      <div class="ol-when">Wed 09/09/2026 8:00 AM</div>
    </div>
  </div>
  <div class="ol-body">
    <p><b>Readmissions Report run</b></p>
    <ul class="dg">
      <li>Window: Tuesday, September 8, 2026 (America/New_York)</li>
      <li>Facilities scanned: 231</li>
      <li>Emails sent: 2</li>
      <li>Admissions reported: 3</li>
      <li>Facilities skipped: 0</li>
    </ul>
    <p><b>Facility emails (2):</b></p>
    <ul class="dg">
      <li>Sample Care Center (3 rows) to <span class="mono">admin@samplecarecenter.com</span>
          [Administrator], own link expires Thursday, September 10, 2026 2:12 PM EDT</li>
      <li>Sample Care Center (3 rows) to <span class="mono">don@samplecarecenter.com</span>
          [Director of Nursing], own link expires Thursday, September 10, 2026 2:12 PM EDT</li>
    </ul>
    <p><b>Link activity, last 14 days:</b></p>
    <ul class="dg">
      <li>2 links examined, 1 opened, 0 downloaded, 0 closed early on the view cap</li>
    </ul>
  </div>
</div>"""


def build():
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>LMNA-581 Delivery Walkthrough</title>
<style>
  * {{ box-sizing:border-box }}
  body {{ margin:0; color:{INK}; font-size:14px; line-height:1.55;
    font-family:'DM Sans',-apple-system,'SF Pro Text',Tahoma,Helvetica,Arial,sans-serif;
    background:#f4f6f8; }}
  .page {{ width:{WIDTH}px; margin:0 auto }}
  h1,h2,h3 {{ font-family:'Antonia Variable',Georgia,'Times New Roman',serif; font-weight:400 }}

  header {{ background:{SLATE}; color:#fff; padding:32px 40px 36px;
    border-bottom:4px solid {YELLOW} }}
  .htop {{ display:flex; justify-content:space-between; align-items:flex-start; gap:24px }}
  header img.logo {{ height:36px }}
  .meta {{ font-family:'SF Mono',Menlo,monospace; font-size:10.5px; letter-spacing:.09em;
    text-transform:uppercase; color:{BLUE}; text-align:right; line-height:1.75 }}
  header h1 {{ margin:22px 0 10px; font-size:33px; line-height:1.14; letter-spacing:-.01em }}
  header p.sub {{ margin:0; max-width:76ch; color:#cfe0ee; font-size:15px }}
  .pill {{ display:inline-block; background:{YELLOW}; color:{NAVY}; font-weight:700; font-size:11.5px;
    padding:8px 14px; border-radius:3px; margin-top:22px;
    font-family:'SF Mono',Menlo,monospace; letter-spacing:.04em }}

  .scope {{ margin:0; padding:20px 40px; background:#fff;
    border-bottom:1px solid #dde2e7 }}
  .scope b {{ color:{SLATE} }}

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
  p.lede {{ margin:0 0 13px; color:#4d5a66 }}

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
  p.note {{ margin:10px 0 0; font-size:12.5px; padding:11px 14px; border-radius:4px;
    background:#eef4fb; color:{NAVY}; border:1px solid #cddff0; border-left:3px solid #7ea9d0 }}
  p.note.warn {{ background:#fdfbe8; border-color:#e3e2b4; border-left-color:#c9c96a; color:#5a5310 }}

  .ol {{ font-family:'Segoe UI',-apple-system,Helvetica,Arial,sans-serif }}
  .ol-hd {{ padding:16px 20px 14px; border-bottom:1px solid #e6e7ea }}
  .ol-subj {{ font-size:18px; font-weight:600; color:#201f1e; margin-bottom:13px }}
  .ol-row {{ display:flex; align-items:flex-start; gap:12px }}
  .ol-av {{ flex:0 0 38px; height:38px; border-radius:50%; background:#0f6cbd; color:#fff;
    display:flex; align-items:center; justify-content:center; font-size:13px; font-weight:600 }}
  .ol-who {{ flex:1; font-size:13.5px; color:#201f1e; line-height:1.5 }}
  .ol-addr {{ color:#605e5c; font-weight:400 }}
  .ol-to {{ color:#605e5c; font-size:12.5px }}
  .ol-when {{ font-size:12px; color:#605e5c; white-space:nowrap; padding-top:2px }}
  .ol-body {{ padding:18px 20px 22px; font-size:14px; color:#201f1e; line-height:1.6 }}
  .ol-body p {{ margin:0 0 13px }}
  .ol-btn {{ display:inline-block; background:{NAVY}; color:#fff; padding:10px 18px;
    border-radius:3px; font-weight:700; font-size:13.5px }}
  .ol-fine {{ font-size:12px; color:#605e5c }}
  .ol-body ul.dg {{ margin:0 0 13px; padding-left:22px }}
  .ol-body ul.dg li {{ margin:0 0 4px }}
  .mono, .attr .m {{ font-family:'SF Mono',Menlo,monospace; font-size:12px }}
  .attr {{ width:100%; border-collapse:collapse; font-size:12.5px }}
  .attr th {{ background:{SLATE}; color:#fff; text-align:left; padding:9px 12px;
    font-size:10px; letter-spacing:.07em; text-transform:uppercase; font-weight:600 }}
  .attr td {{ padding:10px 12px; border-bottom:1px solid #e7ebef; vertical-align:top;
    color:#2b3743 }}
  .attr tr:nth-child(even) td {{ background:#f7f9fb }}
  .attr .n {{ text-align:center }}
  .attr td.n {{ font-weight:700; font-family:'SF Mono',Menlo,monospace }}
  .attr td.hit {{ color:#1f7a3d }}
  .attr .role {{ display:block; font-size:11px; color:#7b8794; margin-top:2px }}

  table {{ width:100%; border-collapse:separate; border-spacing:0; margin:14px 0 0; font-size:13px;
    background:#fff; border:1px solid #dde2e7; border-radius:5px; overflow:hidden }}
  th {{ background:{SLATE}; color:#fff; text-align:left; padding:10px 12px; font-size:10.5px;
    letter-spacing:.06em; text-transform:uppercase; font-weight:500 }}
  td {{ padding:10px 12px; border-top:1px solid #eceef1; vertical-align:top }}
  tr:nth-child(even) td {{ background:#fafbfc }}
  code {{ font-family:'SF Mono',Menlo,monospace; font-size:12px; background:#eef1f4;
    padding:1.5px 5px; border-radius:4px }}
  .ok {{ color:#1e6b3f; font-weight:700 }} .bad {{ color:#c23934; font-weight:700 }}
  .warn {{ color:#8a6100; font-weight:700 }}

  .gap {{ padding:20px 24px; margin-top:16px; border-radius:6px; background:#fff;
    border:1px solid #dde2e7; border-left:4px solid #c23934 }}
  .gap h3 {{ margin:0 0 7px; font-size:17px; color:#a62f26 }}
  .gap.good {{ border-left-color:#1e6b3f; background:#f6fbf8 }}
  .gap.good h3 {{ color:#1a5c37 }}

  ol.asks {{ margin:14px 0 0; padding:0; list-style:none; counter-reset:a }}
  ol.asks li {{ counter-increment:a; background:#fff; border-radius:5px;
    border:1px solid #dde2e7; padding:14px 18px 14px 52px; position:relative;
    margin-bottom:8px }}
  ol.asks li:before {{ content:counter(a,decimal-leading-zero); position:absolute; left:15px; top:14px;
    font-family:'SF Mono',Menlo,monospace; font-size:11px; color:{YELLOW};
    background:{SLATE}; padding:5px 7px; border-radius:3px }}
  ol.asks b {{ display:block; color:{SLATE} }}
  ol.asks span {{ color:#4d5a66; font-size:13px }}

  a {{ color:#1b4568 }}
  footer {{ background:{SLATE}; color:{BLUE}; padding:24px 40px; border-top:4px solid {YELLOW};
    font-family:'SF Mono',Menlo,monospace; font-size:10.5px; line-height:1.85; margin-top:34px }}
  footer b {{ color:{YELLOW} }}

  @page {{ size:{WIDTH}px __PAGE_H__px; margin:0 }}
  /* Chrome's print path rasterises box-shadow blurs into solid grey blocks, so the design
     carries no shadows at all. This is the guard against one creeping back in. */
  @media print {{
    * {{ box-shadow:none !important }}
    .page {{ width:{WIDTH}px }}
    footer {{ margin-bottom:0 }}
  }}
</style></head><body><div class="page">

<header>
  <div class="htop">
    <img class="logo" src="{logo()}" alt="Propela">
    <div class="meta">LMNA-581 &middot; Lumina Care<br>TCM Daily Readmission Reports<br>9 September 2026</div>
  </div>
  <h1>Delivering the readmission report by expiring link</h1>
  <p class="sub">Every path the report can take, captured from the live sandbox after deployment.
     Each recipient gets their own link, so an open or a download is attributed to a named
     mailbox rather than only to a facility.</p>
  <div class="pill">BUILT &amp; LIVE-TESTED IN SANDBOX &middot; NOT YET IN PRODUCTION</div>
</header>

<div class="scope">
  <b>Scope, plainly.</b> Deployed to <code>lumDev</code> on 9 September 2026, 74 of 74 tests
  passing, and exercised end to end with fabricated patient records. It is <b>not</b> in
  production, production holds none of this code, and the kill switch <code>Is_Active__c</code>
  is still <b>false</b>, so the 8am schedule is a no-op. Nothing has ever been sent to a real
  facility. Patient names in every screenshot are invented.
</div>

<main>

<h2 class="sh">The happy path</h2>
<p class="intro">Five steps, all captured from the sandbox run at 2:41pm ET on 9 September.</p>

{step("01", "The job builds one report and one link per recipient",
  "The nightly batch groups yesterday's readmissions by facility and renders that facility's "
  "report to PDF once. It then asks Salesforce for a separate public link per recipient, all "
  "pointing at the same file. Facilities with no readmissions are not emailed at all.",
  '<table><tr><th>Setting</th><th>Value in the tested run</th></tr>'
  '<tr><td>Link lifetime</td><td><code>Link_Expiry_Hours__c = 24</code>. Created 18:41 UTC, '
  'expires 2026-09-10 18:41 UTC. Measured at exactly 24.0 hours.</td></tr>'
  '<tr><td>View cap</td><td><code>Max_Opens__c = 10</code>. The link closes early once a '
  'recipient has opened it ten times.</td></tr>'
  '<tr><td>Download allowed</td><td><code>Allow_Download__c = true</code>, logged separately '
  'from a view.</td></tr>'
  '<tr><td>Password</td><td>None by design. The unguessable URL is the credential.</td></tr>'
  '<tr><td>Storage</td><td>One PDF per facility, filed on the Facility record. Every recipient '
  'link points at that same file, so extra recipients cost one small row each.</td></tr>'
  '</table>')}

{step("02", "Each recipient gets an email with no patient data in it",
  "The message carries a count and a button, and names the address it was issued to. No patient "
  "names, no dates of birth, no attachment.",
  outlook("Thursday, September 10, 2026 2:41 PM EDT"))}

{step("03", "One click, no login, and the report opens",
  "The recipient has no Salesforce account and never signs in. The long random string in the URL "
  "is the credential, and it unlocks that one file and nothing else. Captured in a browser "
  "profile with zero Salesforce cookies.",
  mac(shot("13_gmail_recipient_link.png"), "Salesforce file viewer",
      "The link issued to the Gmail recipient, rendering the report inline. The file title "
      "carries the address the link belongs to.",
      "The report is a PDF rather than a CSV because this viewer shows &quot;No preview "
      "available&quot; for CSV, which would have forced every recipient to download before "
      "reading anything.", 860))}

{step("04", "The open is attributed to that mailbox, not just the facility",
  "This is the part facility-level tracking could not do. Because each link was issued to one "
  "address, the platform recording an open tells you who opened it. Below are the real rows "
  "after opening only the Gmail recipient's link.",
  pane("Readmission Report Links — lumDev", ATTRIBUTION_ROWS,
      "Two recipients, two links, and the open landed on exactly one of them. The second "
      "mailbox shows one open; the first stays at zero.",
      "These are real values from the live test, with the testers' own addresses replaced by "
      "placeholders. Opening one recipient's link left the other recipient's counters "
      "untouched, which is the proof that attribution works.", 1080))}

{step("05", "Lumina gets one digest, not a copy of every email",
  "Kevin receives a single summary naming each facility, each recipient, their role and the link "
  "expiry, followed by the day's open and download totals. Facilities that were skipped appear "
  "underneath, so gaps surface daily instead of silently.",
  pane("Outlook — Readmissions Report run", DIGEST_PANE,
      "The digest from a tested run, with the testers' own addresses replaced by placeholders. "
      "One line per email rather than one per facility, because each recipient gets their own "
      "link and therefore their own message. Two recipients at one facility is two emails. The "
      "per-recipient detail and the link-activity block are new work; the job previously "
      "reported bare totals.", None, 860))}

<h2 class="sh">What the audit captures</h2>
<p class="intro">Worth being exact, because this is the one place the design trades something away.</p>
<table>
  <tr><th>Question</th><th>Answered?</th><th>How</th></tr>
  <tr><td><b>Which mailbox opened it</b></td><td class="ok">Yes</td>
      <td>Each recipient has their own link, so the open identifies the address</td></tr>
  <tr><td><b>Which mailbox downloaded it</b></td><td class="ok">Yes</td>
      <td>Downloads counted separately from views, per recipient</td></tr>
  <tr><td>When, to the second</td><td class="ok">Yes</td>
      <td>First opened and last activity, per recipient</td></tr>
  <tr><td>How many times</td><td class="ok">Yes</td><td>Open and download counts per recipient</td></tr>
  <tr><td>Which facility's report</td><td class="ok">Yes</td><td>Each row is a child of its Facility</td></tr>
  <tr><td>A named human, not a mailbox</td><td class="warn">Partly</td>
      <td>Every open is attributed to the exact address the link was issued to, and to that
          facility. What a public link cannot prove is who was sitting at the keyboard. If the
          administrator forwards their own link to the director of nursing, the open is still
          recorded against the administrator's address, because that is the link that was used.
          Naming the human would require a login or a one-time code on every open, which is the
          portal build Lumina chose not to take</td></tr>
  <tr><td><b>IP address of the viewer</b></td><td class="bad">No</td>
      <td>Not available free. Salesforce offers a <code>ContentDistribution</code> event type
          carrying client IP, but this org generates only 3 of the 79 event types, so it needs
          the Event Monitoring add-on licence</td></tr>
</table>
<p class="note">Identity here is <b>possession of the mailbox the link was sent to</b>, the same
   model Microsoft's own one-time-passcode encryption uses. It satisfies HIPAA accounting of
   disclosures, which asks for the entity and address that received the data.</p>

<h2 class="sh">The other paths</h2>
<p class="intro">A single happy case is a demo, not proof. These are the branches that matter.</p>

{step("06", "The link dies on its own, two ways",
  "Whichever comes first: 24 hours, or ten opens. Anyone opening it after that, including anyone "
  "the email was forwarded to, gets Salesforce's page instead of the report.",
  mac(shot("04_public_link_expired.png"), "Salesforce — expired delivery",
      "The native expired page, captured by expiring a real link and reloading it.",
      "The view cap is enforced when the audit refreshes rather than instantly, so it is a soft "
      "cap: a burst of opens inside one window can exceed ten slightly. Salesforce has no native "
      "hard view limit on a public link.", 560))}

<div class="gap good">
  <h3>Lumina can reissue a link, and that is the intended route</h3>
  <p>Salesforce's expired page carries no way back, so the email itself tells the recipient to
     reply and <b>Lumina reissues it for them</b>. Because every link now has its own row naming
     its recipient, a reissue is a lookup rather than a guess: staff open the Facility, see who
     held which link and whether they ever opened it, then send that person a fresh one. The new
     link always goes to the address on the row, never to whoever asked, so a forwarded request
     cannot redirect a report somewhere else.</p>
  <p><b>Built and live in the sandbox.</b> <b>Resend Readmissions Report</b> sits on the Facility
     record. It first shows what would go out, to which addresses and in which role, and sends
     nothing until that is confirmed. Confirming issues a brand new link per recipient, points it
     at the report already filed on the record rather than generating a second copy, and reports
     what actually sent.</p>
</div>

{mac(derive("16_facility_record_with_resend.png", crop=(0, 0, 1586, 76), marks=(
        ((1136, 14, 1344, 56), "Reissues the link, one per recipient", "above"),
     )), "Salesforce — Facility record, header",
     "Where the button lives: the action row on the Facility record, next to Create Opportunity. "
     "Any Lumina user who can see the facility can reissue its link from here.", None, 1000)}

{mac(shot("14_resend_dialog.png"), "Salesforce — Resend Readmissions Report",
   "The confirmation step. Nothing has been sent at this point: the dialog exists so nobody puts "
   "a link to patient data in an inbox they did not expect.",
   "Both rows here are sandbox testers, because this org diverts every facility email away from "
   "real contacts. In production this list is the facility's own administrator, or the director "
   "of nursing when no administrator is on file, which for most facilities is a single row.",
   860)}

{mac(shot("15_resend_sent.png"), "Salesforce — after confirming",
   "After confirming. Each recipient has their own new link with its own expiry, and each row "
   "says whether it sent. A failure for one address does not stop the others. Two rows again "
   "because this is the sandbox, standing in for one facility contact.",
   "Every reissue writes its own attribution row rather than editing the old one, so the "
   "accounting of disclosures keeps both deliveries and each one's opens stay separate.", 860)}

{step("07", "A facility with no contact on file is skipped, loudly",
  "If a facility has readmissions but no administrator or director-of-nursing email, nothing is "
  "sent and the reason is named in the digest rather than swallowed. Measured against production "
  "today: of the <b>131 facilities</b> that had a qualifying readmission in the last 30 days, "
  "<b>25</b> have no contact of either kind, so about one report in five goes nowhere. Across "
  "the whole enrolled list the gap is wider: <b>159 of 326</b> facilities have neither address, "
  "66 of them GHC and 60 Complete Care Management.",
  '<table><tr><th>Condition</th><th>Behaviour</th></tr>'
  '<tr><td>No <code>Admin_Email__c</code></td><td>Falls back to <code>DON_Email__c</code>, and '
  'the attribution row records which role received it</td></tr>'
  '<tr><td>Neither on file</td><td class="warn">Skipped, listed in the digest with its row count</td></tr>'
  '<tr><td>Zero readmissions</td><td>No email at all, and not listed as a skip</td></tr>'
  '<tr><td>Link could not be created</td><td class="warn">Reported as a failure and that '
  'recipient is <b>not</b> emailed. An email pointing at a broken link never goes out.</td></tr>'
  '</table>')}

{step("08", "A misconfigured sender is reported, not fatal",
  "Found by the live test rather than by reading the code. The first run reported "
  "<b>Emails sent: 0</b> because the sending address existed but had never been verified, and "
  "Salesforce refuses to send from an unverified address.",
  '<table><tr><th></th><th>Before</th><th>After</th></tr>'
  '<tr><td>Unverified sender</td><td class="bad">Whole send rejected, report silenced</td>'
  '<td class="ok">Falls back to the running user, reported once in the digest</td></tr>'
  '<tr><td>Digest &quot;Facility emails&quot; list</td>'
  '<td class="bad">Listed messages that were built, even when none sent</td>'
  '<td class="ok">Lists only what actually went out</td></tr>'
  '<tr><td>Sandbox sender</td><td class="bad">Reused the production address</td>'
  '<td class="ok">Own field, <code>Sandbox_From_Org_Wide_Address__c</code></td></tr></table>'
  '<p class="note warn">A setup gap should never silence a daily clinical report. It should send '
  'anyway and complain in the summary, which is now what happens.</p>')}

<h2 class="sh">Proof of delivery</h2>
<p class="intro">Both testers received both messages, each with their own link. This is a real
   inbox, not a mockup.</p>
{mac(derive("01_gmail_inbox_both_emails.png", crop=(326, 186, 1382, 364)),
     "Gmail — inbox, test mailbox",
     "Both messages landed in a Google mailbox: the facility report and the run digest. This "
     "matters because Genesis, the largest chain and 61% of recipient addresses, is on Google.",
     None, 1000)}

<h2 class="sh">Where it lives in Salesforce</h2>
<p class="intro">Every report is filed against the facility it belongs to, with the per-recipient
   links alongside it, so Lumina staff can see who received what and whether they read it.</p>
{mac(derive("16_facility_record_with_resend.png", marks=(
        ((1140, 16, 1350, 56), "Resend Readmissions Report", "above"),
        ((50, 146, 134, 188), "Files and links", "left"),
     )), "Salesforce — Facility record",
     f'The test facility, annotated. The generated PDF sits under Files and the per-recipient '
     f'link rows hang off the record, both on the Related tab. <b>Resend Readmissions Report</b> '
     f'reissues a fresh link to the addresses already on file, without rerunning the job for '
     f'every facility. '
     f'<a href="{SB}/lightning/r/Facility__c/{FACILITY_ID}/view" target="_blank" '
     f'rel="noopener">Open the record</a>.',
     "The attribution rows live on a purpose-built object because Salesforce's own "
     "<code>ContentDistribution</code> takes no custom fields and has no Lightning page, so "
     "without it the trail would be neither attributable nor browsable.", 1080)}

<h2 class="sh">Still needed before production</h2>
<ol class="asks">
  <li><b>Verify the sending address in production</b><span>Create <code>tcm@luminacare.com</code>
      as an Org-Wide Email Address and have someone with that mailbox click the verification link.
      Production currently has none.</span></li>
  <li><b>Confirm the export button should be there</b><span>Recommended, since staff need to work
      the list rather than read it on screen, and every download is now logged against a named
      recipient. Worth an explicit yes because a copy leaves Salesforce.</span></li>
  <li><b>Confirm the view cap and the link lifetime</b><span>Currently 24 hours and 10 opens per
      recipient. Both are configuration, changeable without a deploy.</span></li>
  <li><b>An owner for the facilities with no contact</b><span>25 of the 131 facilities that had
      a readmission in the last 30 days have no administrator and no director-of-nursing email,
      and 159 of 326 enrolled facilities have neither. Concentrated in GHC and Complete Care
      Management. Independent of the delivery method, and the single biggest limit on
      coverage.</span></li>
  <li><b>Confirm the retention rule</b><span>The stored PDF is now deleted once every link to
      that report has expired, after a grace period, so patient data does not outlive the
      delivery window on the record. A recipient's own download is theirs and is unaffected.
      Worth confirming the grace period, currently seven days.</span></li>
  <li><b>Compliance sign-off in writing</b><span>The link authenticates by possession of the
      mailbox. Worth recording rather than agreeing verbally.</span></li>
  <li><b>Decide whether IP addresses are wanted</b><span>Not available on the free tier. It needs
      the Event Monitoring add-on licence, or a custom page we host.</span></li>
</ol>

</main>

<footer>
  Propela Tech &middot; LMNA-581 &middot; Expiring-link delivery walkthrough<br>
  Screens captured from <b>lumDev</b> (partial sandbox) on 9 September 2026. All patient names are
  fabricated. Production figures read from <b>Lumina production</b>, read-only.
</footer>

</div></body></html>"""


def render(html_text):
    probe_html, probe_pdf = DOCS / "_probe.html", DOCS / "_probe.pdf"
    probe_html.write_text(html_text.replace("__PAGE_H__", "16000"))
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-sandbox",
                    "--no-pdf-header-footer", "--virtual-time-budget=6000",
                    f"--print-to-pdf={probe_pdf}", f"file://{probe_html}"],
                   capture_output=True, timeout=240)
    height = None
    if probe_pdf.exists():
        info = subprocess.run(["pdfinfo", str(probe_pdf)], capture_output=True, text=True).stdout
        pages = re.search(r"Pages:\s+(\d+)", info)
        if pages and pages.group(1) != "1":
            print(f"  WARNING: probe paginated into {pages.group(1)} pages; raise the probe height")
        subprocess.run(["pdftoppm", "-png", "-r", "96", "-f", "1", "-l", "1",
                        str(probe_pdf), str(DOCS / "_probe")], capture_output=True)
        pngs = sorted(DOCS.glob("_probe-*.png"))
        if pngs:
            from PIL import Image
            im = Image.open(pngs[0]).convert("RGB")
            w, h = im.size
            px = im.load()
            # The ground is a gradient, so look for the footer's dark band rather than pure white.
            for y in range(h - 1, -1, -1):
                if any(sum(px[x, y]) < 330 for x in range(0, w, 3)):
                    height = y + 30
                    break
            print(f"  probe raster {w}x{h}, content bottom -> page height {height}")
            for p in pngs:
                p.unlink()
    if not height:
        height = 16000
        print("  WARNING: could not measure raster, falling back to 16000px")

    OUT_HTML.write_text(html_text.replace("__PAGE_H__", str(height)))
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-sandbox",
                    "--no-pdf-header-footer", "--virtual-time-budget=6000",
                    f"--print-to-pdf={OUT_PDF}", f"file://{OUT_HTML}"],
                   capture_output=True, timeout=240)
    for f in (probe_html, probe_pdf):
        if f.exists():
            f.unlink()


if __name__ == "__main__":
    text = build()
    render(text)
    body = OUT_HTML.read_text()
    print(f"HTML  {OUT_HTML.name}  {len(body):,} bytes")
    print(f"  embedded images:  {body.count('src=\"data:image')}")
    print(f"  external refs:    {len(re.findall(r'src=\"(?!data:)', body))} (must be 0)")
    print(f"  links w/o _blank: {len(re.findall(r'<a (?![^>]*target=)', body))} (must be 0)")
    if OUT_PDF.exists():
        info = subprocess.run(["pdfinfo", str(OUT_PDF)], capture_output=True, text=True).stdout
        pages = re.search(r"Pages:\s+(\d+)", info)
        size = re.search(r"Page size:\s+(.+)", info)
        print(f"PDF   {OUT_PDF.name}  {OUT_PDF.stat().st_size:,} bytes")
        print(f"  pages:     {pages.group(1) if pages else '?'} (must be 1)")
        print(f"  page size: {size.group(1).strip() if size else '?'}")
