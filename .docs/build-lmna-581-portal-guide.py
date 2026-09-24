#!/usr/bin/env python3
"""
Builds the LMNA-581 phase-two guide: a one-time code in front of the readmissions report, served
from a page on a Salesforce Site. Describes the model that was built and live-tested in lumDev on
15 September 2026.

Two outputs from one source. The HTML is interactive, because the thing worth showing Chayim is
how the gate behaves on each path, and a static picture of a code box explains nothing. The PDF
is the same document with the controls hidden and the scenarios written out, so it survives being
emailed.

Self-contained: the Propela logo and the three sandbox screenshots are inlined, no CDN, no external
asset.

Usage: python3 .docs/build-lmna-581-portal-guide.py
"""
import base64, io, pathlib, re, subprocess, sys

DOCS = pathlib.Path(__file__).resolve().parent
BRAND = pathlib.Path.home() / "Documents" / "propela-tech" / "BRANDING"
LOGO = BRAND / "LOGO" / "MAIN Logo" / "Yellow-white" / "Web" / "propela-logo-yellow-white-rgb.svg"
SHOTS = DOCS / "shots-lmna-581"
SHOT_REQUEST = SHOTS / "20_gate_request.png"
SHOT_CODE = SHOTS / "21_gate_code.png"
SHOT_REPORT = SHOTS / "22_gate_report.png"
OUT_HTML = DOCS / "lmna-581-pin-gated-portal-2026-09-14.html"
OUT_PDF = DOCS / "lmna-581-pin-gated-portal-2026-09-14.pdf"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WIDTH = 1180

NAVY, YELLOW = "#0c263b", "#f5fd7e"
INK, MUTED, LINE = "#16212b", "#5b6b7a", "#dde3ea"

SANDBOX_HOST = "data-efficiency-9627--partialsb.sandbox.my.salesforce-sites.com"
PROD_HOST = "data-efficiency-9627.my.salesforce-sites.com"


def logo_svg():
    if not LOGO.exists():
        sys.exit(f"missing brand logo: {LOGO}")
    svg = LOGO.read_text()
    svg = re.sub(r"<\?xml[^>]*\?>", "", svg).strip()
    # Namespaced ids would collide if the page ever carries a second copy.
    return svg.replace('id="Layer_2"', 'id="propela-logo" class="logo"')


def shot_data_uri(path, crop_height=None):
    """Base64 PNG. Optionally trims empty ground below the content so the figure stays tight."""
    if not path.exists():
        sys.exit(f"missing screenshot: {path}")
    data = path.read_bytes()
    if crop_height:
        try:
            from PIL import Image
            with Image.open(io.BytesIO(data)) as im:
                if im.height > crop_height:
                    im = im.crop((0, 0, im.width, crop_height))
                    buf = io.BytesIO()
                    im.save(buf, format="PNG", optimize=True)
                    data = buf.getvalue()
        except Exception as e:  # pragma: no cover - cropping is a nicety
            print(f"  crop skipped for {path.name} ({e})")
    return "data:image/png;base64," + base64.b64encode(data).decode()


TEMPLATE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>LMNA-581 phase two: a one-time code in front of the readmissions report</title>
<style>
  * { box-sizing: border-box }
  :root {
    --navy: %NAVY%; --yellow: %YELLOW%; --ink: %INK%; --muted: %MUTED%; --line: %LINE%;
    --mono: 'SF Mono', Menlo, Consolas, monospace;
    --ok: #1f7a3d; --bad: #b3261e; --warn: #8a6100;
  }
  body {
    margin: 0; background: #f4f6f8; color: var(--ink);
    font: 15px/1.6 'DM Sans', -apple-system, 'SF Pro Text', Helvetica, Arial, sans-serif;
  }
  .page { max-width: %WIDTH%px; margin: 0 auto; background: #fff }
  h1, h2, h3 { font-family: 'Antonia Variable', Georgia, 'Times New Roman', serif; font-weight: 400 }

  header { background: var(--navy); color: #fff; padding: 26px 40px 30px;
    border-bottom: 5px solid var(--yellow) }
  .htop { display: flex; justify-content: space-between; align-items: flex-start; gap: 24px }
  .logo { height: 30px; width: auto }
  .meta { font: 10.5px var(--mono); letter-spacing: .09em; text-transform: uppercase;
    color: #b9d8f5; text-align: right; line-height: 1.8 }
  header h1 { margin: 20px 0 8px; font-size: 31px; line-height: 1.15 }
  header p { margin: 0; max-width: 78ch; color: #cfe0ee; font-size: 15.5px }

  .bluf { background: #10314b; color: #fff; padding: 22px 40px 24px;
    border-bottom: 1px solid rgba(255,255,255,.12) }
  .bluf .lead { font-size: 18px; font-weight: 600; margin: 0 0 12px; max-width: 86ch }
  .bluf ul { margin: 0; padding-left: 20px; color: #cfe0ee; font-size: 14.5px }
  .bluf li { margin-bottom: 5px }
  .bluf b { color: var(--yellow) }

  .strip { display: grid; grid-template-columns: repeat(3, 1fr); border-bottom: 1px solid var(--line) }
  .strip div { padding: 16px 24px; border-right: 1px solid var(--line) }
  .strip div:last-child { border-right: 0 }
  .strip h4 { margin: 0 0 4px; font: 10.5px var(--mono); letter-spacing: .1em;
    text-transform: uppercase; color: var(--muted) }
  .strip p { margin: 0; font-size: 14px }

  main { padding: 8px 40px 44px }
  section { margin-top: 34px }
  .snum { font: 11px var(--mono); letter-spacing: .12em; color: var(--muted) }
  h2 { font-size: 22px; margin: 4px 0 6px; display: flex; align-items: center; gap: 11px }
  h2:before { content: ''; width: 5px; height: 21px; background: var(--yellow); border-radius: 3px }
  .lede { margin: 6px 0 16px; max-width: 88ch; color: #46586a }

  table { width: 100%; border-collapse: collapse; font-size: 13.5px; margin-top: 12px }
  th { background: var(--navy); color: #fff; text-align: left; padding: 9px 12px;
    font: 10px var(--mono); letter-spacing: .08em; text-transform: uppercase }
  td { padding: 10px 12px; border-bottom: 1px solid #e8edf2; vertical-align: top }
  tr:nth-child(even) td { background: #f8fafc }
  code { font: 12px var(--mono); background: #eef2f6; padding: 1px 5px; border-radius: 3px;
    word-break: break-word }
  .yes { color: var(--ok); font-weight: 600 }
  .no { color: var(--bad); font-weight: 600 }
  .partly { color: var(--warn); font-weight: 600 }

  .note { background: #eef4fb; border-left: 3px solid #8fb8dd; padding: 12px 16px;
    font-size: 13.5px; margin-top: 14px }
  .note.warn { background: #fdf6e3; border-left-color: #d8b13a }

  /* ---- simulator ------------------------------------------------------------------ */
  .sim { border: 1px solid var(--line); border-radius: 8px; overflow: hidden; margin-top: 16px }
  .simbar { background: #f2f5f8; border-bottom: 1px solid var(--line); padding: 12px 16px;
    display: flex; flex-wrap: wrap; gap: 8px; align-items: center }
  .simbar span.lbl { font: 10px var(--mono); letter-spacing: .1em; text-transform: uppercase;
    color: var(--muted); margin-right: 4px }
  button.scn { font: 12.5px inherit; padding: 7px 13px; border-radius: 4px; cursor: pointer;
    border: 1px solid #c3ccd6; background: #fff; color: var(--ink) }
  button.scn:hover { border-color: var(--navy) }
  button.scn[aria-pressed="true"] { background: var(--navy); color: #fff; border-color: var(--navy) }
  button.reset { margin-left: auto; border-style: dashed }

  .simbody { display: grid; grid-template-columns: 1.35fr 1fr; gap: 0 }
  .flow { padding: 18px; border-right: 1px solid var(--line) }
  .node { border: 1px solid var(--line); border-radius: 6px; padding: 10px 12px; background: #fff;
    position: relative; transition: background .25s, border-color .25s }
  .node + .node { margin-top: 26px }
  .node + .node:before { content: ''; position: absolute; top: -21px; left: 22px; width: 2px;
    height: 16px; background: #c9d4de }
  .node + .node:after { content: ''; position: absolute; top: -8px; left: 18px;
    border: 5px solid transparent; border-top-color: #c9d4de }
  .node h5 { margin: 0 0 3px; font-size: 13.5px }
  .node p { margin: 0; font-size: 12.5px; color: var(--muted) }
  .node.active { border-color: var(--navy); background: #f2f7fc }
  .node.pass { border-color: #9ed3b2; background: #f1faf4 }
  .node.fail { border-color: #e8a9a3; background: #fdf3f2 }
  .node .tag { position: absolute; right: 10px; top: 9px; font: 10px var(--mono);
    letter-spacing: .06em; text-transform: uppercase }
  .node.pass .tag { color: var(--ok) }
  .node.fail .tag { color: var(--bad) }

  .side { padding: 18px; background: #fbfcfd }
  .card { border: 1px solid var(--line); border-radius: 6px; background: #fff; overflow: hidden }
  .card h5 { margin: 0; padding: 9px 12px; background: #f2f5f8; border-bottom: 1px solid var(--line);
    font: 10.5px var(--mono); letter-spacing: .08em; text-transform: uppercase; color: var(--muted) }
  .fields { padding: 6px 12px 10px }
  .fld { display: flex; justify-content: space-between; gap: 10px; padding: 5px 0;
    border-bottom: 1px dotted #e6ebf0; font-size: 12.5px }
  .fld:last-child { border-bottom: 0 }
  .fld span:first-child { font: 11.5px var(--mono); color: var(--muted); word-break: break-word }
  .fld span:last-child { font: 12px var(--mono); font-variant-numeric: tabular-nums;
    text-align: right }
  .fld.changed span:last-child { background: #d9f2e2; color: #14532d; border-radius: 3px;
    padding: 0 5px }

  .feed { margin-top: 14px; background: #101c27; border-radius: 6px; padding: 12px;
    font: 12px var(--mono); color: #cfd9e3; min-height: 190px; max-height: 300px; overflow: auto }
  .feed div { padding: 2px 0; animation: fade .22s ease both }
  .feed .w { color: #7ee2a8 }
  .feed .x { color: #ff9b91 }
  .feed .s { color: var(--yellow) }
  .feed .d { color: #8b9aa9 }
  @keyframes fade { from { opacity: 0; transform: translateY(3px) } to { opacity: 1 } }

  /* the mock page the recipient sees */
  .screen { margin-top: 14px; border: 1px solid #c9d0d8; border-radius: 7px; overflow: hidden }
  .screenbar { background: linear-gradient(#f6f7f9, #e9ecf0); border-bottom: 1px solid #d6dbe1;
    padding: 7px 11px; font: 11px var(--mono); color: #61697a; display: flex; gap: 6px;
    align-items: center }
  .dot { width: 9px; height: 9px; border-radius: 50%; display: inline-block }
  .screenbody { padding: 20px 18px; text-align: center; background: #fff; min-height: 150px }
  .screenbody .fac { font-size: 15px; font-weight: 600; color: #30385c }
  .screenbody .sub { font-size: 12.5px; color: var(--muted); margin: 3px 0 14px }
  .pinboxes { display: flex; gap: 6px; justify-content: center; margin-bottom: 12px }
  .pinboxes i { width: 30px; height: 38px; border: 1px solid #c3ccd6; border-radius: 4px;
    font: 17px var(--mono); font-style: normal; line-height: 38px; background: #fbfcfd }
  .pinboxes i.on { border-color: var(--navy); background: #fff }
  .sbtn { display: inline-block; background: #1f5fe0; color: #fff; padding: 8px 16px;
    border-radius: 4px; font-size: 12.5px; font-weight: 600 }
  .sbtn.ghost { background: #fff; color: #1f5fe0; border: 1px solid #1f5fe0 }
  .screenbody .msg { font-size: 13px; margin-top: 8px }
  .screenbody .msg.bad { color: var(--bad) }
  .screenbody .msg.ok { color: var(--ok) }
  .docmock { text-align: left; border: 1px solid var(--line); border-radius: 4px; padding: 10px;
    font-size: 11.5px; color: #44525f }
  .docmock b { display: block; font-size: 13px; color: var(--ink); margin-bottom: 2px }

  /* real screenshots from the sandbox */
  .shots { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; margin-top: 14px }
  .shot img { width: 100%; height: auto; display: block; border: 1px solid #c9d0d8;
    border-radius: 6px }
  .shot p { margin: 8px 2px 0; font-size: 13px; color: var(--muted); line-height: 1.5 }
  .shot p b { color: var(--ink) }
  .shot.wide { grid-column: 1 / -1; max-width: 860px; margin: 6px auto 0 }

  .print-only { display: none }

  footer { background: var(--navy); color: #cfe0ee; padding: 20px 40px; font-size: 12.5px;
    display: flex; justify-content: space-between; gap: 20px; flex-wrap: wrap }
  footer b { color: #fff }

  @media screen and (max-width: 880px) {
    .simbody { grid-template-columns: 1fr }
    .flow { border-right: 0; border-bottom: 1px solid var(--line) }
    .strip, .shots { grid-template-columns: 1fr }
    main, header, .bluf, footer { padding-left: 20px; padding-right: 20px }
  }
  @media (prefers-reduced-motion: reduce) {
    * { animation: none !important; transition: none !important }
  }
  @media print {
    body { background: #fff }
    .simbar, .feed, .screen { display: none }
    .simbody { grid-template-columns: 1fr }
    .flow { border-right: 0 }
    .print-only { display: block }
    .node, .shot { break-inside: avoid }
    * { box-shadow: none !important }
  }
</style>
</head>
<body>
<div class="page">

<header>
  <div class="htop">
    %LOGO%
    <div class="meta">
      LMNA-581 &middot; phase two &middot; built<br>Lumina Care &middot; TCM readmissions<br>15 September 2026
    </div>
  </div>
  <h1>A one-time code in front of the readmissions report</h1>
  <p>What was built, how it behaves on every path, what it protects against, and what production
     needs before deploy. Written for Chayim after the sandbox test.</p>
</header>

<div class="bluf">
  <p class="lead">The email no longer carries anything that opens the report. It carries a link to a
     page we own; that page emails a six-digit code to the address on file, and the report opens
     only after the code is entered. Built and live-tested in the sandbox on 15 September 2026.</p>
  <ul>
    <li><b>You asked for the stronger option</b>, a code that expires after 10 minutes. It cannot
        live in the report email because the job sends at 8am and people open hours later, so the
        page asks for the code at view time instead.</li>
    <li><b>A forwarded email is now covered.</b> The code goes to the original address, so someone
        holding a forwarded link cannot get in unless they also control that mailbox.</li>
    <li><b>Nothing in production yet.</b> What production needs is listed at the end, two items
        for a Lumina admin. Deploy happens after your go-ahead.</li>
  </ul>
</div>

<div class="strip">
  <div><h4>Background</h4><p>Phase one shipped an expiring public file link, one per recipient, with
     an audit trail. Chris wanted the report protected by more than a URL.</p></div>
  <div><h4>The decision</h4><p>A one-time code, requested on the page and emailed to the address on
     file, valid for 10 minutes. The public file link is removed.</p></div>
  <div><h4>Status</h4><p>Built. 142 automated tests green. Every path below was exercised by hand
     in the sandbox with no Salesforce login. Not yet deployed to production.</p></div>
</div>

<main>

<section>
  <div class="snum">01</div>
  <h2>What the code protects, and how</h2>
  <p class="lede">A link is a bearer token: whoever holds it is in. The code adds a second thing to
     hold, and that second thing is only ever delivered to the mailbox on file. This is the
     difference from the earlier idea of a PIN printed in the same email, which protected the link
     but not a forwarded message.</p>
  <table>
    <tr><th>Concern</th><th>Phase one</th><th>Now</th></tr>
    <tr>
      <td><b>Someone guesses another facility's URL</b><br>
          <span style="color:var(--muted);font-size:12.5px">Chris's stated worry</span></td>
      <td class="yes">Already covered</td>
      <td class="yes">The link is 64 random characters, and there is no public file URL to guess
          at all. Wrong, expired and closed links all get the same page.</td>
    </tr>
    <tr>
      <td><b>The URL leaks on its own</b><br>
          <span style="color:var(--muted);font-size:12.5px">browser history, a pasted chat
          message, a screenshot, a proxy log</span></td>
      <td class="no">Opens the report</td>
      <td class="yes">Opens a request button and nothing else. A fresh code has to reach the
          mailbox on file.</td>
    </tr>
    <tr>
      <td><b>Someone tries codes until one works</b></td>
      <td>Not applicable</td>
      <td class="yes">Five wrong codes lock the link for good. A code lasts 10 minutes and has a
          million possibilities.</td>
    </tr>
    <tr>
      <td><b>The whole email is forwarded</b></td>
      <td class="no">Opens the report</td>
      <td class="yes">The code still goes to the original address. The forwardee is stuck at the
          request screen.</td>
    </tr>
    <tr>
      <td><b>The recipient's mailbox is compromised</b></td>
      <td class="no">Opens the report</td>
      <td class="partly">Still opens. Whoever controls the mailbox can request the code. No
          email-based delivery can close this one; it is the facility's mailbox security.</td>
    </tr>
  </table>
</section>

<section>
  <div class="snum">02</div>
  <h2>The change, in one line</h2>
  <p class="lede">The public file link goes away. That is what makes the code real rather than
     decorative. If we had kept the file link and put a code page in front of it, the file link
     would still work for anyone who had it.</p>
  <table>
    <tr><th>Step</th><th>Phase one</th><th>Now</th></tr>
    <tr><td>What the email carries</td>
        <td>A link that opens the report immediately</td>
        <td>A link to our page, a count of admissions, and the instruction to choose
            <i>Email me a code</i>. No code, no patient data.</td></tr>
    <tr><td>What the link points at</td>
        <td>Salesforce's own public file viewer</td>
        <td>A page we control, on a Salesforce Site. The only door.</td></tr>
    <tr><td>What unlocks the report</td>
        <td>Holding the URL</td>
        <td>A six-digit code emailed to the address on file when the reader asks for it. It
            works for 10 minutes, and the report then stays open for 10 minutes.</td></tr>
    <tr><td>Who serves the PDF</td>
        <td>Salesforce, to anyone with the URL</td>
        <td>Our page, only inside the 10 minutes after a correct code.</td></tr>
    <tr><td>The ten-view cap</td>
        <td>Applied by the nightly job, so a burst could overshoot</td>
        <td>Applied at the moment of the tenth correct code. The eleventh is refused.</td></tr>
    <tr><td>Who counts the opens</td>
        <td>Salesforce's own tracking, read back by us</td>
        <td>Our page, as it happens. A correct code is one open.</td></tr>
    <tr><td>Resending</td>
        <td>New link, old one keeps working until it expires</td>
        <td>New link, and the previous live link to that person is closed at once.</td></tr>
  </table>
</section>

<section>
  <div class="snum">03</div>
  <h2>How it behaves, path by path</h2>
  <p class="lede">Pick a scenario. The left column is the real check order in the code, the right
     is the recipient's screen and the record we keep for the audit trail. Every value shown is a
     real field on <code>Readmission_Report_Link__c</code>.</p>

  <div class="sim">
    <div class="simbar">
      <span class="lbl">Scenario</span>
      <button class="scn" data-s="happy" aria-pressed="false">Correct code</button>
      <button class="scn" data-s="download" aria-pressed="false">Downloads the PDF</button>
      <button class="scn" data-s="tooSoon" aria-pressed="false">Asks again too soon</button>
      <button class="scn" data-s="stale" aria-pressed="false">Code past 10 minutes</button>
      <button class="scn" data-s="wrong" aria-pressed="false">Wrong code, five times</button>
      <button class="scn" data-s="expired" aria-pressed="false">Link past 24 hours</button>
      <button class="scn" data-s="cap" aria-pressed="false">Eleventh code</button>
      <button class="scn" data-s="guess" aria-pressed="false">Guessed URL</button>
      <button class="scn" data-s="reissue" aria-pressed="false">Reissued link</button>
      <button class="scn reset" id="reset">Reset</button>
    </div>
    <div class="simbody">
      <div class="flow" id="flow">
        <div class="node" data-n="token"><span class="tag"></span>
          <h5>1. Find the report from the link</h5>
          <p>The page hashes the token from the URL and looks for exactly one matching row.</p></div>
        <div class="node" data-n="live"><span class="tag"></span>
          <h5>2. Is it still live?</h5>
          <p>Past its 24 hours, locked, superseded, or at the view cap: stop here with the
             generic page.</p></div>
        <div class="node" data-n="send"><span class="tag"></span>
          <h5>3. Email a code</h5>
          <p>Six digits, to the address the link was issued to, valid 10 minutes. Not again within
             60 seconds. Five per link, then locked.</p></div>
        <div class="node" data-n="code"><span class="tag"></span>
          <h5>4. Check the code</h5>
          <p>Compared against a stored hash, never a stored code. Wrong is a strike, expired is
             not. Five strikes lock the link.</p></div>
        <div class="node" data-n="record"><span class="tag"></span>
          <h5>5. Record the open and unlock</h5>
          <p>One open is written, the code is cleared, and the report is unlocked for 10
             minutes. The tenth open closes the link.</p></div>
        <div class="node" data-n="serve"><span class="tag"></span>
          <h5>6. Serve the report</h5>
          <p>Our page streams the PDF while the window is open. No second link exists for it.</p></div>
      </div>
      <div class="side">
        <div class="card">
          <h5>Readmission Report Link &middot; RRL-00000042</h5>
          <div class="fields" id="fields">
            <div class="fld" data-f="recipient"><span>Recipient_Email__c</span><span>a***@samplecare.com</span></div>
            <div class="fld" data-f="opens"><span>Opens__c</span><span>0</span></div>
            <div class="fld" data-f="downloads"><span>Downloads__c</span><span>0</span></div>
            <div class="fld" data-f="codes"><span>Codes_Sent__c</span><span>0</span></div>
            <div class="fld" data-f="failed"><span>Failed_Attempts__c</span><span>0</span></div>
            <div class="fld" data-f="unlocked"><span>Unlocked_Until__c</span><span>none</span></div>
            <div class="fld" data-f="closed"><span>Closed_Reason__c</span><span>none</span></div>
            <div class="fld" data-f="expires"><span>Expires_At__c</span><span>16 Sep 08:00</span></div>
          </div>
        </div>

        <div class="screen">
          <div class="screenbar">
            <span class="dot" style="background:#ff5f57"></span>
            <span class="dot" style="background:#febc2e"></span>
            <span class="dot" style="background:#28c840"></span>
            <span style="margin-left:6px" id="url">%SANDBOX_HOST%/report?t=&hellip;</span>
          </div>
          <div class="screenbody" id="screen"></div>
        </div>

        <div class="feed" id="feed"><div class="d">Pick a scenario to walk the real check order.</div></div>
      </div>
    </div>
  </div>

  <div class="print-only">
    <table>
      <tr><th>Scenario</th><th>What happens</th><th>What the record shows</th></tr>
      <tr><td><b>Correct code</b></td>
          <td>Token matches, link is live, the reader asks for a code, enters it, and it matches.
              The open is written, the code is cleared, and the PDF renders in the browser for 10
              minutes. Reloading inside that window shows it again without a new code.</td>
          <td><code>Opens__c 1</code>, <code>Codes_Sent__c 1</code>, <code>Unlocked_Until__c</code>
              set, first-opened timestamp set</td></tr>
      <tr><td><b>Downloads the PDF</b></td>
          <td>Same as above, then Download PDF is pressed. Counted separately, because reading on
              screen and taking a copy are different disclosures.</td>
          <td><code>Opens__c 1</code>, <code>Downloads__c 1</code></td></tr>
      <tr><td><b>Asks again too soon</b></td>
          <td>A second Email me a code inside 60 seconds is refused with "A code was sent less
              than a minute ago." No second email, no change to the record.</td>
          <td><code>Codes_Sent__c 1</code>, unchanged</td></tr>
      <tr><td><b>Code past 10 minutes</b></td>
          <td>The page says "That code has expired. Ask for a new one." No strike is counted.</td>
          <td><code>Failed_Attempts__c 0</code>, unchanged</td></tr>
      <tr><td><b>Wrong code, five times</b></td>
          <td>Each wrong attempt is counted and the page says how many are left. The fifth locks
              the link for good and shows the generic page. Lumina can reissue.</td>
          <td><code>Failed_Attempts__c 5</code>, <code>Closed_Reason__c Locked</code></td></tr>
      <tr><td><b>Link past 24 hours</b></td>
          <td>Stops at the second check with the generic page. No code is sent, no attempt is
              recorded.</td>
          <td>Unchanged, already expired</td></tr>
      <tr><td><b>Eleventh code</b></td>
          <td>A link already at 10 opens: the next correct code is refused and the link closes in
              that moment.</td>
          <td><code>Opens__c 10</code>, <code>Closed_Reason__c View limit reached</code></td></tr>
      <tr><td><b>Guessed URL</b></td>
          <td>No row matches. The page says exactly what it says for an expired link, so a guesser
              learns nothing from the difference.</td>
          <td>No record is touched</td></tr>
      <tr><td><b>Reissued link</b></td>
          <td>The Resend button, or the next morning's job, mints a new link for the same person.
              The previous live link is closed at once; only the newest works.</td>
          <td>Old row <code>Closed_Reason__c Superseded</code>, new row live</td></tr>
    </table>
  </div>
</section>

<section>
  <div class="snum">04</div>
  <h2>The real screens, from the sandbox test</h2>
  <p class="lede">Captured on 15 September 2026 in a browser with no Salesforce session, in the
     order a reader meets them. The facility and the patient row are test data. The address shown
     is the tester address, masked by the page itself. The header is Lumina's own.</p>
  <div class="shots">
    <div class="shot">
      <img src="%SHOT_REQUEST%" alt="The request screen: facility name, report date, link expiry, the masked address, and the Email me a code button">
      <p><b>The request screen.</b> What the link opens. Facility name, report date, when the link
         expires, the masked address the code will go to, and one button. Nothing from the
         report.</p>
    </div>
    <div class="shot">
      <img src="%SHOT_CODE%" alt="The code entry screen: a note that the code was emailed to the masked address, a six-digit code box, the Open report button and a Send me a new code link">
      <p><b>After Email me a code.</b> The page confirms where the code went, offers the six-digit
         box, and a link to send another. A wrong code shows how many attempts are left.</p>
    </div>
    <div class="shot wide">
      <img src="%SHOT_REPORT%" alt="The unlocked report: facility name, the 10-minute window notice, Download PDF and Open in a new tab buttons, and the PDF inline">
      <p><b>After a correct code.</b> The PDF inline, the two buttons, and the time the view stays
         open until. After that the reader asks for a new code.</p>
    </div>
  </div>
</section>

<section>
  <div class="snum">05</div>
  <h2>What we kept, and what is new</h2>
  <p class="lede">The delivery step was the only part replaced. Everything built and tested in
     phase one stays.</p>
  <table>
    <tr><th>Piece</th><th>Status</th><th>Why</th></tr>
    <tr><td>The PDF itself and how it is generated</td><td class="yes">Kept</td>
        <td>Unchanged. Still one file per facility per day, filed on the facility record.</td></tr>
    <tr><td>One link per recipient, and the audit trail behind it</td><td class="yes">Kept</td>
        <td>This is what makes an open attributable to a person. It is now more accurate, because
            our own page records it at the moment of disclosure.</td></tr>
    <tr><td>Resend button on the facility record</td><td class="yes">Kept</td>
        <td>Reissues a new link and closes the old one as superseded. No change to the button
            itself.</td></tr>
    <tr><td>The daily digest to Kevin</td><td class="yes">Kept</td>
        <td>Now counts locked links, so a facility failing to get in is visible the next
            morning.</td></tr>
    <tr><td>Deleting the stored report once every link is dead</td><td class="yes">Kept</td>
        <td>Same 7 day grace. A file is deleted only when no live link points at it.</td></tr>
    <tr><td>Salesforce's public file link</td><td class="no">Removed</td>
        <td>It was the open door. Removing it is what makes the code meaningful.</td></tr>
    <tr><td>A page on a Salesforce Site, and a locked-down guest profile</td><td class="partly">New</td>
        <td>One page, one purpose. The guest holds no record or field permission at all; our code
            reaches the link row and the file, and only by the link's fingerprint. It cannot see
            a facility, a patient or an admission.</td></tr>
    <tr><td>Link and code stored as fingerprints</td><td class="partly">New</td>
        <td>We never store the link or the code itself, so reading our database does not let
            anyone in.</td></tr>
    <tr><td>An access log on every link</td><td class="partly">New</td>
        <td>Every step on a link, from the code being sent to the report being opened or
            downloaded, is logged with the time, the IP address and the browser, so a disclosure
            can be traced to a device as well as to a mailbox.</td></tr>
  </table>
  <div class="note">
    For the compliance conversation: this narrows the surface rather than widening it. The page
    that queries patient data stays inside Salesforce, run by the job. The public page only ever
    hands over a file that was already produced, and only inside the minutes after a code that
    reached the mailbox on file.
  </div>
</section>

<section>
  <div class="snum">06</div>
  <h2>Answers to the questions that came up in the thread</h2>
  <table>
    <tr><th>Question</th><th>Answer</th></tr>
    <tr><td>Would a Salesforce external site be secure?</td>
        <td>Yes, as long as the guest profile stays as narrow as it is now: two pages and the
            classes behind them, no objects, no fields. That is the whole surface, and it is
            written down in the technical page for sign-off.</td></tr>
    <tr><td>Do they need a licence per facility?</td>
        <td>No. Everyone arrives as the same guest user, which is included. No per-facility cost,
            no logins to hand out, nothing for 326 facilities to forget.</td></tr>
    <tr><td>Is there already a password field on the facility record?</td>
        <td>We do not need one. A stored password per facility would need a reset flow, a place to
            keep it and a rule for who may see it. A code per view avoids all three.</td></tr>
    <tr><td>PIN or password?</td>
        <td>Neither is stored or remembered. A fresh six-digit code each time, sent to the address
            on file when the reader asks.</td></tr>
    <tr><td>Five-minute expiry, and request a new one?</td>
        <td>Yes, with 10 minutes rather than five, so a slow inbox does not cost the reader a
            second round. The reader asks for the code on the page, which is why it can be short:
            it is issued when they are sitting in front of it, not at 8am.</td></tr>
    <tr><td>Does it follow the same rules for who gets it?</td>
        <td>Yes, unchanged. Administrator if there is one, director of nursing if not, nobody if
            neither, and the digest names the facilities it skipped.</td></tr>
  </table>
</section>

<section>
  <div class="snum">07</div>
  <h2>What production needs</h2>
  <p class="lede">Nothing here is a build task. Two steps are for a Lumina admin, the rest are on
     us at deploy time.</p>
  <table>
    <tr><th>#</th><th>Needed</th><th>From</th></tr>
    <tr><td>01</td>
        <td><b>Register Salesforce Sites once in production.</b> Setup, then Sites, accept the
            terms, then Register My Salesforce Site Domain. The domain
            <code>%PROD_HOST%</code> already exists. Until this is done every page
            shows a maintenance notice.</td>
        <td>Lumina admin</td></tr>
    <tr><td>02</td>
        <td><b>Allow the sender address.</b> The org-wide address <code>tcm@luminacare.com</code>
            should be allowed for all profiles, or for the site guest profile, so the code email
            comes from it. Otherwise the code email is sent as the site user, which works but
            reads worse.</td>
        <td>Lumina admin</td></tr>
    <tr><td>03</td>
        <td><b>Point the site at the production domain</b> before deploy, and assign the guest
            permission set once the site exists. Production links will read
            <code>https://%PROD_HOST%/report?t=&hellip;</code></td>
        <td>Propela</td></tr>
    <tr><td>04</td>
        <td><b>Deploy, by a person, after your go-ahead.</b> We prepare the files and the exact
            command.</td>
        <td>Propela, after Chayim</td></tr>
    <tr><td>05</td>
        <td><b>An owner for the missing contacts.</b> 159 of 326 enrolled facilities still have
            neither an administrator nor a director-of-nursing email, mostly GHC and Complete
            Care. No delivery method fixes that.</td>
        <td>Lumina</td></tr>
  </table>
</section>

</main>

<footer>
  <div><b>LMNA-581 phase two</b> &middot; code-gated report access &middot; built and tested in the sandbox, not yet in production</div>
  <div>Propela Tech &middot; 15 September 2026</div>
</footer>

</div>

<script>
(function () {
  var FIELDS = {
    recipient: 'a***@samplecare.com', opens: '0', downloads: '0', codes: '0', failed: '0',
    unlocked: 'none', closed: 'none', expires: '16 Sep 08:00'
  };
  var NODES = ['token', 'live', 'send', 'code', 'record', 'serve'];
  var HOST = '%SANDBOX_HOST%';

  var flow = document.getElementById('flow');
  var feed = document.getElementById('feed');
  var screen = document.getElementById('screen');
  var url = document.getElementById('url');
  var timers = [];

  function clearTimers() { timers.forEach(clearTimeout); timers = []; }

  function setField(key, value, changed) {
    var row = document.querySelector('.fld[data-f="' + key + '"]');
    if (!row) return;
    row.lastElementChild.innerHTML = value;
    row.classList.toggle('changed', !!changed);
  }

  function requestScreen(msg, cls) {
    screen.innerHTML = '<div class="fac">Sample Care Center</div>' +
      '<div class="sub">Readmissions report for Monday, 14 September 2026. This link expires 16 Sep 08:00.</div>' +
      '<div class="msg">To open it, we will email a six-digit code to <b>a***@samplecare.com</b>. The code works for 10 minutes.</div>' +
      '<div style="margin-top:10px"><span class="sbtn">Email me a code</span></div>' +
      (msg ? '<div class="msg ' + (cls || '') + '">' + msg + '</div>' : '');
  }

  function codeScreen(filled, msg, cls) {
    var boxes = '';
    for (var i = 0; i < 6; i++) {
      boxes += '<i class="' + (i < filled ? 'on' : '') + '">' + (i < filled ? '•' : '&nbsp;') + '</i>';
    }
    screen.innerHTML = '<div class="fac">Sample Care Center</div>' +
      '<div class="sub">Readmissions report for Monday, 14 September 2026.</div>' +
      '<div class="pinboxes">' + boxes + '</div>' +
      '<span class="sbtn">Open report</span>' +
      '<div class="msg ' + (cls || '') + '">' + msg + '</div>';
  }

  function plainScreen(title, msg) {
    screen.innerHTML = '<div class="fac">' + title + '</div><div class="msg">' + msg + '</div>';
  }

  function reportScreen(note) {
    screen.innerHTML = '<div class="docmock"><b>Sample Care Center</b>' +
      'Patients discharged home who were readmitted, Monday, 14 September 2026.<br><br>' +
      '3 hospital admissions<br>' +
      '<span style="color:#8a94a0">Patient names and dates appear here in the real report.</span>' +
      '</div><div style="margin-top:8px"><span class="sbtn">Download PDF</span> ' +
      '<span class="sbtn ghost">Open in a new tab</span></div>' +
      '<div class="msg ok">' + note + '</div>';
  }

  function resetAll() {
    clearTimers();
    Object.keys(FIELDS).forEach(function (k) { setField(k, FIELDS[k], false); });
    NODES.forEach(function (n) {
      var el = flow.querySelector('.node[data-n="' + n + '"]');
      el.className = 'node';
      el.querySelector('.tag').textContent = '';
    });
    feed.innerHTML = '<div class="d">Pick a scenario to walk the real check order.</div>';
    url.textContent = HOST + '/report?t=…';
    requestScreen();
    document.querySelectorAll('button.scn').forEach(function (b) {
      b.setAttribute('aria-pressed', 'false');
    });
  }

  function log(cls, text) {
    var d = document.createElement('div');
    d.className = cls;
    d.textContent = text;
    feed.appendChild(d);
    feed.scrollTop = feed.scrollHeight;
  }

  function mark(node, state, tag) {
    var el = flow.querySelector('.node[data-n="' + node + '"]');
    el.className = 'node ' + state;
    el.querySelector('.tag').textContent = tag || '';
  }

  var UNAVAILABLE_TITLE = 'This report is no longer available.';
  var UNAVAILABLE_MSG = 'Reply to the email that brought you here and Lumina Care will send a new link.';

  function opened() {
    mark('token', 'pass', 'match'); mark('live', 'pass', 'live');
    log('s', 'GET /report?t=9f3c…  (no Salesforce login)');
    log('d', 'token hash matches 1 row → RRL-00000042 · live until 16 Sep 08:00');
  }

  function sentCode() {
    mark('send', 'pass', 'sent');
    setField('codes', '1', true);
    log('s', 'Email me a code');
    log('w', 'Codes_Sent__c → 1 · code emailed to a***@samplecare.com · hash stored, 10 min');
    codeScreen(0, 'We sent a code to a***@samplecare.com. It works for 10 minutes.');
  }

  // Each step: [delay, function]. Kept as data so the sequences read like the check order.
  var SCENARIOS = {
    happy: [
      [0, opened],
      [500, sentCode],
      [1200, function () { codeScreen(6, 'Checking…'); log('s', 'code submitted'); }],
      [1650, function () { mark('code', 'pass', 'ok'); log('d', 'hash compare ok · code cleared · attempts reset'); }],
      [2050, function () {
        mark('record', 'pass', 'written');
        setField('opens', '1', true); setField('unlocked', '09:22', true);
        log('w', 'Opens__c → 1'); log('w', 'Unlocked_Until__c → 09:22 (now + 10 min)');
      }],
      [2550, function () { mark('serve', 'pass', 'served'); reportScreen('Report open until 09:22. A reload inside that window needs no new code.'); log('d', 'PDF streamed by our page; the endpoint answers 404 outside the window'); }]
    ],
    download: [
      [0, function () { opened(); mark('send', 'pass', 'sent'); mark('code', 'pass', 'ok'); setField('codes', '1', false); log('s', 'code already accepted, report on screen'); }],
      [300, function () { setField('opens', '1', true); setField('unlocked', '09:22', true); reportScreen('Report open until 09:22.'); log('w', 'Opens__c → 1'); }],
      [900, function () { log('s', 'Download PDF pressed'); }],
      [1300, function () {
        mark('record', 'pass', 'written');
        setField('downloads', '1', true);
        log('w', 'Downloads__c → 1');
        log('d', 'counted separately: reading it and keeping a copy are different disclosures');
      }],
      [1800, function () { mark('serve', 'pass', 'served'); reportScreen('Copy downloaded. That copy is now theirs to keep.'); }]
    ],
    tooSoon: [
      [0, opened],
      [500, sentCode],
      [1200, function () { log('s', 'Send me a new code, 20 seconds later'); }],
      [1600, function () {
        mark('send', 'fail', 'refused');
        codeScreen(0, 'A code was sent less than a minute ago. Check your inbox and spam folder, or wait a minute and ask for another.', 'bad');
        log('x', 'Code_Sent_At__c + 60s is in the future → refused, nothing written, no second email');
        log('d', 'five codes per link at most; the sixth request locks it');
      }]
    ],
    stale: [
      [0, opened],
      [500, sentCode],
      [1200, function () { log('s', 'code entered 12 minutes later'); }],
      [1600, function () {
        mark('code', 'fail', 'expired');
        codeScreen(6, 'That code has expired. Ask for a new one.', 'bad');
        log('x', 'Code_Expires_At__c has passed → not a strike');
        log('d', 'Failed_Attempts__c stays 0 · back to the request screen');
      }]
    ],
    wrong: [
      [0, opened],
      [400, sentCode],
      [900, function () { mark('code', 'fail', 'wrong'); setField('failed', '1', true); codeScreen(6, 'That code is not right. 4 attempts left.', 'bad'); log('x', 'Failed_Attempts__c → 1'); }],
      [1300, function () { setField('failed', '2', true); codeScreen(6, 'That code is not right. 3 attempts left.', 'bad'); log('x', 'Failed_Attempts__c → 2'); }],
      [1700, function () { setField('failed', '3', true); codeScreen(6, 'That code is not right. 2 attempts left.', 'bad'); log('x', 'Failed_Attempts__c → 3'); }],
      [2100, function () { setField('failed', '4', true); codeScreen(6, 'That code is not right. 1 attempt left.', 'bad'); log('x', 'Failed_Attempts__c → 4'); }],
      [2600, function () {
        setField('failed', '5', true); setField('closed', 'Locked', true);
        mark('record', 'fail', 'locked'); mark('serve', 'fail', 'blocked');
        log('x', 'Failed_Attempts__c → 5'); log('x', 'Closed_Reason__c → Locked');
        log('s', 'counted in tomorrow’s digest to Kevin');
        plainScreen(UNAVAILABLE_TITLE, UNAVAILABLE_MSG);
      }]
    ],
    expired: [
      [0, function () { setField('expires', '14 Sep 08:00', true); log('s', 'GET /report?t=9f3c… on 15 Sep'); }],
      [400, function () { mark('token', 'pass', 'match'); log('d', 'token matches → RRL-00000042'); }],
      [900, function () {
        mark('live', 'fail', 'expired'); mark('send', 'fail', 'skipped'); mark('code', 'fail', 'skipped');
        log('x', 'expired 14 Sep 08:00 · stop before any code is offered');
        log('d', 'no email sent, no attempt recorded');
        plainScreen(UNAVAILABLE_TITLE, UNAVAILABLE_MSG);
      }]
    ],
    cap: [
      [0, function () { setField('opens', '10', false); log('s', 'link already opened 10 times, cap is 10'); }],
      [400, function () { opened(); }],
      [900, function () { sentCode(); }],
      [1500, function () { codeScreen(6, 'Checking…'); log('s', 'correct code submitted'); mark('code', 'pass', 'ok'); }],
      [1900, function () {
        mark('record', 'fail', 'cap'); mark('serve', 'fail', 'blocked');
        setField('closed', 'View limit reached', true);
        plainScreen(UNAVAILABLE_TITLE, UNAVAILABLE_MSG);
        log('x', 'Opens__c 10 >= cap → Closed_Reason__c → View limit reached');
        log('d', 'closed in the same moment, not overnight: the cap is a hard stop');
      }]
    ],
    guess: [
      [0, function () { url.textContent = HOST + '/report?t=aaaa…'; log('s', 'GET /report?t=aaaa…  (made-up token)'); }],
      [500, function () {
        mark('token', 'fail', 'no match');
        mark('live', 'fail', 'skipped'); mark('send', 'fail', 'skipped'); mark('code', 'fail', 'skipped');
        log('x', '0 rows match · nothing is read, nothing is written');
        plainScreen(UNAVAILABLE_TITLE, UNAVAILABLE_MSG);
      }],
      [1100, function () {
        log('d', 'identical wording to an expired link, on purpose');
        log('d', 'a guesser cannot tell a real report from a wrong address');
      }]
    ],
    reissue: [
      [0, function () { log('s', 'Resend pressed on the Facility record (or the 8am job runs again)'); }],
      [400, function () {
        setField('closed', 'Superseded', true); setField('unlocked', 'none', true);
        log('w', 'new row RRL-00000043 minted for a***@samplecare.com');
        log('x', 'RRL-00000042 Closed_Reason__c → Superseded');
      }],
      [900, function () { log('s', 'old link opened again'); mark('token', 'pass', 'match'); }],
      [1300, function () {
        mark('live', 'fail', 'closed'); mark('send', 'fail', 'skipped'); mark('code', 'fail', 'skipped');
        plainScreen(UNAVAILABLE_TITLE, UNAVAILABLE_MSG);
        log('d', 'only the newest link to that person works');
      }]
    ]
  };

  function run(name, button) {
    resetAll();
    button.setAttribute('aria-pressed', 'true');
    feed.innerHTML = '';
    SCENARIOS[name].forEach(function (step) {
      timers.push(setTimeout(step[1], step[0]));
    });
  }

  document.querySelectorAll('button.scn').forEach(function (b) {
    if (b.id === 'reset') return;
    b.addEventListener('click', function () { run(b.dataset.s, b); });
  });
  document.getElementById('reset').addEventListener('click', resetAll);
  resetAll();
})();
</script>
</body></html>
"""


def build():
    html = TEMPLATE
    for key, value in {
        "%LOGO%": logo_svg(),
        "%SHOT_REQUEST%": shot_data_uri(SHOT_REQUEST, crop_height=520),
        "%SHOT_CODE%": shot_data_uri(SHOT_CODE, crop_height=520),
        "%SHOT_REPORT%": shot_data_uri(SHOT_REPORT),
        "%NAVY%": NAVY, "%YELLOW%": YELLOW, "%INK%": INK, "%MUTED%": MUTED, "%LINE%": LINE,
        "%WIDTH%": str(WIDTH),
        "%SANDBOX_HOST%": SANDBOX_HOST, "%PROD_HOST%": PROD_HOST,
    }.items():
        html = html.replace(key, value)
    leftover = re.findall(r"%[A-Z_]+%", html)
    if leftover:
        sys.exit(f"unfilled placeholders: {sorted(set(leftover))}")
    return html


def render_pdf(html_path, pdf_path):
    """Measures the rendered height, then sizes @page to it so the PDF is one continuous page."""
    probe = DOCS / "_portal-probe.png"
    # The print layout differs from the screen one (simulator hidden, scenario table shown), so
    # the probe copy carries the @media print rules unconditionally. Otherwise the measured
    # height is the screen height and the PDF spills onto a second page.
    source = html_path.read_text()
    print_rules = re.search(r"@media print \{(.*?)\n  \}\n</style>", source, re.S)
    probe_html = DOCS / "_portal-probe.html"
    probe_html.write_text(
        source.replace("</style>", (print_rules.group(1) if print_rules else "") + "\n</style>", 1)
    )
    subprocess.run(
        [CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
         f"--window-size={WIDTH},20000", f"--screenshot={probe}", f"file://{probe_html}"],
        capture_output=True, check=False,
    )
    probe_html.unlink(missing_ok=True)
    height = 14000
    try:
        from PIL import Image
        with Image.open(probe) as im:
            px = im.convert("L").load()
            w, h = im.size
            sample = range(0, w, 12)
            count = len(list(sample))

            def row_mean(y):
                return sum(px[x, y] for x in sample) / count

            # The ground below the document is the body colour, not white, so "darker than
            # white" finds every row. Read the ground from the last row instead and look for
            # the first row that differs from it.
            ground = row_mean(h - 1)
            bottom = 0
            for y in range(h - 1, 0, -1):
                if abs(row_mean(y) - ground) > 4:
                    bottom = y
                    break
            if bottom >= h - 2:
                sys.exit("probe window too short: raise --window-size and re-run")
            height = bottom + 40
            print(f"  measured content bottom {bottom}px (ground {ground:.0f})")
    except Exception as e:  # pragma: no cover - measurement is a nicety, not a requirement
        print(f"  height probe failed ({e}); falling back to {height}px")
    finally:
        probe.unlink(missing_ok=True)

    printable = DOCS / "_portal-print.html"
    body = html_path.read_text()
    body = body.replace(
        "</style>",
        f"  @page {{ size: {WIDTH}px {height}px; margin: 0 }}\n</style>",
        1,
    )
    printable.write_text(body)
    # Media queries in the print pass follow the browser window, not the @page box. Without an
    # explicit width the narrow-screen rules fire and the two-column blocks stack.
    subprocess.run(
        [CHROME, "--headless", "--disable-gpu", "--no-pdf-header-footer",
         f"--window-size={WIDTH},1200", f"--print-to-pdf={pdf_path}", f"file://{printable}"],
        capture_output=True, check=False,
    )
    printable.unlink(missing_ok=True)


def main():
    html = build()
    OUT_HTML.write_text(html)
    print(f"HTML  {OUT_HTML.name}  {len(html):,} bytes")
    # The SVG namespace declarations are not fetched; the site hostnames are shown as text, not
    # loaded. Anything else external would be.
    external = [u for u in re.findall(r'https?://[^"\')\s]+', html)
                if "www.w3.org" not in u and "salesforce-sites.com" not in u]
    print(f"  external refs: {len(external)} (must be 0)")
    for u in external[:5]:
        print(f"    {u}")
    render_pdf(OUT_HTML, OUT_PDF)
    if OUT_PDF.exists():
        print(f"PDF   {OUT_PDF.name}  {OUT_PDF.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
