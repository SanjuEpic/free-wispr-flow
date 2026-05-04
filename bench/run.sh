#!/usr/bin/env bash
# bench/run.sh  —  4-model transcription speed comparison
#
# Models:
#   Python sidecar (baseline):  Whisper tiny  ·  Parakeet MLX
#   FluidAudio / ANE (new):     Parakeet v2   ·  Parakeet v3  ← default
#
# Usage:
#   ./bench/run.sh                    # table output
#   ./bench/run.sh --markdown         # GitHub-flavoured markdown (paste into PR)
#   ./bench/run.sh --cold             # wipe FluidAudio model cache first
#   ./bench/run.sh --fluid-only       # skip Python sidecar benchmarks
#   ./bench/run.sh path/to/clip.aiff  # benchmark a specific file

set -euo pipefail

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$BENCH_DIR/.." && pwd)"
AUDIO_DIR="$BENCH_DIR/audio"
SIDECAR_DIR="$REPO_DIR/stt-server-py"

MARKDOWN=false
COLD=false
FLUID_ONLY=false
CUSTOM_FILES=()

for arg in "$@"; do
    case "$arg" in
        --markdown)   MARKDOWN=true ;;
        --cold)       COLD=true ;;
        --fluid-only) FLUID_ONLY=true ;;
        -*)           echo "unknown flag: $arg"; exit 1 ;;
        *)            CUSTOM_FILES+=("$arg") ;;
    esac
done

# ── Generate test clips ────────────────────────────────────────────────────────

mkdir -p "$AUDIO_DIR"

generate() {
    local name="$1" text="$2"
    local path="$AUDIO_DIR/$name.aiff"
    [ -f "$path" ] && return
    echo "  generating $name.aiff…"
    say -r 180 -o "$path" "$text"
}

SHORT_TEXT="Pack my box with five dozen liquor jugs. \
The quick brown fox jumps over the lazy dog. \
How vexingly quick daft zebras jump."

MEDIUM_TEXT="Automatic speech recognition has improved dramatically in recent years, \
driven by deep learning and large-scale training data. \
Modern systems can transcribe natural conversational speech with high accuracy, \
even in the presence of background noise and multiple speakers. \
Apple Silicon's Neural Engine provides dedicated hardware acceleration \
for on-device machine learning workloads, enabling real-time transcription \
without sending audio to external servers. \
This gives users both low latency and strong privacy guarantees, \
which are especially important for professional and sensitive workflows."

LONG_TEXT="The history of automatic speech recognition spans more than seven decades. \
Early systems in the nineteen fifties could recognise only isolated digits spoken by a single speaker. \
By the nineteen eighties, hidden Markov models had become the dominant approach, \
enabling continuous speech recognition for the first time. \
The nineteen nineties saw the rise of commercial products, \
though accuracy remained limited and speaker adaptation was often required. \
The deep learning revolution of the twenty tens transformed the field. \
Recurrent neural networks, then convolutional architectures, and finally transformer-based models \
pushed word error rates to new lows on standard benchmarks. \
Whisper, released by OpenAI in twenty twenty two, demonstrated that a single model \
trained on diverse multilingual data could generalise robustly across accents, \
domains, and noise conditions. \
Meanwhile, Apple has invested heavily in on-device inference through its Neural Engine, \
a dedicated matrix-multiply accelerator present in every Apple Silicon chip since the A11 Bionic. \
The Neural Engine can execute trillions of operations per second while consuming a fraction \
of the power required by GPU-based inference. \
Parakeet, developed by NVIDIA and adapted for CoreML by FluidInference, \
takes advantage of this hardware to deliver transcription that runs many times faster than real time \
on MacBook Air and MacBook Pro."

if [ ${#CUSTOM_FILES[@]} -eq 0 ]; then
    echo "── Generating test clips ──────────────────────────────────────────────────"
    generate "short"  "$SHORT_TEXT"
    generate "medium" "$MEDIUM_TEXT"
    generate "long"   "$LONG_TEXT"
    echo ""
    CLIPS=("$AUDIO_DIR/short.aiff" "$AUDIO_DIR/medium.aiff" "$AUDIO_DIR/long.aiff")
else
    CLIPS=("${CUSTOM_FILES[@]}")
fi

CLIP_NAMES=()
for c in "${CLIPS[@]}"; do CLIP_NAMES+=("$(basename "$c")"); done

# ── Cold start ─────────────────────────────────────────────────────────────────

if [ "$COLD" = true ]; then
    CACHE="$HOME/Library/Caches/FluidAudio"
    [ -d "$CACHE" ] && { echo "── Wiping model cache ─────────────────────────────────────────────────────"; rm -rf "$CACHE"; echo ""; }
fi

# ── Python sidecar benchmarks ──────────────────────────────────────────────────
# TSV output:  model \t clip \t duration \t infer \t rtfx

PYTHON_TSV=""

if [ "$FLUID_ONLY" = false ] && [ -d "$SIDECAR_DIR" ]; then
    echo "── Python sidecar benchmarks ─────────────────────────────────────────────"

    PYCODE=$(cat << 'PYEOF'
import sys, time, os, subprocess

def duration(path):
    r = subprocess.run(["afinfo", path], capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if "estimated duration" in line.lower():
            return float(line.split()[-2])
    return 0.0

mode = sys.argv[1]
clips = sys.argv[2:]

if mode == "whisper":
    import whisper
    m = whisper.load_model("tiny")
    label = "Whisper tiny (sidecar)"
    m.transcribe(clips[0])   # warmup
    def infer(p): t=time.perf_counter(); m.transcribe(p); return time.perf_counter()-t
else:
    from parakeet_mlx import from_pretrained
    m = from_pretrained("mlx-community/parakeet-tdt-0.6b-v3")
    label = "Parakeet MLX (sidecar)"
    m.transcribe(clips[0])   # warmup
    def infer(p): t=time.perf_counter(); m.transcribe(p); return time.perf_counter()-t

for p in clips:
    d = duration(p); elapsed = infer(p); rtfx = d/elapsed if elapsed else 0
    print(f"{label}\t{os.path.basename(p)}\t{d:.1f}\t{elapsed:.2f}\t{rtfx:.1f}", flush=True)
PYEOF
)

    cd "$SIDECAR_DIR"
    WHISPER_TSV=$(uv run python - "whisper" "${CLIPS[@]}" 2>/dev/null <<< "$PYCODE")
    echo "  Whisper tiny  — done"
    PARA_TSV=$(uv run python - "parakeet" "${CLIPS[@]}" 2>/dev/null <<< "$PYCODE")
    echo "  Parakeet MLX  — done"
    cd "$REPO_DIR"
    PYTHON_TSV="${WHISPER_TSV}"$'\n'"${PARA_TSV}"
    echo ""
fi

# ── FluidAudio benchmarks ──────────────────────────────────────────────────────

echo "── FluidAudio benchmarks ─────────────────────────────────────────────────"
cd "$BENCH_DIR"
swift build -c release 2>&1 | grep -v "^Build complete\|^warning:\|^note:"

V2_TSV=$(./.build/release/bench --v2 --tsv "${CLIPS[@]}" 2>/dev/null | sed 's/.*\(Parakeet\)/\1/' | grep '^Parakeet')
echo "  Parakeet v2   — done"
V3_TSV=$(./.build/release/bench --v3 --tsv "${CLIPS[@]}" 2>/dev/null | sed 's/.*\(Parakeet\)/\1/' | grep '^Parakeet')
echo "  Parakeet v3   — done"
echo ""

# ── Render table via Python (bash 3 has no associative arrays) ────────────────

ALL_TSV=""
[ -n "$PYTHON_TSV" ] && ALL_TSV="${PYTHON_TSV}"$'\n'
ALL_TSV="${ALL_TSV}${V2_TSV}"$'\n'"${V3_TSV}"

python3 - "$MARKDOWN" <<PYEOF
import sys

markdown = sys.argv[1] == "true"
tsv = """$ALL_TSV"""

rows = [line.split('\t') for line in tsv.strip().splitlines() if line.strip()]
# rows: [model, clip, dur, infer, rtfx]

models, clips = [], []
data = {}
for model, clip, dur, infer, rtfx in rows:
    if model not in models: models.append(model)
    if clip  not in clips:  clips.append(clip)
    data[(model, clip)] = (rtfx, infer)

if markdown:
    print("### uttr — transcription speed benchmark")
    print()
    print("> RTFx = audio seconds ÷ inference seconds. Higher is faster.  ")
    print("> Python sidecar models are the pre-M1 baseline. Warm models (cached).")
    print()
    header = "| Model | " + " | ".join(clips) + " |"
    sep    = "|-------|" + "--------|" * len(clips)
    print(header)
    print(sep)
    for model in models:
        cells = []
        for clip in clips:
            rtfx, infer = data.get((model, clip), ("—", "—"))
            cells.append(f"{rtfx}× / {infer}s")
        print(f"| \`{model}\` | " + " | ".join(cells) + " |")
    print()
    print("![benchmark](bench/benchmark.png)")
else:
    col = 15
    fmt = f"  {{:<32}}" + f"  {{:>{col}}}" * len(clips)
    print(fmt.format("Model", *clips))
    print(fmt.format("─"*32, *["─"*col]*len(clips)))
    for model in models:
        cells = []
        for clip in clips:
            rtfx, infer = data.get((model, clip), ("—", "—"))
            cells.append(f"{rtfx}× / {infer}s")
        print(fmt.format(model, *cells))
PYEOF
