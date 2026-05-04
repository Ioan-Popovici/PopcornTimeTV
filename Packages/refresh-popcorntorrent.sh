#!/usr/bin/env bash
# Manual maintenance: re-pull alextud/PopcornTorrent@v2_3 from upstream and
# reapply popcorntorrent.patch on top. Use this when there's an upstream
# fix worth picking up.
#
# This script is NOT part of the regular build — Packages/PopcornTorrent/ is
# committed in-tree, so a normal `make build*` works offline. Run by hand
# from the repo root:
#
#     bash Packages/refresh-popcorntorrent.sh
#
# Then `git diff Packages/PopcornTorrent` to review what changed and commit.

set -euo pipefail

REPO="https://github.com/alextud/PopcornTorrent"
BRANCH="v2_3"

cd "$(dirname "$0")"

DEST="PopcornTorrent"
PATCH="popcorntorrent.patch"

if [ -d "${DEST}" ]; then
  read -p "Wipe ${DEST}/ and re-clone from ${REPO}@${BRANCH}? [y/N] " yn
  case "${yn}" in
    [Yy]*) rm -rf "${DEST}" ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

echo "Cloning ${REPO} (branch ${BRANCH})..."
git clone --depth 1 --branch "${BRANCH}" "${REPO}" "${DEST}"
rm -rf "${DEST}/.git"

# Drop subtrees we don't ship.
rm -rf "${DEST}/PopcornTorrentTests" \
       "${DEST}/Package.resolved" \
       "${DEST}/update_boost.sh" \
       "${DEST}/update_torrent.sh"

echo "Applying ${PATCH}..."
( cd "${DEST}" && patch -p1 < "../${PATCH}" )

date -u +"%Y-%m-%dT%H:%M:%SZ vendored from ${REPO}@${BRANCH} + ${PATCH}" > "${DEST}/.mem-zone-patched"
echo
echo "Done. Review with:  git diff Packages/PopcornTorrent"
