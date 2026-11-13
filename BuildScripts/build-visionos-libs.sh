#!/bin/bash
#
# Builds the third-party static libraries that the Vision Pro target links
# against, for visionOS devices and for the visionOS simulator:
#
#   libs/opus/lib/visionOS/libopus.a        libs/opus/lib/visionOS-Sim/libopus.a
#   libs/SDL2/lib/visionOS/libSDL2.a        libs/SDL2/lib/visionOS-Sim/libSDL2.a
#
# The archives that used to live at those paths were iOS builds. Only the old
# "classic" linker accepted them in a visionOS app, and Xcode 27 removed it.
#
# The app uses SDL2 for audio output only, so every other SDL subsystem is
# switched off. The headers in libs/SDL2/include and libs/opus/include are
# left alone: the handful of functions the app calls have not changed.
#
# Requirements: macOS with Xcode (visionOS SDK installed) and CMake 3.28+.
# Usage:  BuildScripts/build-visionos-libs.sh
#
set -euo pipefail

OPUS_VERSION="${OPUS_VERSION:-1.4}"
SDL_VERSION="${SDL_VERSION:-2.32.10}"
XROS_MIN="${XROS_MIN:-26.0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK_DIR:-$ROOT/BuildScripts/build-visionos}"
OUT="${OUT_DIR:-$ROOT/libs}"

mkdir -p "$WORK"

echo "== Toolchain"
xcodebuild -version
cmake --version | head -1

fetch() {
    local url="$1" out="$2"
    if [ ! -f "$out" ]; then
        echo "Downloading $url"
        curl -fL --retry 3 -o "$out" "$url"
    fi
    shasum -a 256 "$out"
}

echo "== Sources"
fetch "https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz" "$WORK/opus-${OPUS_VERSION}.tar.gz"
fetch "https://github.com/libsdl-org/SDL/releases/download/release-${SDL_VERSION}/SDL2-${SDL_VERSION}.tar.gz" "$WORK/SDL2-${SDL_VERSION}.tar.gz"

rm -rf "$WORK/opus-src" "$WORK/sdl2-src"
mkdir -p "$WORK/opus-src" "$WORK/sdl2-src"
tar xzf "$WORK/opus-${OPUS_VERSION}.tar.gz" --strip-components=1 -C "$WORK/opus-src"
tar xzf "$WORK/SDL2-${SDL_VERSION}.tar.gz" --strip-components=1 -C "$WORK/sdl2-src"

# build <name> <source dir> <sdk> <archive name> <destination dir> [cmake args...]
build() {
    local name="$1" src="$2" sdk="$3" archive="$4" dest="$5"
    shift 5
    local bdir="$WORK/build-$name-$sdk"

    echo "== Building $name for $sdk"
    rm -rf "$bdir"
    cmake -S "$src" -B "$bdir" \
        -DCMAKE_SYSTEM_NAME=visionOS \
        -DCMAKE_OSX_SYSROOT="$sdk" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$XROS_MIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        "$@" > "$bdir.configure.log" 2>&1 || { tail -60 "$bdir.configure.log"; exit 1; }
    cmake --build "$bdir" --parallel > "$bdir.build.log" 2>&1 || { tail -80 "$bdir.build.log"; exit 1; }

    local built
    built="$(find "$bdir" -name "$archive" -type f | head -1)"
    if [ -z "$built" ]; then
        echo "error: $archive was not produced for $sdk" >&2
        exit 1
    fi
    mkdir -p "$dest"
    cp "$built" "$dest/$archive"

    # Show which platform the objects were built for (11 = visionOS, 12 = simulator).
    echo "-- $dest/$archive"
    lipo -info "$dest/$archive"
    otool -l "$dest/$archive" | grep -A4 LC_BUILD_VERSION | grep -E "platform|minos|sdk" | sort | uniq -c
}

OPUS_ARGS=(
    -DOPUS_BUILD_SHARED_LIBRARY=OFF
    -DOPUS_BUILD_PROGRAMS=OFF
    -DOPUS_BUILD_TESTING=OFF
    -DOPUS_INSTALL_PKG_CONFIG_MODULE=OFF
    -DOPUS_INSTALL_CMAKE_CONFIG_MODULE=OFF
)

# Audio output is the only SDL feature the app uses.
SDL_ARGS=(
    -DSDL_SHARED=OFF
    -DSDL_STATIC=ON
    -DSDL_TEST=OFF
    -DSDL_VIDEO=OFF
    -DSDL_RENDER=OFF
    -DSDL_JOYSTICK=OFF
    -DSDL_HAPTIC=OFF
    -DSDL_HIDAPI=OFF
    -DSDL_SENSOR=OFF
    -DSDL_POWER=OFF
    -DSDL_FILESYSTEM=OFF
    -DSDL_LOCALE=OFF
    -DSDL_MISC=OFF
)

build opus "$WORK/opus-src" xros        libopus.a "$OUT/opus/lib/visionOS"     "${OPUS_ARGS[@]}"
build opus "$WORK/opus-src" xrsimulator libopus.a "$OUT/opus/lib/visionOS-Sim" "${OPUS_ARGS[@]}"
build sdl2 "$WORK/sdl2-src" xros        libSDL2.a "$OUT/SDL2/lib/visionOS"     "${SDL_ARGS[@]}"
build sdl2 "$WORK/sdl2-src" xrsimulator libSDL2.a "$OUT/SDL2/lib/visionOS-Sim" "${SDL_ARGS[@]}"

echo "== Done"
ls -la "$OUT/opus/lib/visionOS" "$OUT/opus/lib/visionOS-Sim" "$OUT/SDL2/lib/visionOS" "$OUT/SDL2/lib/visionOS-Sim"
