"""LMNA-630 facility scheduling walkthrough: one wav per caption line.

Kokoro returns no word timings, so the script is split at caption boundaries and each
line rendered separately. Its measured length then drives the caption, and the sum per
scene drives that scene's beat -- exact sync, nothing guessed.

Local Kokoro on purpose: James, 2026-10-01, every preview and review take is local so
the Gemini free tier (about 10 a day) is spent only on the final.

Run: uv run narrate.py [voice]
"""
import json
import pathlib
import sys

import espeakng_loader
import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro
from phonemizer.backend import EspeakBackend
from phonemizer.backend.espeak.wrapper import EspeakWrapper

EspeakWrapper.set_library(espeakng_loader.get_library_path())
EspeakWrapper.set_data_path(espeakng_loader.get_data_path())
PHONEMIZER = EspeakBackend("en-us", preserve_punctuation=True, with_stress=True)

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent / "remotion" / "public" / "vo"
MODEL = pathlib.Path.home() / ".cache" / "kokoro" / "kokoro-v1.0.onnx"
VOICES = HERE / "voices-v1.0.bin"

VOICE = sys.argv[1] if len(sys.argv) > 1 else "af_heart"
LANG = "en-us"
LEAD_OUT = 0.22  # silence per line so sentences do not butt-join
RAMP = 0.012     # edge fades; without them the waveform starts mid-cycle and clicks


def polish(samples, rate):
    n = max(1, int(rate * RAMP))
    out = np.asarray(samples, dtype="float32").copy()
    out[:n] *= np.linspace(0.0, 1.0, n)
    out[-n:] *= np.linspace(1.0, 0.0, n)
    return np.concatenate([out, np.zeros(int(rate * LEAD_OUT), dtype="float32")])


# Scene -> lines. `caption` burns on screen; `say` is what is read, with the spellings
# that make the synth pronounce it right. Speed varies per line (1.06-1.30): the slow
# line is the one that lands.
#
# Spine follows the skill: hook, problem, what we built, how it works, in Salesforce,
# guardrails, what's next. One idea per line, because each line becomes a beat.
SCRIPT = [
    ("01-problem", [
        ("Twenty seven facilities are waiting to be onboarded.", None, 1.10),
        ("Fifteen of them have nothing booked.", None, 1.06),
        ("Until now that lived in a spreadsheet.", None, 1.14),
        ("Who is going, which programs, whether they are even licensed for it.", None, 1.18),
        ("All of it checked by hand.", None, 1.06),
    ]),
    ("02-built", [
        ("So we built one screen for it.", None, 1.10),
        ("A worklist of every facility still waiting.", None, 1.18),
        ("And the same thing as a calendar.", None, 1.18),
        ("An onboarding coordinator works from this and nothing else.", None, 1.14),
    ]),
    ("03-programs", [
        ("A visit used to carry one program.", None, 1.10),
        ("Now it carries as many as the visit really covers.", None, 1.22),
        ("Open a facility and the programs tick themselves.", None, 1.18),
        ("Read straight off the facility record.", None, 1.10),
        ("A program that facility does not run says so.", None, 1.18),
        ("Rather than sitting there blank.", None, 1.06),
    ]),
    ("04-providers", [
        ("Then the question that used to take a phone call.", None, 1.14),
        ("Who can actually go.", None, 1.06),
        ("This facility is in Ohio, and the visit covers two programs.", None, 1.22),
        ("Of three hundred and twenty three providers, two qualify.", None, 1.26),
        ("They hold a current Ohio licence.", None, 1.10),
        ("And they are approved for every program on the visit.", None, 1.22),
        ("Not one of them. All of them.", None, 1.06),
    ]),
    ("05-counts", [
        ("The numbers come from the facility itself.", None, 1.14),
        ("Census, seen, and consented.", None, 1.10),
        ("Counted live, every time the screen opens.", None, 1.18),
        ("So they are never stale.", None, 1.06),
    ]),
    ("06-guardrails", [
        ("Change any of this and the people on the visit hear about it.", None, 1.22),
        ("The facilitator, and every provider going.", None, 1.14),
        ("Move it, cancel it, or take someone off it.", None, 1.14),
        ("An expired licence never counts.", None, 1.10),
        ("And no patient information goes in the email.", None, 1.14),
    ]),
]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    kokoro = Kokoro(str(MODEL), str(VOICES))
    manifest = []
    for scene, lines in SCRIPT:
        out_lines = []
        for i, (caption, say, speed) in enumerate(lines):
            text = say or caption
            phonemes = PHONEMIZER.phonemize([text])[0]
            samples, rate = kokoro.create(
                phonemes, voice=VOICE, speed=speed, lang=LANG, is_phonemes=True
            )
            samples = polish(samples, rate)
            name = f"{scene}-{i:02d}.wav"
            sf.write(OUT / name, samples, rate)
            secs = round(len(samples) / rate, 3)
            out_lines.append({"id": f"{scene}-{i:02d}", "caption": caption, "secs": secs})
            print(f"  {name}  {secs:6.2f}s  {caption[:62]}")
        manifest.append({"scene": scene, "lines": out_lines})
    total = sum(l["secs"] for s in manifest for l in s["lines"])
    (HERE.parent / "remotion" / "src" / "script.json").write_text(
        json.dumps(manifest, indent=1)
    )
    print(f"\n{len(manifest)} scenes, narration {total:.1f}s, voice {VOICE}")


if __name__ == "__main__":
    main()
