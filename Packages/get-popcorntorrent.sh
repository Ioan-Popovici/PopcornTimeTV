#!/usr/bin/env bash
# Vendor the alextud/PopcornTorrent SwiftPM dependency locally and apply the
# MEM.Zone streaming-latency patch on top.
#
# The Xcode project references this dependency by relative path
# (PopcornTime.xcodeproj/project.pbxproj — XCLocalSwiftPackageReference
# "Packages/PopcornTorrent"), so the source must exist before xcodebuild.
# CI calls this script in its build matrix; locally it's invoked through
# `make vendor-popcorntorrent`.
#
# Idempotent: if the patched marker already exists, the script is a no-op.

set -euo pipefail

REPO="https://github.com/alextud/PopcornTorrent"
BRANCH="v2_3"

cd "$(dirname "$0")"

DEST="PopcornTorrent"
PATCH="popcorntorrent.patch"
MARKER="${DEST}/.mem-zone-patched"

if [ -f "${MARKER}" ]; then
  echo "PopcornTorrent already vendored and patched."
  exit 0
fi

if [ -d "${DEST}" ]; then
  echo "${DEST} exists but is unpatched — wiping and re-cloning to keep build deterministic."
  rm -rf "${DEST}"
fi

echo "Cloning ${REPO} (branch ${BRANCH})..."
git clone --depth 1 --branch "${BRANCH}" "${REPO}" "${DEST}"

# Drop the upstream .git so this directory doesn't get treated as a
# submodule by the parent repo.
rm -rf "${DEST}/.git"

echo "Applying ${PATCH}..."
( cd "${DEST}" && patch -p1 < "../${PATCH}" )

date -u +"%Y-%m-%dT%H:%M:%SZ patched against ${REPO}@${BRANCH}" > "${MARKER}"
echo "PopcornTorrent ready at ${PWD}/${DEST}"
