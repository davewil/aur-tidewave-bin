#!/bin/sh
# Usage: latest-version.sh OWNER/REPO
# Prints the version of the repo's latest GitHub release, authenticating with
# $GH_TOKEN. Fails on any API error or unexpected tag, logging GitHub's
# response, so an error can never be mistaken for a new version.
set -eu

if [ $# -ne 1 ]; then
    echo "usage: $0 OWNER/REPO" >&2
    exit 2
fi

body=$(mktemp)
trap 'rm -f "$body"' EXIT

# fail_with_body MESSAGE: log the message and GitHub's response, then exit
fail_with_body() {
    echo "::error::$1 Response body:" >&2
    # Defuse "::" so the body can't act as a workflow command (the runner ignores indentation)
    sed 's/^\([[:space:]]*\)::/\1: :/' "$body" >&2
    exit 1
}

# --retry covers only transient failures (timeouts, 408/429/5xx): retrying a 401 or
# 403 would just spend more rate limit.
# -o, not stdout: a retry then overwrites the earlier error body instead of appending to it
if ! curl --fail-with-body -sS --retry 3 --retry-delay 5 \
    -H "Authorization: Bearer ${GH_TOKEN:?GH_TOKEN must be set}" -o "$body" \
    "https://api.github.com/repos/$1/releases/latest"; then
    fail_with_body "Release lookup failed."
fi

if ! sh "$(dirname "$0")/release-version.sh" < "$body"; then
    fail_with_body "Release response has no usable tag."
fi
