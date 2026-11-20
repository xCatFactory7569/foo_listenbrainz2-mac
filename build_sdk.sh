#!/bin/bash
# Downloads the foobar2000 SDK and builds its static libraries (Intel, macOS 13+).
set -euo pipefail

SDK_VERSION="${SDK_VERSION:-2026-10-01}"
DEPLOY="${DEPLOYMENT_TARGET:-13.0}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$ROOT/work"
mkdir -p "$WORK"
cd "$WORK"

if [ -f sdk-ready.txt ]; then
  echo "SDK already built (restored from cache). Skipping."
  exit 0
fi

echo "::group::Download SDK $SDK_VERSION"
curl -fL --retry 5 --retry-delay 5 -A "Mozilla/5.0" \
  -o sdk.7z "https://www.foobar2000.org/downloads/SDK-${SDK_VERSION}.7z"
ls -l sdk.7z
echo "::endgroup::"

SEVENZ=""
for c in 7zz 7z 7za; do
  if command -v "$c" >/dev/null 2>&1; then SEVENZ="$c"; break; fi
done
if [ -z "$SEVENZ" ]; then
  echo "Installing 7-zip..."
  brew install sevenzip
  SEVENZ=7zz
fi

rm -rf sdk-extract sdk
mkdir sdk-extract
"$SEVENZ" x -y -osdk-extract sdk.7z > /dev/null
PFC_DIR="$(find sdk-extract -maxdepth 3 -type d -name pfc | head -1)"
if [ -z "$PFC_DIR" ] || [ ! -f "$(dirname "$PFC_DIR")/foobar2000/SDK/foobar2000.h" ]; then
  echo "::error::Unexpected SDK layout. Contents:"
  find sdk-extract -maxdepth 3 | head -50
  exit 1
fi
mv "$(dirname "$PFC_DIR")" sdk
SDK="$WORK/sdk"

xcodebuild -version
rm -f sdk-build.log

build_project () {
  echo "::group::Building $1"
  if ! xcodebuild -project "$SDK/$1" -configuration Release \
      MACOSX_DEPLOYMENT_TARGET="$DEPLOY" ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO \
      SYMROOT="$WORK/products" OBJROOT="$WORK/objects" \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
      build 2>&1 | tee -a sdk-build.log; then
    echo "::endgroup::"
    echo "::error::Building $1 failed. See the log above."
    exit 1
  fi
  echo "::endgroup::"
}

build_project pfc/pfc.xcodeproj
build_project foobar2000/SDK/foobar2000_SDK.xcodeproj
build_project foobar2000/shared/shared.xcodeproj
build_project foobar2000/helpers/foobar2000_SDK_helpers.xcodeproj
build_project foobar2000/foobar2000_component_client/foobar2000_component_client.xcodeproj

echo "Built libraries:"
find "$WORK/products" -name '*.a' -type f
if [ -z "$(find "$WORK/products" -name 'libfoobar2000_component_client.a' -type f)" ]; then
  echo "::error::libfoobar2000_component_client.a was not produced."
  exit 1
fi
echo "ok" > sdk-ready.txt
