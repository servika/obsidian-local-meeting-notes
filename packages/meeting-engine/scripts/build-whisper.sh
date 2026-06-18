#!/usr/bin/env bash
# Build a self-contained, native whisper.cpp `whisper-cli` to bundle in the app.
#
# We build statically (-DBUILD_SHARED_LIBS=OFF) so the result is a single binary
# with no libwhisper/libggml dylib dependencies - only system frameworks
# (Metal, Accelerate, ...) that are always present. The Metal shader is embedded.
# The binary is cached at vendor/whisper-cli so app builds don't recompile it.
#
# Usage: scripts/build-whisper.sh [--force]
set -euo pipefail

# Pinned whisper.cpp version (bump deliberately).
WHISPER_REF="v1.8.6"
REPO="https://github.com/ggml-org/whisper.cpp.git"

cd "$(dirname "$0")/.."          # packages/meeting-engine
ROOT="$(pwd)"
SRC="$ROOT/.build/whisper-src"
BUILD="$ROOT/.build/whisper-build"
OUT="$ROOT/vendor/whisper-cli"

if [[ "${1:-}" != "--force" && -x "$OUT" ]]; then
  echo "whisper-cli already built: $OUT ($(file -b "$OUT" | cut -d, -f1,2))"
  echo "  (use --force to rebuild)"
  exit 0
fi

# Fetch source at the pinned ref (shallow, cached).
if [[ ! -d "$SRC/.git" ]]; then
  echo "Cloning whisper.cpp ${WHISPER_REF}..."
  rm -rf "$SRC"
  git clone --depth 1 --branch "$WHISPER_REF" "$REPO" "$SRC"
else
  echo "Reusing whisper.cpp source at $SRC"
  git -C "$SRC" fetch --depth 1 origin tag "$WHISPER_REF" >/dev/null 2>&1 || true
  git -C "$SRC" checkout -q "$WHISPER_REF" 2>/dev/null || true
fi

# Configure + build only the whisper-cli target, statically, native arch.
ARCH="$(uname -m)"
echo "Building whisper-cli (static, ${ARCH})..."
cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_NATIVE=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
  >/dev/null
cmake --build "$BUILD" --config Release --target whisper-cli -j "$(sysctl -n hw.ncpu)" >/dev/null

# Locate the built binary (cmake puts it in build/bin).
BIN="$(find "$BUILD" -name whisper-cli -type f -perm -111 | head -1)"
if [[ -z "$BIN" ]]; then echo "ERROR: whisper-cli not produced"; exit 1; fi

mkdir -p "$(dirname "$OUT")"
cp "$BIN" "$OUT"
chmod +x "$OUT"

echo "built: $OUT"
file -b "$OUT" | sed 's/^/  /'
echo "  dylib deps (should be system-only):"
otool -L "$OUT" | tail -n +2 | grep -v '/usr/lib/\|/System/' | sed 's/^/  ⚠️  /' || echo "    (none - fully self-contained)"