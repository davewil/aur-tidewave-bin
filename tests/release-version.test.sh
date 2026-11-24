#!/bin/sh
# Tests for scripts/release-version.sh. Run: sh tests/release-version.test.sh
set -u

script="$(dirname "$0")/../scripts/release-version.sh"
failed=0

accepts() {
    if got=$(printf '%s' "$2" | sh "$script" 2>/dev/null) && [ "$got" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: got '${got:-}', want '$3'"
        failed=1
    fi
}

rejects() {
    if got=$(printf '%s' "$2" | sh "$script" 2>/dev/null); then
        echo "FAIL $1: accepted as '$got'"
        failed=1
    else
        echo "ok   $1"
    fi
}

accepts "v-prefixed tag"       '{"tag_name":"v1.1.0"}'  1.1.0
accepts "single-number tag"    '{"tag_name":"v2"}'      2

rejects "rate-limit error body" '{"message":"API rate limit exceeded for 203.0.113.1."}'
rejects "HTML error page"       '<!DOCTYPE html><html></html>'
rejects "empty response"        ''
rejects "JSON null"             'null'
rejects "tag without v"         '{"tag_name":"1.2.3"}'
rejects "prerelease tag"        '{"tag_name":"v1.2.0-rc1"}'
rejects "hyphenated tag"        '{"tag_name":"v1.2-3"}'
rejects "non-version tag"       '{"tag_name":"nightly"}'
rejects "path in tag"           '{"tag_name":"v1.2/../evil"}'
rejects "empty version"         '{"tag_name":"v"}'
rejects "double dot"            '{"tag_name":"v1..2"}'
rejects "newline in tag"        '{"tag_name":"v1.2\nupdate=true"}'
rejects "trailing newline"      '{"tag_name":"v1.2\n"}'
rejects "two JSON documents"    '{"tag_name":"v1"}{"tag_name":"v2"}'

if out=$(printf '{"message":"x"}' | sh "$script" 2>&1) || [ -z "$out" ]; then
    echo "FAIL missing tag explains itself: '$out'"
    failed=1
else
    echo "ok   missing tag explains itself"
fi

exit "$failed"
