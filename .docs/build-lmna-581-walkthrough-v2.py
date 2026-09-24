#!/usr/bin/env python3
"""
Builds the LMNA-581 phase-two client walkthrough: self-contained Propela-branded HTML plus a
single-continuous-page PDF.

Revision of build-lmna-581-walkthrough.py for the model built on 15 September 2026: the report
email links to a page on a Salesforce Site, the page emails a ten-minute code to the address on
file, a correct code opens the PDF, and every step is logged with IP and browser.

Presentation is unchanged from the first walkthrough: real screenshots inside CSS macOS window
frames, the emails rendered as CSS Outlook reading panes from the exact HTML the code produces,
everything base64-embedded, and the PDF sized to one continuous page.

Re-runnable. Usage: python3 .docs/build-lmna-581-walkthrough-v2.py [--no-pdf]
"""
import base64, hashlib, html, pathlib, re, subprocess, sys

DOCS = pathlib.Path(__file__).resolve().parent
SHOTS = DOCS / "shots-lmna-581"
BRAND = pathlib.Path.home() / ".claude" / "brand"
OUT_HTML = DOCS / "lmna-581-delivery-walkthrough-2026-09-15.html"
OUT_PDF = DOCS / "lmna-581-delivery-walkthrough-2026-09-15.pdf"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WIDTH = 1120

SB = "https://data-efficiency-9627--partialsb.sandbox.lightning.force.com"
SITE = "https://data-efficiency-9627--partialsb.sandbox.my.salesforce-sites.com/report"
FACILITY_ID = "a01Ou00000slDi4IAE"
LINK_ID = "a20Ou000004H2ZNIA0"

SLATE, NAVY, YELLOW, BLUE = "#24323f", "#0C263B", "#f5fd7e", "#b9d8f5"
INK = "#1a1a1a"
LUMINA_BLUE, LUMINA_NAVY = "#1f5fe0", "#30385c"

# The Salesforce captures were taken at 1200x900 with other records open in workspace tabs.
# Cropping below the tab strip removes those tab names, which belong to other records.
SF_CROP = (25, 140, 830, 860)


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
    """Crop a screenshot and draw annotations in a white margin around it. Cached by (crop, marks)."""
    from PIL import Image, ImageDraw, ImageFont
    src = SHOTS / name
    if not src.exists():
        sys.exit(f"missing screenshot: {src}")
    DERIVED.mkdir(exist_ok=True)
    variant = hashlib.sha1(repr((crop, marks)).encode()).hexdigest()[:10]
    out = DERIVED / f"{pathlib.Path(name).stem}-{variant}.png"
    if out.exists() and out.stat().st_mtime > max(src.stat().st_mtime,
                                                  pathlib.Path(__file__).stat().st_mtime):
        return b64(out)
    im = Image.open(src).convert("RGB")
    if crop:
        im = im.crop(crop)
    if marks:
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


def pair(left, right):
    return f'<div class="pair">{left}{right}</div>'


def step(num, title, lede, body):
    return f"""<section class="step">
  <div class="snum">{num}</div>
  <div class="sbody"><h3>{title}</h3><p class="lede">{lede}</p>{body}</div>
</section>"""


# The facility email body is the exact HTML TCMReadmissionEmailBuilder produced for the test
# facility today, captured from the org. Only the token is replaced, so the document does not
# carry a working link.
EMAIL_BODY_FILE = DOCS / "shots-lmna-581" / "email_body_2026-09-15.html"


def facility_email():
    body = EMAIL_BODY_FILE.read_text() if EMAIL_BODY_FILE.exists() else ""
    body = re.sub(r"t=[0-9a-f]{64}", "t=&hellip;", body)
    body = body.replace("administrator@facility.example", "maria.santos@samplecarecenter.com")
    body = body.replace("ZZ Claude Test Facility", "Sample Care Center")
    body = body.replace('style="display:inline-block;background:#1f5fe0;color:#ffffff;'
                        'padding:10px 16px;text-decoration:none;border-radius:3px;font-weight:bold;"',
                        'class="ol-btn"')
    return f"""<div class="ol">
  <div class="ol-hd">
    <div class="ol-subj">Readmissions Report - Sample Care Center - 2026-09-14</div>
    <div class="ol-row">
      <div class="ol-av">LC</div>
      <div class="ol-who">
        <div><b>Lumina Care</b> <span class="ol-addr">&lt;tcm@luminacare.com&gt;</span></div>
        <div class="ol-to">To: Maria Santos (Administrator)</div>
      </div>
      <div class="ol-when">Tue 09/15/2026 8:00 AM</div>
    </div>
  </div>
  <div class="ol-body">{body}</div>
</div>"""


def code_email():
    """The code email, from the markup in TCMReadmissionGateService.codeBody()."""
    return """<div class="ol">
  <div class="ol-hd">
    <div class="ol-subj">Your code for the readmissions report</div>
    <div class="ol-row">
      <div class="ol-av">LC</div>
      <div class="ol-who">
        <div><b>Lumina Care</b> <span class="ol-addr">&lt;tcm@luminacare.com&gt;</span></div>
        <div class="ol-to">To: Maria Santos (Administrator)</div>
      </div>
      <div class="ol-when">Tue 09/15/2026 10:14 AM</div>
    </div>
  </div>
  <div class="ol-body">
    <p>Your code for the readmissions report for Sample Care Center is</p>
    <p class="ol-code">515151</p>
    <p>It works for 10 minutes. Enter it on the page that asked for it.</p>
    <p class="ol-fine">If you did not ask for a code, ignore this email. Nobody can open the report
       without it.</p>
  </div>
</div>"""


def build():
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>LMNA-581 Delivery Walkthrough, revision 2</title>
<style>
  * {{ box-sizing:border-box }}
  body {{ margin:0; color:{INK}; font-size:14px; line-height:1.55;
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
  .pill {{ display:inline-block; background:{YELLOW}; color:{NAVY}; font-weight:700; font-size:11.5px;
    padding:8px 14px; border-radius:3px; margin-top:22px; font-family:'SF Mono',Menlo,monospace; letter-spacing:.04em }}

  .bluf {{ background:{NAVY}; color:#fff; padding:22px 40px 24px; border-bottom:1px solid #0a1e30 }}
  .bluf p.big {{ margin:0 0 10px; font-size:17px; font-weight:700; line-height:1.4 }}
  .bluf ul {{ margin:0; padding-left:20px; color:#cfe0ee; font-size:14px }}
  .bluf li {{ margin:3px 0 }}
  .strip {{ display:grid; grid-template-columns:1fr 1fr 1fr; gap:0; background:#fff; border-bottom:1px solid #dde2e7 }}
  .strip > div {{ padding:16px 40px; border-right:1px solid #eceef1 }}
  .strip > div:last-child {{ border-right:0 }}
  .strip b {{ display:block; font-family:'SF Mono',Menlo,monospace; font-size:10px; letter-spacing:.09em;
    text-transform:uppercase; color:#7b8794; margin-bottom:4px }}
  .strip span {{ font-size:13px; color:#2b3743 }}

  main {{ padding:30px 40px 40px }}
  h2.sh {{ font-size:21px; margin:40px 0 3px; color:{SLATE}; display:flex; align-items:center; gap:11px }}
  h2.sh:before {{ content:''; width:5px; height:22px; background:{YELLOW}; border-radius:3px }}
  p.intro {{ margin:9px 0 0; max-width:84ch; color:#4d5a66 }}

  .step {{ display:flex; gap:18px; padding:22px 24px; margin-top:16px; border-radius:6px; background:#fff; border:1px solid #dde2e7 }}
  .snum {{ flex:0 0 34px; height:34px; border-radius:4px; color:{YELLOW}; background:{SLATE};
    font-family:'SF Mono',Menlo,monospace; font-size:13.5px; font-weight:700; display:flex; align-items:center; justify-content:center }}
  .sbody {{ flex:1; min-width:0 }}
  .sbody h3 {{ margin:3px 0 6px; font-size:18px; color:{SLATE} }}
  p.lede {{ margin:0 0 13px; color:#4d5a66 }}

  .macwrap {{ margin:14px 0 0 }}
  .mac {{ border-radius:8px; overflow:hidden; background:#fff; border:1px solid #c9d0d8 }}
  .macbar {{ display:flex; align-items:center; gap:7px; padding:9px 13px; background:linear-gradient(180deg,#f6f6f7,#e8e9ec); border-bottom:1px solid #d8dade }}
  .dot {{ width:11px; height:11px; border-radius:50%; display:inline-block }}
  .dot.r {{ background:#ff5f57 }} .dot.y {{ background:#febc2e }} .dot.g {{ background:#28c840 }}
  .mactitle {{ margin-left:9px; font-size:11.5px; color:#5f6672; font-family:'SF Mono',Menlo,monospace; letter-spacing:.02em }}
  .mac img {{ display:block; width:100%; height:auto }}
  figcaption {{ font-size:12.5px; color:#5b6b7a; margin-top:9px; line-height:1.5 }}
  p.note {{ margin:10px 0 0; font-size:12.5px; padding:11px 14px; border-radius:4px; background:#eef4fb; color:{NAVY}; border:1px solid #cddff0; border-left:3px solid #7ea9d0 }}
  p.note.warn {{ background:#fdfbe8; border-color:#e3e2b4; border-left-color:#c9c96a; color:#5a5310 }}
  .pair {{ display:grid; grid-template-columns:1fr 1fr; gap:16px }}
  .pair .macwrap {{ margin-top:14px }}

  .ol {{ font-family:'Segoe UI',-apple-system,Helvetica,Arial,sans-serif }}
  .ol-hd {{ padding:16px 20px 14px; border-bottom:1px solid #e6e7ea }}
  .ol-subj {{ font-size:18px; font-weight:600; color:#201f1e; margin-bottom:13px }}
  .ol-row {{ display:flex; align-items:flex-start; gap:12px }}
  .ol-av {{ flex:0 0 38px; height:38px; border-radius:50%; background:{LUMINA_BLUE}; color:#fff; display:flex; align-items:center; justify-content:center; font-size:13px; font-weight:600 }}
  .ol-who {{ flex:1; font-size:13.5px; color:#201f1e; line-height:1.5 }}
  .ol-addr {{ color:#605e5c; font-weight:400 }}
  .ol-to {{ color:#605e5c; font-size:12.5px }}
  .ol-when {{ font-size:12px; color:#605e5c; white-space:nowrap; padding-top:2px }}
  .ol-body {{ padding:18px 20px 22px; font-size:14px; color:#201f1e; line-height:1.6 }}
  .ol-body p {{ margin:0 0 13px }}
  .ol-btn {{ display:inline-block; background:{LUMINA_BLUE}; color:#fff !important; padding:10px 18px; border-radius:3px; font-weight:700; font-size:13.5px; text-decoration:none }}
  .ol-fine, .ol-body p[style*="font-size:12px"] {{ font-size:12px !important; color:#605e5c !important }}
  .ol-code {{ font-size:30px; letter-spacing:8px; font-weight:700; color:{LUMINA_NAVY}; font-family:'SF Mono',Menlo,monospace }}
  .mono {{ font-family:'SF Mono',Menlo,monospace; font-size:12px }}

  table {{ width:100%; border-collapse:separate; border-spacing:0; margin:14px 0 0; font-size:13px; background:#fff; border:1px solid #dde2e7; border-radius:5px; overflow:hidden }}
  th {{ background:{SLATE}; color:#fff; text-align:left; padding:10px 12px; font-size:10.5px; letter-spacing:.06em; text-transform:uppercase; font-weight:500 }}
  td {{ padding:10px 12px; border-top:1px solid #eceef1; vertical-align:top }}
  tr:nth-child(even) td {{ background:#fafbfc }}
  code {{ font-family:'SF Mono',Menlo,monospace; font-size:12px; background:#eef1f4; padding:1.5px 5px; border-radius:4px }}
  .ok {{ color:#1e6b3f; font-weight:700 }} .bad {{ color:#c23934; font-weight:700 }} .warn {{ color:#8a6100; font-weight:700 }}

  .gap {{ padding:20px 24px; margin-top:16px; border-radius:6px; background:#fff; border:1px solid #dde2e7; border-left:4px solid #c23934 }}
  .gap h3 {{ margin:0 0 7px; font-size:17px; color:#a62f26 }}
  .gap.good {{ border-left-color:#1e6b3f; background:#f6fbf8 }}
  .gap.good h3 {{ color:#1a5c37 }}
  .gap p {{ margin:0 0 8px }}

  ol.asks {{ margin:14px 0 0; padding:0; list-style:none; counter-reset:a }}
  ol.asks li {{ counter-increment:a; background:#fff; border-radius:5px; border:1px solid #dde2e7; padding:14px 18px 14px 52px; position:relative; margin-bottom:8px }}
  ol.asks li:before {{ content:counter(a,decimal-leading-zero); position:absolute; left:15px; top:14px; font-family:'SF Mono',Menlo,monospace; font-size:11px; color:{YELLOW}; background:{SLATE}; padding:5px 7px; border-radius:3px }}
  ol.asks b {{ display:block; color:{SLATE} }}
  ol.asks span {{ color:#4d5a66; font-size:13px }}

  a {{ color:#1b4568 }}
  footer {{ background:{SLATE}; color:{BLUE}; padding:24px 40px; border-top:4px solid {YELLOW}; font-family:'SF Mono',Menlo,monospace; font-size:10.5px; line-height:1.85; margin-top:34px }}
  footer b {{ color:{YELLOW} }}

  @page {{ size:{WIDTH}px __PAGE_H__px; margin:0 }}
  @media print {{
    * {{ box-shadow:none !important }}
    .page {{ width:{WIDTH}px }}
    footer {{ margin-bottom:0 }}
  }}
</style></head><body><div class="page">

<header>
  <div class="htop">
    <img class="logo" src="{logo()}" alt="Propela">
    <div class="meta">LMNA-581 &middot; Lumina Care<br>TCM Daily Readmission Reports<br>Revision 2 &middot; 15 September 2026</div>
  </div>
  <h1>The readmission report behind a ten-minute code</h1>
  <p class="sub">What changed since the 9 September walkthrough, captured from the live sandbox after
     the rebuild. The public file link is gone. The email now opens a Lumina page that emails a
     six-digit code to the address on file, and every step on every link is logged with the
     time, the IP address and the browser.</p>
  <div class="pill">BUILT &amp; LIVE-TESTED IN SANDBOX &middot; NOT YET IN PRODUCTION</div>
</header>

<div class="bluf">
  <p class="big">A forwarded link, a copied URL or a screenshot no longer opens a report. Only the
     mailbox the report was sent to can get the code, and the code dies in ten minutes.</p>
  <ul>
    <li>Chris's concern is closed: the link on its own is worthless, and every link is 256 bits of randomness, so guessing one is not possible.</li>
    <li>Chayim's ask is built as asked: a one-time code that expires after ten minutes, requested when the report is opened rather than sent with it.</li>
    <li>New since last time: an access log per link with IP address and browser, a hard view cap, automatic lockout after five wrong codes, and Lumina branding on every screen.</li>
  </ul>
</div>
<div class="strip">
  <div><b>Background</b><span>The 9 September build used a public expiring link. Chris asked for more than possession of the URL; Chayim asked for a ten-minute code.</span></div>
  <div><b>Status</b><span>Deployed to the <code>lumDev</code> sandbox on 15 September. 142 of 142 automated tests pass. Every screen below is a real capture from a clean browser with no Salesforce login.</span></div>
  <div><b>Ask</b><span>Four one-time steps in production, listed at the end, and a decision on the retention grace period. Nothing here has touched production.</span></div>
</div>

<main>

<h2 class="sh">Why a code at view time, not in the email</h2>
<p class="intro">The report goes out on a schedule at 8am and nobody is waiting for it. Most people
   open it hours later, so a ten-minute code sent inside the report email would be dead before it
   was read. The page asks for the code at the moment of viewing instead, and sends it to the
   same address the report was issued to. That is also what makes a forwarded email useless: the
   code goes to the original mailbox, not to whoever is holding the link.</p>

<h2 class="sh">The happy path</h2>
<p class="intro">Six steps, all captured on 15 September from the sandbox, in a browser with no
   Salesforce session, against a test facility with invented patients.</p>

{step("01", "The job builds one report and one link per recipient",
  "Unchanged in shape from last time: the nightly batch groups yesterday's readmissions by facility, "
  "renders that facility's report to PDF once, and issues a separate link per recipient. What changed "
  "is what a link is. It is no longer a public file URL. It is a row we own, holding only a scrambled "
  "copy of the secret in the URL, and it can be opened only through the Lumina page.",
  '<table><tr><th>Setting</th><th>Value in the tested run</th></tr>'
  '<tr><td>Link lifetime</td><td>24 hours, configurable. Same as before.</td></tr>'
  '<tr><td>Code lifetime</td><td><b>10 minutes</b> from the moment it is sent.</td></tr>'
  '<tr><td>View window after a correct code</td><td>10 minutes. Reloading inside it shows the report again; after it, a new code is needed.</td></tr>'
  '<tr><td>View cap</td><td>10 opens per link. Now a hard cap, refused at the moment the eleventh code is entered, rather than a nightly check.</td></tr>'
  '<tr><td>Wrong codes</td><td>5 in total, then the link locks itself for good.</td></tr>'
  '<tr><td>Code requests</td><td>At most one a minute, and 5 per link, then the link locks.</td></tr>'
  '<tr><td>Download allowed</td><td>Yes, logged separately from a view.</td></tr>'
  '<tr><td>Public file link</td><td class="bad">Removed. There is no URL that opens the PDF without a code.</td></tr>'
  '</table>')}

{step("02", "Each recipient gets an email with no patient data and no secret in it",
  "The message carries a count, a button, and one new line telling the recipient a code will be "
  "emailed when they open the link. Nothing in it opens the report on its own.",
  pane("Outlook - Inbox", facility_email(),
      "The facility email as an administrator sees it, rendered from the exact HTML the code "
      "produced today for the test facility, with a representative facility and contact substituted "
      "in and the link secret removed.",
      "Forwarding this email achieves nothing: the code is sent to the address it was issued to, "
      "not to whoever clicks the button.", 900))}

{step("03", "The link opens a Lumina page that shows nothing yet",
  "No login, no account. The page names the facility and the report date, shows a masked version of "
  "the address on file so the reader knows where to look, and offers one button.",
  mac(derive("20_gate_request.png", crop=(0, 0, 1040, 480)), "Lumina Care - report page, before any code",
      "The request screen. Facility name, report date, link expiry and the masked mailbox. No "
      "patient information is on this page, and none will be until a code is entered.",
      None, 900))}

{step("04", "One click, and a six-digit code lands in that mailbox",
  "The page emails a code to the address the link was issued to and switches to the code box. Asking "
  "again inside a minute is refused, so a stuck button cannot flood an inbox.",
  pair(
    pane("Outlook - Inbox", code_email(),
        "The code email, from the template in the code. Ten minutes, six digits, and a line saying "
        "what to do if you did not ask for it.", None),
    mac(derive("27_gate_code_sent.png", crop=(0, 0, 1040, 500)), "Lumina Care - report page, code sent",
        "The page after the click, captured live: it confirms where the code went and waits.", None)
  ) + mac(derive("24_gate_throttle.png", crop=(0, 0, 1040, 500)), "Lumina Care - report page, second request inside a minute",
        "Captured live: asking for another code inside sixty seconds is refused, and the first code "
        "still stands.", None, 900))}

{step("05", "The right code opens the report; the wrong one costs a strike",
  "A correct code counts one open, unlocks the report for ten minutes and shows the PDF on the page "
  "with a download button. A wrong code says how many attempts are left. The fifth wrong code locks "
  "the link permanently.",
  pair(
    mac(derive("21_gate_code.png", crop=(0, 0, 1040, 500)), "Lumina Care - report page, enter the code",
        "The code box. Numeric keypad on a phone, one-time-code autofill where the mail app offers it.", None),
    mac(derive("23_gate_wrong_code.png", crop=(0, 0, 1040, 500)), "Lumina Care - report page, wrong code",
        "Captured live after typing 000000: one strike used, four left.", None)
  ) + mac(shot("22_gate_report.png"), "Lumina Care - report page, unlocked",
        "The report after the correct code, captured live. The PDF renders inline, Download PDF is "
        "logged as a download, and the line under the title says when this view closes.",
        "This is the same PDF the job files on the Facility record. The page streams it only inside "
        "the ten-minute window and only for the link that was just unlocked.", 900))}

{step("06", "Everything that happened is on the record, with IP and browser",
  "This is the new audit trail. Each link keeps counts as before, and now also an access log: one "
  "row per event with the time, the caller's IP address and browser, and a short note such as "
  "which attempt or which open it was.",
  mac(derive("28_link_access_log.png", crop=SF_CROP, marks=(
        ((25, 140, 770, 400), "One row per event, newest first", "above"),
     )), "Salesforce - Readmission Report Link, Related tab",
     "The link used in steps 03 to 05, as Lumina staff see it. The wrong code, the refused second "
     "code request, the open, the inline fetch and the download are each a row with the IP address "
     "they came from. Underneath, Salesforce's own field history shows the counters changing and "
     "names the site user that changed them.",
     "The IP address shown is the tester's real address on the day. A made-up link has no row to log "
     "against and leaves no trace at all, which is deliberate: the log records what happened to real "
     "links, not what strangers typed.", 1000))}

{mac(derive("29_access_log_code_sent.png", crop=(25, 140, 1190, 320)),
     "Salesforce - Access Log, full list",
     "The full list view adds the browser and the exact time. This row is a genuine code send from "
     "the live test: the address it went to is the tester's, so the record is shown from the list "
     "rather than the details page.", None, 1000)}

{mac(derive("26_link_record_details.png", crop=SF_CROP, marks=(
        ((25, 318, 770, 592), "Counts, code state and the unlock window", "left"),
     )), "Salesforce - Readmission Report Link, Details tab",
     "The same link's details: who it was issued to, when it expires, how many opens and downloads, "
     "when the code was sent, and that the last change was made by the site's own user rather than "
     "by a member of staff.", None, 1000)}

<h2 class="sh">What the audit answers now</h2>
<p class="intro">The 9 September walkthrough had two honest gaps in this table. Both are closed.</p>
<table>
  <tr><th>Question</th><th>9 September</th><th>Now</th><th>How</th></tr>
  <tr><td><b>Which mailbox opened it</b></td><td class="ok">Yes</td><td class="ok">Yes</td>
      <td>Each recipient has their own link, and only that mailbox can receive the code</td></tr>
  <tr><td><b>A named human, not a mailbox</b></td><td class="warn">Partly</td><td class="ok">Yes, to the mailbox and the device</td>
      <td>A forwarded link no longer opens anything. Whoever opened it had the mailbox and the code in the same ten minutes</td></tr>
  <tr><td><b>IP address of the viewer</b></td><td class="bad">No</td><td class="ok">Yes</td>
      <td>Every event on the link carries the caller's IP address and browser, on our own object, no add-on licence</td></tr>
  <tr><td>Which mailbox downloaded it, when, how many times</td><td class="ok">Yes</td><td class="ok">Yes</td>
      <td>Counts per link as before, plus one log row per event</td></tr>
  <tr><td>Attempts to get in</td><td class="bad">Not visible</td><td class="ok">Yes</td>
      <td>Wrong codes, refused code requests and lockouts are logged with their IP</td></tr>
</table>

<h2 class="sh">The other paths</h2>
<p class="intro">Every one of these was exercised live on 15 September, not only in automated tests.</p>

{step("07", "Five wrong codes, or too many code requests, and the link locks itself",
  "The lock is permanent for that link. The page shows the same generic message it shows for an expired "
  "or made-up link, so a person guessing cannot tell which case they hit. The only way back is a new "
  "link, reissued by Lumina from the Facility record.",
  mac(derive("25_gate_unavailable.png", crop=(0, 0, 1040, 430)), "Lumina Care - report page, link no longer usable",
      "Captured live from a link locked by a fifth wrong code. Expired links, capped links, superseded "
      "links and made-up links all show exactly this page.", None, 900))}

{step("08", "The view cap is now hard, and a reissue kills the old link",
  "When a link already has ten opens, the next correct code is refused and the link closes with the "
  "reason recorded. Reissuing a report, whether by the Resend button or by the job running again, "
  "closes the previous live link to the same address as superseded, so only the newest link works.",
  '<table><tr><th>Case</th><th>Behaviour</th><th>Seen live</th></tr>'
  '<tr><td>Eleventh open attempted</td><td>Refused; link closed as <b>View limit reached</b></td><td class="ok">Yes</td></tr>'
  '<tr><td>Fifth wrong code</td><td>Link closed as <b>Locked</b>; the right code no longer helps</td><td class="ok">Yes</td></tr>'
  '<tr><td>Code entered after ten minutes</td><td>Refused, no strike, back to the request button</td><td class="ok">Yes</td></tr>'
  '<tr><td>Report opened after the ten-minute window</td><td>Page asks for a new code; the PDF address answers 404</td><td class="ok">Yes</td></tr>'
  '<tr><td>Resend button, or the daily job again</td><td>New links issued; previous links to the same address closed as <b>Superseded</b></td><td class="ok">Yes, both</td></tr>'
  '<tr><td>Link expired</td><td>Same generic page as above</td><td class="ok">Yes</td></tr>'
  '<tr><td>Sandbox run</td><td>A code is emailed only to the testers on the redirect list, never to a facility</td><td class="ok">Yes</td></tr>'
  '</table>')}

<div class="gap good">
  <h3>The Resend button is unchanged, and it is still the route to a fresh link</h3>
  <p>Staff open the Facility, click <b>Resend Readmissions Report</b>, confirm the addresses, and each
     recipient gets a brand new link and a new code flow. The previous link to that address is closed
     as superseded at the same moment. Nothing about the button changed; what it issues did.</p>
</div>

{mac(derive("16_facility_record_with_resend.png", crop=(0, 0, 1586, 76), marks=(
        ((1136, 14, 1344, 56), "Reissues the link, one per recipient", "above"),
     )), "Salesforce - Facility record, header",
     "Where the button lives, unchanged from the 9 September walkthrough.", None, 1000)}

<p class="note">Also new on the Facility record: a <b>Readmission Report Links</b> list on the Related tab,
   showing each link's recipient, role, report date, opens, downloads and status, so staff can see
   which links are live, superseded, locked or capped before reissuing. Not pictured, because the
   test facility's rows carry the testers' own addresses.</p>

<h2 class="sh">What a visitor to the page can and cannot reach</h2>
<p class="intro">Worth stating exactly, because this page is on the public internet.</p>
<table>
  <tr><th>Reachable</th><th>Only when</th></tr>
  <tr><td>The facility name and report date on one link row</td><td>The visitor holds that link's URL</td></tr>
  <tr><td>A code email</td><td>Sent only to the address on that row, never to the visitor</td></tr>
  <tr><td>The PDF for that row</td><td>Inside the ten minutes after a correct code, and only while the link is live</td></tr>
  <tr><td>Anything else: other reports, patients, facilities, the file list</td><td class="bad">Never. The site user has no access to any of those objects, and the page never asks for them.</td></tr>
</table>
<p class="note">Identity is possession of the mailbox <b>at the moment of viewing</b>, which is the
   same standard Microsoft's one-time-passcode mail encryption applies, plus a record of the device
   that did the viewing.</p>

<h2 class="sh">Still needed before production</h2>
<ol class="asks">
  <li><b>Register Salesforce Sites in production, once</b><span>Setup, Sites, accept the terms, Register.
      A two-minute job for a Lumina admin. The domain already exists. Until it is done every page of
      the site shows a maintenance message, which is exactly what happened in the sandbox before we
      registered it there.</span></li>
  <li><b>Verify the sending address in production</b><span>Create <code>tcm@luminacare.com</code> as
      an Org-Wide Email Address, verify it, and allow all profiles to use it, so both the report email
      and the code email come from it.</span></li>
  <li><b>Confirm the numbers</b><span>24-hour link, 10-minute code, 10 opens, 5 wrong codes. All are
      settings or constants that change without a redesign.</span></li>
  <li><b>Confirm the retention rule</b><span>The stored PDF is deleted once every link to it is dead,
      after a seven-day grace period. Unchanged from last time and still awaiting a yes.</span></li>
  <li><b>An owner for the facilities with no contact</b><span>Unchanged: 159 of 326 enrolled facilities
      have neither an administrator nor a director-of-nursing email on file. No delivery method fixes
      that.</span></li>
  <li><b>Compliance sign-off in writing</b><span>Possession of the mailbox at view time, with IP and
      browser logged per event. Worth recording rather than agreeing verbally.</span></li>
</ol>

</main>

<footer>
  Propela Tech &middot; LMNA-581 &middot; Delivery walkthrough, revision 2<br>
  Screens captured from <b>lumDev</b> (partial sandbox) on 15 September 2026 in a browser with no
  Salesforce session. All patient names are fabricated. Production has not been touched.
</footer>

</div></body></html>"""


def render(html_text, pdf=True):
    if not pdf:
        OUT_HTML.write_text(html_text.replace("__PAGE_H__", "16000"))
        return
    probe_html, probe_pdf = DOCS / "_probe.html", DOCS / "_probe.pdf"
    probe_html.write_text(html_text.replace("__PAGE_H__", "20000"))
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-sandbox",
                    "--no-pdf-header-footer", "--virtual-time-budget=6000",
                    f"--print-to-pdf={probe_pdf}", f"file://{probe_html}"],
                   capture_output=True, timeout=240)
    height = None
    if probe_pdf.exists():
        subprocess.run(["pdftoppm", "-png", "-r", "96", "-f", "1", "-l", "1",
                        str(probe_pdf), str(DOCS / "_probe")], capture_output=True)
        pngs = sorted(DOCS.glob("_probe-*.png"))
        if pngs:
            from PIL import Image
            im = Image.open(pngs[0]).convert("RGB")
            w, h = im.size
            px = im.load()
            for y in range(h - 1, -1, -1):
                if any(sum(px[x, y]) < 330 for x in range(0, w, 3)):
                    height = y + 30
                    break
            print(f"  probe raster {w}x{h}, content bottom -> page height {height}")
            for p in pngs:
                p.unlink()
    if not height:
        height = 20000
        print("  WARNING: could not measure raster, falling back to 20000px")
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
    render(text, pdf="--no-pdf" not in sys.argv)
    body = OUT_HTML.read_text()
    print(f"HTML  {OUT_HTML.name}  {len(body):,} bytes")
    print(f"  embedded images:  {body.count('src=\"data:image')}")
    print(f"  external refs:    {len(re.findall(r'src=\"(?!data:)', body))} (must be 0)")
    print(f"  em dashes:        {body.count(chr(8212))} (must be 0)")
    for bad in ("james@", "gmail", "propela.tech\""):
        print(f"  '{bad}' occurrences: {body.count(bad)} (must be 0)")
    if OUT_PDF.exists() and "--no-pdf" not in sys.argv:
        info = subprocess.run(["pdfinfo", str(OUT_PDF)], capture_output=True, text=True).stdout
        pages = re.search(r"Pages:\s+(\d+)", info)
        print(f"PDF   {OUT_PDF.name}  pages: {pages.group(1) if pages else '?'} (must be 1)")
