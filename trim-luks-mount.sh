#!/usr/bin/env bash
# trim-luks-mount.sh - run fstrim on a mounted data disk, rate-limited.
#
# Usage: trim-luks-mount.sh <mount-point>
#
# Environment:
#   MIN_AGE  minimum seconds between runs (default 86400 = 24h)
#   STAMP    stamp file (default /var/lib/trim-luks-mount/last-run)
#
# The stamp is written only when fstrim succeeds, so an interrupted run is
# retried on the next invocation.
set -u

MOUNT="${1:-}"
MIN_AGE="${MIN_AGE:-86400}"
STAMP="${STAMP:-/var/lib/trim-luks-mount/last-run}"

if [ -z "$MOUNT" ]; then
    echo "usage: $0 <mount-point>" >&2
    exit 2
fi

# Safety net: do nothing if the disk is not mounted.
mountpoint -q "$MOUNT" || exit 0

# Rate limit: skip if the last successful run is younger than MIN_AGE.
if [ -f "$STAMP" ]; then
    now=$(date +%s)
    last=$(stat -c %Y "$STAMP")
    if [ $((now - last)) -lt "$MIN_AGE" ]; then
        exit 0
    fi
fi

if fstrim -v "$MOUNT"; then
    mkdir -p "$(dirname "$STAMP")"
    date +%s > "$STAMP"
fi
