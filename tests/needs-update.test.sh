#!/bin/sh
# Tests for scripts/needs-update.sh. Needs pacman's vercmp.
# Run: sh tests/needs-update.test.sh
set -u

script="$(dirname "$0")/../scripts/needs-update.sh"
failed=0

check() {
    got=$(sh "$script" "$2" "$3" 2>/dev/null)
    if [ "$got" = "$4" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: got '$got', want '$4'"
        failed=1
    fi
}

check "newer patch release"        1.1.0  1.1.1  true
check "newer major release"        1.1.0  2      true
check "numeric, not string, order" 1.9.0  1.10.0 true
check "same version"               1.1.0  1.1.0  false
check "older upstream release"     1.2.0  1.1.0  false

if sh "$script" 1.1.0 >/dev/null 2>&1; then
    echo "FAIL missing argument: accepted"
    failed=1
else
    echo "ok   missing argument"
fi

empty=$(mktemp -d)
if got=$(PATH="$empty" /bin/sh "$script" 1.1.0 1.2.0 2>/dev/null); then
    echo "FAIL vercmp missing: answered '$got' instead of failing"
    failed=1
else
    echo "ok   vercmp missing"
fi
rmdir "$empty"

exit "$failed"
