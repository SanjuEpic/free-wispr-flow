# parakeet.cpp vs faster-whisper — benchmark results (2026-06-23)

Hardware: RTX 3050 Laptop 4 GB, Windows. parakeet.cpp v0.3.2 (prebuilt CLI, `bench`
mode, model loaded once). faster-whisper small.en, float16, beam=3 (shipped default).
WER is word-level Levenshtein on **punctuation-stripped, lowercased** text (see
`benchmark_providers.py::normalize`) — applied identically to all providers.

## Dataset A — our 3 dictation samples (real-world: numbers, dates, code terms, names)

| model (GPU)              | avg lat | avg WER | short 7s | med 36s | long 62s |
|--------------------------|--------:|--------:|---------:|--------:|---------:|
| faster-whisper small.en  |  1.37s  |   13%   |   24%    |   5%    |   11%    |
| parakeet tdt-v2-q8       |  0.38s  |   18%   |   35%    |   5%    |   13%    |
| parakeet tdt-v2-f16      |  0.43s  |   18%   |   35%    |   5%    |   13%    |
| parakeet rnnt-0.6b-q8    |  0.41s  |   23%   |   29%    |  16%    |   22%    |

Per-clip latency (model stage): short 0.10s / med 0.32s / long 0.72s (tdt-q8) vs
0.33s / 0.75s / 3.02s (faster-whisper).

## Dataset B — LibriSpeech test-clean, 50 utterances (clean read speech, golden)

| model (GPU)              | avg lat | avg WER |
|--------------------------|--------:|--------:|
| faster-whisper small.en  |  0.38s  |   4%    |
| parakeet tdt-v2-q8       |  0.08s  |   2%    |
| parakeet tdt-v2-f16      |  0.09s  |   2%    |
| parakeet rnnt-0.6b-q8    |  0.09s  |   2%    |

## Findings

1. **tdt-v2 is the only viable parakeet candidate.** rnnt-0.6b matches its WER on clean
   speech but emits lowercase, unpunctuated, no-ITN text (`"three thirty p m"`) — unusable
   for a paste-at-cursor dictation app. tdt-v2 outputs `"3:30 p.m."`, proper casing,
   punctuation. **q8_0 over f16:** identical WER, slightly faster, ~half the VRAM (~0.9 GB
   vs ~1.4 GB) — matters on the 4 GB card.
2. **Latency: parakeet wins clearly on GPU** — ~4× faster on short clips, ~4× on long.
   For *short* dictation the absolute gain is small (0.08s vs 0.33s model stage); the big
   win is long-form audio.
3. **Accuracy is content-dependent, not absolute.** Clean prose → parakeet better
   (2% vs 4%). Real-world dictation with numbers/dates/names/code → faster-whisper
   better (13% vs 18%), the gap entirely on those hard tokens (whisper does ITN, parakeet
   spells out / mis-formats: `"OAuth 2.0"`→`"two point two"` on rnnt; tdt gets OAuth right
   but `"3:30 PM"`→`"three: thirty"`).
4. **4 GB VRAM is fine** — all variants loaded and ran on CUDA0, no OOM, no silent CPU
   fallback (verified: GPU RTFx 80–100× vs CPU ~6×).

## Live-mic findings (real dictation through the app, not the file benchmark)

The tables above use pre-recorded clips. Running both providers live through the actual
hotkey → speak → paste flow (`python -m uttr_win.app -model 1|4 -device cpu|cuda`)
surfaced behaviour the WER numbers don't capture:

1. **Quiet / whispered speech → parakeet wins.** faster-whisper has a voice-activity
   gate and frequently drops very soft or whispered input as "no speech". parakeet has
   no VAD front-end, so it transcribes low-energy speech that whisper discards.
2. **Filler / non-speech sounds → faster-whisper wins.** The flip side of (1): parakeet
   transcribes *everything*, so it emits stray tokens for `"uh"`, `"da"`, breaths, and
   background noise. whisper's gate + decoding drop these, giving cleaner, more directly
   usable output.
3. **Latency → parakeet wins, clearly.** Sub-second and effectively instantaneous on both
   short and long utterances; whisper has a noticeable post-speech pause. Confirms the
   file benchmark in felt terms.
4. **Output quality → slight edge to faster-whisper.** Cleaner punctuation/casing and
   better on numbers/dates/names, consistent with Dataset A.

**Verdict from hands-on use:** for everyday real-world dictation parakeet feels better
overall — latency and tolerance of soft speech matter more moment-to-moment than the
small accuracy edge. Prefer faster-whisper when cleanest text matters (numbers/names-heavy
writing) or in noisy rooms where parakeet's lack of a noise gate hurts.

### CPU-only live findings (`-device cpu`, both providers)

Latencies here are wall-clock by stopwatch on cold start, so treat them as rough, not
lab-grade — but the gap was consistent across many utterances:

| provider (CPU) | felt latency (stopwatch) |
|----------------|--------------------------|
| parakeet tdt-v2-q8 | ~2–3 s (incl. cold start) |
| faster-whisper small.en | ~5–8 s |

- **Parakeet on CPU ≈ faster-whisper on GPU, latency-wise.** This is the headline: a
  GPU-less user gets near-GPU responsiveness from parakeet. Parakeet stayed clearly
  faster than whisper on CPU across both short and long utterances.
- **Background music / noise: parakeet held up far better than expected.** With music
  playing and through earphones, parakeet still produced good transcriptions — it did
  *not* fall apart the way the "no noise gate" theory predicted. faster-whisper also
  handled background music fine. (Earphone capture that previously gave whisper trouble
  worked cleanly here.)
- **Technical terms: parakeet captured them well** — `CPU`, `GPU`, `VRAM`, `RAM`,
  `Python`, `OAuth 2.0`, `Python 3.6`, `version 3.7.5` all came through. This is on the
  spoken text; the earlier Dataset-A penalty was mostly numeric *formatting*, not these
  tokens.
- **Both still miss Indian proper nouns** (`Swami`, `Sachin`, `Priya`) and even mangle
  the word "Parakeet" itself (`Barakeet`, `Farakeet`, `Barricade`) — expected for rare
  proper nouns in a small English model.
- **Stop words confirmed live:** parakeet transcribes `"uh"`, `"da"`, etc. back into the
  output; faster-whisper drops them. Same tradeoff as on GPU.
- **Time normalizer:** spoken times like `"3:30 p.m."` / `"12:30 AM"` are converted, but
  watch AM/PM casing — verify it always emits uppercase `PM`/`AM`.

Net: on CPU the speed gap *widens* in parakeet's favour (whisper-small is heavy on CPU),
while the quality tradeoff is unchanged. For a CPU-only setup parakeet is the stronger
daily driver; faster-whisper remains the pick when output cleanliness outweighs speed.

## Caveats
- Dataset A is n=3 (self-recorded); the short clip's 35% is one 17-word utterance where
  two errors dominate. Directional, not definitive.
- LibriSpeech is clean audiobook read speech — limited validity for noisy/accented input.

## Decision (2026-06-24): not adopting Parakeet — staying on faster-whisper

After the benchmarks above *and* extended live hands-on use, we evaluated shipping a
Parakeet provider (built it, bundled a universal CPU+GPU installer, tested it on the
RTX 3050) and decided **not to adopt it**. faster-whisper `small.en` remains the sole
engine. The reasoning, so future-us doesn't re-litigate it:

1. **~2× the GPU memory for no GPU speed win.** Live, Parakeet held ~1.3 GB VRAM vs
   faster-whisper's ~0.6 GB. On the GPU the two were effectively **on par** for both
   latency and perceived accuracy — so we'd be paying double the VRAM for nothing on the
   hardware most users run.
2. **Inconsistent number/ITN formatting.** The dealbreaker for a dictation app: Parakeet
   would render the same value as words one time and digits the next (e.g. "1.3" spoken
   came out as "one point three" or "1.3" unpredictably; "1.4" similarly). faster-whisper
   is reliably correct on numbers, dates, and times — exactly the tokens dictation users
   type most.
3. **Its real edges didn't apply to our target.** Parakeet genuinely wins on **CPU
   latency** (~2–3 s vs ~5–8 s) and **soft/whispered speech** (no VAD gate). But those
   help a CPU-only or soft-speech user — not the GPU, normal-volume case we're optimizing
   for — and they don't outweigh the formatting inconsistency or the **+1.4 GB installer**
   that bundling Parakeet's DLLs + GGUF would add.

**Net:** the cost (2× VRAM, larger installer, output you can't trust on numbers) outweighs
the benefit (latency/soft-speech edges we don't need on GPU). The provider code was
reverted; this benchmark and these notes are kept as the record of *why*. Revisit only if
a **CPU-only** or **soft-speech** use case becomes a real priority — that's where Parakeet
would actually earn its place.
- WER normalization strips punctuation but not ITN differences; `"3:30 PM"` (ref/whisper)
  vs `"three thirty"` (parakeet) is scored as errors. That penalty is *legitimate* for a
  dictation app (users want the written form) but is a representation gap, not pure ASR error.

## Reproduce
```
python benchmarks/prep_golden.py --n 50
python benchmarks/benchmark_providers.py --providers parakeet,fw --sizes small.en \
    --beam-sizes 3 --pk-device cuda --audio-dir benchmarks/golden
python benchmarks/benchmark_providers.py --providers parakeet,fw --sizes small.en \
    --beam-sizes 3 --pk-device both           # our 3 samples
```
