#!/bin/sh
# Usage: needs-update.sh CURRENT LATEST
# Prints "true" if LATEST is a newer version than CURRENT (by pacman's
# vercmp), otherwise "false", so an older upstream "latest" release never
# downgrades the package. Exits non-zero if it can't compare.
set -eu

if [ $# -ne 2 ]; then
    echo "usage: $0 CURRENT LATEST" >&2
    exit 2
fi

order=$(vercmp "$2" "$1")

if [ "$order" -gt 0 ]; then
    echo true
else
    echo false
fi
