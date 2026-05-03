#!/usr/bin/env bash
# Fetch a prebuilt VLCKit drop for the requested platform.
#
# Usage: get-vlc-frameworks.sh <tv|ios|mac>
# View available releases: https://download.videolan.org/pub/cocoapods/prod/

set -euo pipefail

VERSION="3.7.2-3e42ae47-79128878"
BASE_URL="https://download.videolan.org/pub/cocoapods/prod"

cd "$(dirname "$0")"

usage() {
  echo "Usage: $0 <tv|ios|mac>" >&2
  exit 64
}

[ $# -eq 1 ] || usage

case "$1" in
  tv)  archive="TVVLCKit-${VERSION}.tar.xz";    binary_dir="TVVLCKit-binary";    lock="tv-version.lock"  ;;
  ios) archive="MobileVLCKit-${VERSION}.tar.xz"; binary_dir="MobileVLCKit-binary"; lock="ios-version.lock" ;;
  mac) archive="VLCKit-${VERSION}.tar.xz";       binary_dir="VLCKit - binary package"; lock="mac-version.lock" ;;
  *)   usage ;;
esac

# `Manifest.lock` lets `actions/cache` invalidate when the version changes.
echo "${VERSION}" > Manifest.lock

if [ -f "${lock}" ] && diff -q "${lock}" Manifest.lock >/dev/null 2>&1 && [ -d "${binary_dir}" ]; then
  echo "VLCKit ${VERSION} already present for $1"
  exit 0
fi

echo "Downloading ${archive}"
rm -rf "${binary_dir}"

curl -fsSL --retry 3 --retry-delay 2 "${BASE_URL}/${archive}" | tar -xz -

if [ ! -d "${binary_dir}" ]; then
  echo "ERROR: ${binary_dir} missing after extraction" >&2
  exit 1
fi

echo "${VERSION}" > "${lock}"
echo "VLCKit ${VERSION} ready for $1"
