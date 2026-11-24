#!/bin/sh
# Usage: sync-aur.sh AUR_GIT_URL
# Run from the repo root. Publishes this repo's PKGBUILD and .SRCINFO to the
# AUR package repo. Pushes nothing when the AUR already matches, and refuses to
# overwrite the AUR with an older version, or with different files at the same
# version (a fix pushed straight to the AUR is kept until a pkgrel bump here).
set -eu

if [ $# -ne 1 ]; then
    echo "usage: $0 AUR_GIT_URL" >&2
    exit 2
fi

# [epoch:]pkgver-pkgrel from a .SRCINFO
full_version() {
    awk -F' = ' '
        $1 == "\tepoch" { e = $2 }
        $1 == "\tpkgver" { v = $2 }
        $1 == "\tpkgrel" { r = $2 }
        END { if (v != "" && r != "") print (e != "" ? e ":" : "") v "-" r }
    ' "$1"
}

ours=$(full_version .SRCINFO)
if [ -z "$ours" ]; then
    echo "::error::No pkgver/pkgrel in this repo's .SRCINFO" >&2
    exit 1
fi

aur=$(mktemp -d)
trap 'rm -rf "$aur"' EXIT
git clone -q "$1" "$aur"

theirs=
if [ -f "$aur/.SRCINFO" ]; then
    theirs=$(full_version "$aur/.SRCINFO")
    if [ -z "$theirs" ]; then
        echo "::error::No pkgver/pkgrel in the AUR's .SRCINFO" >&2
        exit 1
    fi
fi

cp PKGBUILD .SRCINFO "$aur/"
cd "$aur"
git add PKGBUILD .SRCINFO

if git diff --cached --quiet; then
    echo "AUR already up to date ($ours)"
    exit 0
fi

if [ -n "$theirs" ]; then
    # On its own line so a missing vercmp stops the script (set -e doesn't apply inside if)
    order=$(vercmp "$ours" "$theirs")
    if [ "$order" -lt 0 ]; then
        echo "::error::The AUR has $theirs, newer than this repo's $ours. Not downgrading it." >&2
        exit 1
    fi
    if [ "$order" -eq 0 ]; then
        echo "::error::The AUR's files differ from this repo's at the same version ($ours). Not overwriting them: bump pkgrel to publish a change." >&2
        exit 1
    fi
fi

git commit -q -m "Update tidewave-bin to ${ours%-*}"
# The AUR only accepts pushes to master
git push -q origin HEAD:master
echo "Pushed $ours to the AUR"
