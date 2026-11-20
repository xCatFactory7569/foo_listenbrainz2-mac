#!/bin/bash
# Compiles foo_listenbrainz2 for macOS (Intel, macOS 13+) and packages it.
# Mirrors the settings of the SDK's own foo_sample Xcode project:
#   gnu++20, ARC, prefix header stdafx.h, header paths <SDK> <SDK>/foobar2000 <SDK>/pfc.
set -euo pipefail

DEPLOY="${DEPLOYMENT_TARGET:-13.0}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$ROOT/work"
SDK="$WORK/sdk"
OBJ="$WORK/obj"
NAME="foo_listenbrainz2"
BUNDLE="$WORK/$NAME.component"
DIST="$ROOT/dist"

[ -d "$SDK" ] || { echo "::error::SDK not found, run build_sdk.sh first"; exit 1; }
rm -rf "$OBJ" "$BUNDLE" "$DIST" "$WORK/pkg"
mkdir -p "$OBJ" "$BUNDLE/Contents/MacOS" "$DIST"

CXXFLAGS=(-std=gnu++20 -stdlib=libc++ -arch x86_64 -mmacosx-version-min="$DEPLOY"
          -O2 -DNDEBUG=1 -fobjc-arc -fobjc-weak -Wno-everything
          -I"$SDK" -I"$SDK/foobar2000" -I"$SDK/pfc" -I"$ROOT/src"
          -include "$ROOT/src/stdafx.h")

echo "::group::Compiling"
for f in "$ROOT"/src/*.mm; do
  echo "  $(basename "$f")"
  clang++ "${CXXFLAGS[@]}" -x objective-c++ -c "$f" -o "$OBJ/$(basename "${f%.mm}").o"
done
echo "::endgroup::"

# --- link against the five SDK libraries (same set foo_sample links)
CLIENT_LIB="$(find "$WORK/products" -name 'libfoobar2000_component_client.a' -type f | head -1)"
OTHER_LIBS=()
while IFS= read -r lib; do
  [ "$lib" = "$CLIENT_LIB" ] || OTHER_LIBS+=("$lib")
done < <(find "$WORK/products" -name '*.a' -type f)
echo "Client lib: $CLIENT_LIB"
printf 'Other libs:\n'; printf '  %s\n' "${OTHER_LIBS[@]}"

echo "::group::Linking"
clang++ -arch x86_64 -mmacosx-version-min="$DEPLOY" -stdlib=libc++ -bundle \
  -o "$BUNDLE/Contents/MacOS/$NAME" "$OBJ"/*.o \
  -Wl,-force_load,"$CLIENT_LIB" "${OTHER_LIBS[@]}" \
  -framework Cocoa -framework Foundation -framework AppKit -framework CoreFoundation \
  -framework CoreServices -framework Security -framework SystemConfiguration \
  -framework AudioToolbox -framework CoreAudio
echo "::endgroup::"

cp "$ROOT/resources/Info.plist" "$BUNDLE/Contents/Info.plist"

# --- sanity checks
if ! nm -gU "$BUNDLE/Contents/MacOS/$NAME" | grep -q foobar2000_get_interface; then
  echo "::error::The component does not export foobar2000_get_interface; foobar2000 would not load it."
  nm -gU "$BUNDLE/Contents/MacOS/$NAME" | head -30
  exit 1
fi
echo "Export check OK."
lipo -info "$BUNDLE/Contents/MacOS/$NAME"
otool -l "$BUNDLE/Contents/MacOS/$NAME" | grep -A4 -E 'LC_BUILD_VERSION|LC_VERSION_MIN' || true

codesign --force --sign - "$BUNDLE"
codesign -v "$BUNDLE" && echo "Ad-hoc signature OK."

# --- package: .fb2k-component = zip with mac/<bundle>
PKG="$WORK/pkg"
mkdir -p "$PKG/mac" "$PKG/licenses"
cp -R "$BUNDLE" "$PKG/mac/"
cp "$ROOT/LICENSE.txt" "$PKG/licenses/foo_listenbrainz2-license.txt"
find "$SDK" -maxdepth 2 -iname '*license*' -type f 2>/dev/null | while read -r l; do
  cp "$l" "$PKG/licenses/sdk-$(basename "$l")" 2>/dev/null || true
done
(cd "$PKG" && zip -qry "$DIST/$NAME.fb2k-component" mac licenses)
ls -l "$DIST"
