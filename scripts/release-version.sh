#!/bin/sh
# Reads a GitHub release (JSON) on stdin and prints its version: the tag
# without its leading "v". The PKGBUILD downloads from .../download/v${pkgver}/,
# so anything other than a single release with a "v"-prefixed numeric tag is
# rejected, and an API error body can never become a pkgver.
set -eu

# The "x" keeps command substitution from stripping trailing newlines from the
# tag itself; only the one newline jq adds is removed.
if ! out=$(jq -er '.tag_name' && echo x); then
    echo "::error::Release JSON has no tag_name" >&2
    exit 1
fi
tag=${out%x}
tag=${tag%"
"}

case $tag in
    v*) version=${tag#v} ;;
    *) version= ;;
esac

# Checks the whole string, so a tag holding a newline (or two JSON documents) fails too
case $version in
    '' | .* | *. | *..* | *[!0-9.]*)
        printf '::error::Unexpected release tag: %s\n' "$(printf '%s' "$tag" | tr '\n' ' ')" >&2
        exit 1
        ;;
esac

printf '%s\n' "$version"
