#!/usr/bin/env bash
# Install the experimental "Recognize speakers" dependencies: the sherpa-onnx
# offline speaker-diarization binary and its two ONNX models (a pyannote
# segmentation model + a speaker-embedding model).
#
# Models go to ~/models/sherpa (picked up at runtime with no app rebuild). The
# binary is resolved from Homebrew or the app bundle; this script installs it via
# Homebrew when available. Re-run is idempotent (skips files already present).
#
# After running, the "Recognize speakers" toggle in Settings -> Transcription
# becomes enabled.

set -euo pipefail

MODELS_DIR="${HOME}/models/sherpa"
mkdir -p "$MODELS_DIR"

# Pinned, stable model assets (rename on disk so the app can tell them apart by
# the "segmentation" substring in the filename).
SEG_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2"
SEG_OUT="${MODELS_DIR}/sherpa-onnx-pyannote-segmentation-3-0.onnx"
EMB_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_campplus_sv_zh-cn_16k-common.onnx"
EMB_OUT="${MODELS_DIR}/3dspeaker_speech_campplus_sv_zh-cn_16k-common.onnx"

fetch() { # url out
	if [ -f "$2" ]; then echo "  have $(basename "$2")"; return; fi
	echo "  downloading $(basename "$2")..."
	curl -fL --progress-bar "$1" -o "$2.part"
	mv "$2.part" "$2"
}

echo "Speaker-embedding model:"
fetch "$EMB_URL" "$EMB_OUT"

echo "Segmentation model:"
if [ -f "$SEG_OUT" ]; then
	echo "  have $(basename "$SEG_OUT")"
else
	echo "  downloading + extracting segmentation model..."
	tmp="$(mktemp -d)"
	curl -fL --progress-bar "$SEG_URL" -o "$tmp/seg.tar.bz2"
	tar xjf "$tmp/seg.tar.bz2" -C "$tmp"
	# The tarball contains a folder with model.onnx; grab the first .onnx.
	found="$(find "$tmp" -name '*.onnx' | head -n1)"
	[ -n "$found" ] || { echo "  ERROR: no .onnx inside segmentation archive"; exit 1; }
	mv "$found" "$SEG_OUT"
	rm -rf "$tmp"
fi

echo "Diarization binary:"
BIN="sherpa-onnx-offline-speaker-diarization"
if command -v "$BIN" >/dev/null 2>&1; then
	echo "  found on PATH: $(command -v "$BIN")"
elif command -v brew >/dev/null 2>&1; then
	echo "  installing sherpa-onnx via Homebrew..."
	brew install sherpa-onnx
else
	cat <<EOF
  NOT installed. Install the sherpa-onnx CLI tools, which provide
  '$BIN'. Options:
    - brew install sherpa-onnx   (install Homebrew first), or
    - download a prebuilt release from
      https://github.com/k2-fsa/sherpa-onnx/releases and put
      '$BIN' on your PATH (or in the app bundle's Resources).
EOF
fi

echo
echo "Done. Models in: $MODELS_DIR"
echo "Enable it in the app: Settings -> Transcription -> Recognize speakers."