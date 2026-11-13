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
# switched off. The headers in libs/SDL2/include (SDL 2.28.5) and
# libs/opus/include (Opus 1.4) are left alone: the declarations the app uses
# are the same in SDL 2.32.10.
#
# One behaviour does differ from the SDL 2.28.5 archive this replaces: for
# 7.1 audio, which the Vision app always requests, SDL now tells CoreAudio the
# channel order is L R C LFE BL BR SL SR. That is the order Moonlight sends;
# SDL 2.28.5 declared the last four as side and front-centre pairs.
#
# Requirements: macOS with Xcode (visionOS SDK installed) and CMake 3.28+.
# Usage:  BuildScripts/build-visionos-libs.sh
#
set -euo pipefail

OPUS_VERSION="${OPUS_VERSION:-1.4}"
SDL_VERSION="${SDL_VERSION:-2.32.10}"
XROS_MIN="${XROS_MIN:-26.0}"

# SHA-256 of the source tarballs. Set these too when overriding a version.
OPUS_SHA256="${OPUS_SHA256:-c9b32b4253be5ae63d1ff16eea06b94b5f0f2951b7a02aceef58e3a3ce49c51f}"
SDL_SHA256="${SDL_SHA256:-5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK_DIR:-$ROOT/BuildScripts/build-visionos}"
OUT="${OUT_DIR:-$ROOT/libs}"

mkdir -p "$WORK"

echo "== Toolchain"
xcodebuild -version
cmake --version | head -1

# fetch <url> <file> <expected sha256>
fetch() {
    local url="$1" out="$2" sha="$3"
    if [ ! -f "$out" ]; then
        echo "Downloading $url"
        curl -fL --retry 3 -o "$out.part" "$url"
        mv "$out.part" "$out"
    fi
    if ! echo "$sha  $out" | shasum -a 256 -c -; then
        rm -f "$out"
        echo "error: $out does not have the expected SHA-256 ($sha); it was deleted, run again" >&2
        exit 1
    fi
}

echo "== Sources"
fetch "https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz" "$WORK/opus-${OPUS_VERSION}.tar.gz" "$OPUS_SHA256"
fetch "https://github.com/libsdl-org/SDL/releases/download/release-${SDL_VERSION}/SDL2-${SDL_VERSION}.tar.gz" "$WORK/SDL2-${SDL_VERSION}.tar.gz" "$SDL_SHA256"

rm -rf "$WORK/opus-src" "$WORK/sdl2-src"
mkdir -p "$WORK/opus-src" "$WORK/sdl2-src"
tar xzf "$WORK/opus-${OPUS_VERSION}.tar.gz" --strip-components=1 -C "$WORK/opus-src"
tar xzf "$WORK/SDL2-${SDL_VERSION}.tar.gz" --strip-components=1 -C "$WORK/sdl2-src"

# SDL_IsTablet() in SDL.c calls SDL_IsIPad(), which is defined in the UIKit
# video driver. Video is switched off below, so without this the archive has an
# undefined symbol and a Debug build of the app (no dead-code stripping) fails
# to link.
cat >> "$WORK/sdl2-src/src/SDL.c" <<'EOF'

/* Added by build-visionos-libs.sh: the UIKit video driver that normally
 * defines this function is not part of this build. */
#if defined(__IPHONEOS__) && !defined(SDL_VIDEO_DRIVER_UIKIT)
SDL_bool SDL_IsIPad(void)
{
    return SDL_FALSE;
}
#endif
EOF

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
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
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
    # Opus only builds its NEON code when CMAKE_SYSTEM_PROCESSOR names an ARM
    # CPU, and a cross build leaves it empty. It must be "aarch64" (not
    # "arm64"): only that spelling switches on OPUS_PRESUME_NEON. Leave
    # OPUS_MAY_HAVE_NEON at its default (ON): the headers that route calls to
    # the NEON functions are only included when it is on. The configure log
    # then contains "ERRORRuntime cpu capability detection needed for
    # MAY_HAVE_NEON"; that line is a harmless message, not a failure.
    -DCMAKE_SYSTEM_PROCESSOR=aarch64
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

# An archive must define every one of its own functions that it refers to.
# A Release build of the app can hide a gap like that (the unused caller is
# stripped), a Debug build cannot.
# check_self_contained <archive> <regex matching the library's own symbols>
check_self_contained() {
    local lib="$1" pattern="$2" undefined defined missing
    # nm's exit status is ignored (it can complain about members that have no
    # symbols); an archive it cannot read at all shows up as an empty list.
    undefined="$(nm -u "$lib" 2>/dev/null | awk '{ print $NF }' | sort -u || true)"
    defined="$(nm -U "$lib" 2>/dev/null | awk '{ print $NF }' | sort -u || true)"
    if [ -z "$defined" ]; then
        echo "error: nm found no defined symbols in $lib" >&2
        exit 1
    fi
    missing="$(comm -23 \
        <(printf '%s\n' "$undefined" | grep -E "$pattern") \
        <(printf '%s\n' "$defined"))"
    if [ -n "$missing" ]; then
        echo "error: $lib refers to symbols it does not define:" >&2
        echo "$missing" >&2
        exit 1
    fi
    echo "-- $lib defines every symbol of its own that it uses"
}

echo "== Checking the archives"
check_self_contained "$OUT/opus/lib/visionOS/libopus.a"     '^_(opus|celt|silk)_'
check_self_contained "$OUT/opus/lib/visionOS-Sim/libopus.a" '^_(opus|celt|silk)_'
check_self_contained "$OUT/SDL2/lib/visionOS/libSDL2.a"     '^_SDL_'
check_self_contained "$OUT/SDL2/lib/visionOS-Sim/libSDL2.a" '^_SDL_'

# The Opus archives must call the NEON routines, as the archives they replace did.
for lib in "$OUT/opus/lib/visionOS/libopus.a" "$OUT/opus/lib/visionOS-Sim/libopus.a"; do
    neon_calls="$(nm -u "$lib" 2>/dev/null | grep -c '_celt_inner_prod_neon$' || true)"
    if [ "${neon_calls:-0}" -eq 0 ]; then
        echo "error: $lib does not call the Opus NEON routines" >&2
        exit 1
    fi
    echo "-- $lib uses the Opus NEON routines"
done

echo "== Done"
ls -la "$OUT/opus/lib/visionOS" "$OUT/opus/lib/visionOS-Sim" "$OUT/SDL2/lib/visionOS" "$OUT/SDL2/lib/visionOS-Sim"
