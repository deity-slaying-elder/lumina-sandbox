#!/usr/bin/env python3
"""One page proving the internal-recipient behaviour in the sandbox. Self-contained, Propela
branded, everything base64 embedded so it survives being dropped into Teams."""
import base64, pathlib, subprocess, re

DOCS = pathlib.Path(__file__).resolve().parent
SHOTS = DOCS / "shots-lmna-581"
BRAND = pathlib.Path.home() / ".claude" / "brand"
OUT = DOCS / "lmna-581-internal-recipient-proof-2026-09-22.html"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W = 1080
SLATE, NAVY, YELLOW, BLUE, INK = "#24323f", "#0C263B", "#f5fd7e", "#b9d8f5", "#1a1a1a"


def b64(p):
    return "data:image/png;base64," + base64.b64encode(pathlib.Path(p).read_bytes()).decode()


def shot(n):
    p = SHOTS / n
    if not p.exists():
        raise SystemExit(f"missing {p}")
    return b64(p)


def logo():
    return b64(BRAND / "logos" / "main" / "propela-main-yellow-white-900.png")


def shell(title, img, cap):
    return f"""<figure>
  <div class="mac"><div class="bar"><span class="d r"></span><span class="d y"></span><span class="d g"></span>
    <span class="t">{title}</span></div><img src="{img}" alt=""></div>
  <figcaption>{cap}</figcaption></figure>"""


LOG = [
    ("james@propela.tech", "Code sent", "Code 1 of 10", "21:05"),
    ("chayim@propela.tech", "Code sent", "Code 1 of 10", "21:05"),
    ("chayim@propela.tech", "Wrong code", "Attempt 1 of 5", "21:06"),
    ("chayim@propela.tech", "Opened", "Open 1 of 10", "21:06"),
    ("chayim@propela.tech", "PDF fetched", "", "21:06"),
]


def rows():
    out = ""
    for who, ev, detail, when in LOG:
        cls = ' class="hit"' if ev == "Wrong code" else ""
        out += (f"<tr{cls}><td class='m'>{who}</td><td><b>{ev}</b></td><td>{detail}</td>"
                f"<td class='m'>213.194.158.31</td><td class='m'>{when}</td></tr>")
    return out


HTML = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>LMNA-581 internal recipient proof</title><style>
*{{box-sizing:border-box}}
body{{margin:0;background:#f4f6f8;color:{INK};font:14px/1.55 'DM Sans',-apple-system,Helvetica,Arial,sans-serif}}
.page{{width:{W}px;margin:0 auto;background:#f4f6f8}}
h1,h2{{font-family:'Antonia Variable',Georgia,serif;font-weight:400}}
header{{background:{SLATE};color:#fff;padding:26px 34px 30px;border-bottom:4px solid {YELLOW}}}
.htop{{display:flex;justify-content:space-between;align-items:flex-start;gap:20px}}
header img.logo{{height:32px}}
.meta{{font:10px/1.7 'SF Mono',Menlo,monospace;letter-spacing:.09em;text-transform:uppercase;color:{BLUE};text-align:right}}
header h1{{margin:18px 0 8px;font-size:27px;line-height:1.15}}
header p{{margin:0;color:#cfe0ee;font-size:14.5px;max-width:78ch}}
.bluf{{background:{NAVY};color:#fff;padding:18px 34px}}
.bluf b{{color:{YELLOW}}}
main{{padding:24px 34px 34px}}
h2{{font-size:18px;margin:26px 0 2px;color:{SLATE};display:flex;align-items:center;gap:10px}}
h2:before{{content:'';width:5px;height:19px;background:{YELLOW};border-radius:3px}}
p.lede{{margin:6px 0 0;color:#4d5a66;max-width:84ch}}
.grid{{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-top:12px}}
figure{{margin:12px 0 0}}
.mac{{border-radius:7px;overflow:hidden;background:#fff;border:1px solid #c9d0d8}}
.bar{{display:flex;align-items:center;gap:6px;padding:7px 11px;background:linear-gradient(180deg,#f6f6f7,#e8e9ec);border-bottom:1px solid #d8dade}}
.d{{width:10px;height:10px;border-radius:50%;display:inline-block}}
.d.r{{background:#ff5f57}}.d.y{{background:#febc2e}}.d.g{{background:#28c840}}
.t{{margin-left:8px;font:11px 'SF Mono',Menlo,monospace;color:#5f6672}}
.mac img{{display:block;width:100%;height:auto}}
figcaption{{font-size:12.5px;color:#5b6b7a;margin-top:7px;line-height:1.5}}
table{{width:100%;border-collapse:separate;border-spacing:0;margin-top:12px;background:#fff;border:1px solid #dde2e7;border-radius:5px;overflow:hidden;font-size:12.5px}}
th{{background:{SLATE};color:#fff;text-align:left;padding:8px 10px;font-size:10px;letter-spacing:.06em;text-transform:uppercase}}
td{{padding:8px 10px;border-top:1px solid #eceef1}}
tr.hit td{{background:#fdf3f2}}
.m{{font-family:'SF Mono',Menlo,monospace;font-size:11.5px}}
.note{{margin:12px 0 0;font-size:12.5px;padding:10px 13px;border-radius:4px;background:#eef4fb;color:{NAVY};border:1px solid #cddff0;border-left:3px solid #7ea9d0}}
footer{{background:{SLATE};color:{BLUE};padding:18px 34px;border-top:4px solid {YELLOW};font:10px/1.8 'SF Mono',Menlo,monospace;margin-top:28px}}
footer b{{color:{YELLOW}}}
@page{{size:{W}px __H__px;margin:0}}
@media print{{*{{box-shadow:none!important}}footer{{margin-bottom:0}}}}
</style></head><body><div class="page">
<header><div class="htop"><img class="logo" src="{logo()}" alt="Propela">
<div class="meta">LMNA-581 &middot; Lumina Care<br>Sandbox proof<br>22 September 2026</div></div>
<h1>Each person gets their own link and their own code</h1>
<p>The option Lumina chose. Nobody is Cc'd, so one person's code can never open another
person's copy of the report. Captured from the lumDev sandbox today.</p></header>

<div class="bluf"><b>The result:</b> two people, one report, two separate emails. Chayim's code
opened his copy. The same code was refused on James's copy, and the refusal is on the record
with its IP address and time.</div>

<main>
<h2>One report, two links, two different mailboxes</h2>
<p class="lede">Both links point at the same report for the same facility and day. Each one names
the only mailbox that can open it, so the page tells you up front where the code will go.</p>
<div class="grid">
{shell("Link issued to James", shot("p1_james_link.png"), "Says the code goes to j***@propela.tech.")}
{shell("Link issued to Chayim", shot("p2_chayim_link.png"), "Same report, but the code goes to c***@propela.tech.")}
</div>

<h2>Asking for a code sends it to that mailbox only</h2>
<p class="lede">One click on each link. Two real emails went out, one to each address.</p>
<div class="grid">
{shell("James's link", shot("p3_james_code_sent.png"), "Code sent to James, good for 10 minutes.")}
{shell("Chayim's link", shot("p4_chayim_code_sent.png"), "Code sent to Chayim, a different code.")}
</div>

<h2>The part that matters: a code only works on its own link</h2>
<p class="lede">James's code was typed into Chayim's link. It was refused and counted as a failed
attempt. Five wrong attempts lock the link for good.</p>
{shell("James's code entered on Chayim's link", shot("p5_wrong_code_rejected.png"),
  "Refused, and the page says how many attempts remain.")}
{shell("Chayim's own code on Chayim's link", shot("p6_report_open.png"),
  "His own code opens the report. It stays open for 10 minutes, then needs a new code.")}

<h2>Every step is on the record</h2>
<p class="lede">Written by the site itself, not by us. Lumina staff can read this on the link
record at any time.</p>
<table><tr><th>Link issued to</th><th>Event</th><th>Detail</th><th>IP address</th><th>Time</th></tr>
{rows()}</table>
<p class="note">Both codes were genuinely emailed. The test inboxes are not ours to read, so for
the refusal step each link's code was set to a known value first. Nothing else in the flow
changed, and the stored value is the same scrambled form a real code produces.</p>
</main>

<footer>Propela Tech &middot; LMNA-581 &middot; Internal recipient proof<br>
Captured from <b>lumDev</b> (partial sandbox) on 22 September 2026 in a browser with no Salesforce
login. Patient data in the report is fabricated. Production is not affected.</footer>
</div></body></html>"""

probe = DOCS / "_p.html"
probe.write_text(HTML.replace("__H__", "14000"))
subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-sandbox", "--no-pdf-header-footer",
                "--virtual-time-budget=6000", f"--print-to-pdf={DOCS/'_p.pdf'}", f"file://{probe}"],
               capture_output=True, timeout=240)
h = 14000
if (DOCS / "_p.pdf").exists():
    subprocess.run(["pdftoppm", "-png", "-r", "96", "-f", "1", "-l", "1", str(DOCS / "_p.pdf"),
                    str(DOCS / "_p")], capture_output=True)
    pngs = sorted(DOCS.glob("_p-*.png"))
    if pngs:
        from PIL import Image
        im = Image.open(pngs[0]).convert("RGB"); w, hh = im.size; px = im.load()
        for y in range(hh - 1, -1, -1):
            if any(sum(px[x, y]) < 330 for x in range(0, w, 3)):
                h = y + 26; break
        for p in pngs: p.unlink()
OUT.write_text(HTML.replace("__H__", str(h)))
subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-sandbox", "--no-pdf-header-footer",
                "--virtual-time-budget=6000",
                f"--print-to-pdf={OUT.with_suffix('.pdf')}", f"file://{OUT}"],
               capture_output=True, timeout=240)
for f in (probe, DOCS / "_p.pdf"):
    if f.exists(): f.unlink()
body = OUT.read_text()
print(f"HTML {OUT.name} {len(body):,} bytes | images {body.count('data:image')} | "
      f"external refs {len(re.findall(r'src=.(?!data:)', body))} | em dashes {body.count(chr(8212))}")
info = subprocess.run(["pdfinfo", str(OUT.with_suffix('.pdf'))], capture_output=True, text=True).stdout
print("PDF pages:", (re.search(r'Pages:\s+(\d+)', info) or ['','?'])[1])
