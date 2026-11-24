#!/bin/sh
# Tests for scripts/latest-version.sh, with a stand-in curl on PATH.
# Run: sh tests/latest-version.test.sh
# "cond && pass || fail" is safe here: pass only echoes, so fail never runs after it
# shellcheck disable=SC2015
set -u

script="$(cd "$(dirname "$0")/.." && pwd)/scripts/latest-version.sh"
fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT
failed=0

# Stand-in curl: records its arguments, writes $FAKE_BODY to the -o file, exits $FAKE_EXIT
cat > "$fake/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$FAKE_DIR/args"
while [ $# -gt 0 ]; do
    if [ "$1" = -o ]; then printf '%s' "$FAKE_BODY" > "$2"; fi
    shift
done
exit "$FAKE_EXIT"
EOF
chmod +x "$fake/curl"

# run BODY CURL_EXIT [GH_TOKEN]: sets $out, $err and $status
run() {
    rm -f "$fake/args"
    out=$(FAKE_DIR=$fake FAKE_BODY=$1 FAKE_EXIT=$2 GH_TOKEN=${3-secret} PATH="$fake:$PATH" \
        sh "$script" tidewave-ai/tidewave_app 2>"$fake/err")
    status=$?
    err=$(cat "$fake/err")
}

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; failed=1; }

run '{"tag_name":"v1.2.0"}' 0
[ "$status" = 0 ] && [ "$out" = 1.2.0 ] && pass "prints the latest version" || fail "prints the latest version: status=$status out='$out' err='$err'"
grep -qx 'https://api.github.com/repos/tidewave-ai/tidewave_app/releases/latest' "$fake/args" \
    && pass "asks for the repo's latest release" || fail "asks for the repo's latest release"
grep -qx 'Authorization: Bearer secret' "$fake/args" \
    && pass "authenticates with GH_TOKEN" || fail "authenticates with GH_TOKEN"

run '{"message":"API rate limit exceeded"}' 22
[ "$status" != 0 ] && [ -z "$out" ] && pass "HTTP error fails" || fail "HTTP error fails: status=$status out='$out'"
case $err in *"API rate limit exceeded"*) pass "HTTP error logs GitHub's reason" ;; *) fail "HTTP error logs GitHub's reason: '$err'" ;; esac

run '' 7
[ "$status" != 0 ] && [ -z "$out" ] && pass "network error fails" || fail "network error fails: status=$status out='$out'"

run '{"message":"Not Found"}' 0
[ "$status" != 0 ] && [ -z "$out" ] && pass "release-less 200 fails" || fail "release-less 200 fails: status=$status out='$out'"
case $err in *'"Not Found"'*) pass "release-less 200 logs the response" ;; *) fail "release-less 200 logs the response: '$err'" ;; esac

run '::add-mask::hidden
  ::stop-commands::x' 22
if printf '%s\n' "$err" | grep -Eq '^[[:space:]]*::(add-mask|stop-commands)::'; then fail "response can't issue workflow commands: '$err'"; else pass "response can't issue workflow commands"; fi

run '{"tag_name":"v1.2.0"}' 0 ''
[ "$status" != 0 ] && [ ! -e "$fake/args" ] && pass "missing GH_TOKEN fails before any request" || fail "missing GH_TOKEN fails before any request: status=$status"

exit "$failed"
