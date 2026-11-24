#!/bin/sh
# Tests for scripts/sync-aur.sh, against a local bare git repo standing in for
# the AUR. Needs git and pacman's vercmp. Run: sh tests/sync-aur.test.sh
set -u

script="$(cd "$(dirname "$0")/.." && pwd)/scripts/sync-aur.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null

# package DIR PKGVER PKGREL [EPOCH [DEPENDS]]: write a PKGBUILD and the
# .SRCINFO makepkg would generate for it
package() {
    mkdir -p "$1"
    {
        printf 'pkgname=tidewave-bin\n'
        [ -n "${4:-}" ] && printf 'epoch=%s\n' "$4"
        printf 'pkgver=%s\npkgrel=%s\n' "$2" "$3"
        [ -n "${5:-}" ] && printf "depends=('%s')\n" "$5"
    } > "$1/PKGBUILD"
    {
        printf 'pkgbase = tidewave-bin\n\tpkgver = %s\n\tpkgrel = %s\n' "$2" "$3"
        [ -n "${4:-}" ] && printf '\tepoch = %s\n' "$4"
        [ -n "${5:-}" ] && printf '\tdepends = %s\n' "$5"
        printf '\npkgname = tidewave-bin\n'
    } > "$1/.SRCINFO"
}

# aur PKGVER PKGREL [EPOCH [DEPENDS]]: fresh bare repo holding that version,
# on master like the AUR whatever git's default branch; "" for an empty repo
aur() {
    rm -rf "$tmp/aur.git" "$tmp/seed"
    git init -q --bare --initial-branch=master "$tmp/aur.git"
    [ -z "$1" ] && return
    package "$tmp/seed" "$@"
    git -C "$tmp/seed" init -q --initial-branch=master
    git -C "$tmp/seed" add PKGBUILD .SRCINFO
    git -C "$tmp/seed" commit -q -m seed
    git -C "$tmp/seed" push -q "$tmp/aur.git" HEAD:master
}

# sync PKGVER PKGREL [EPOCH [DEPENDS]]: run the script from a repo holding that version
sync() {
    rm -rf "$tmp/repo"
    package "$tmp/repo" "$@"
    (cd "$tmp/repo" && sh "$script" "$tmp/aur.git") > "$tmp/out" 2>&1
}

aur_version() {
    git -C "$tmp/aur.git" show master:.SRCINFO 2>/dev/null | awk -F' = ' '$1 == "\tpkgver" { v = $2 } $1 == "\tpkgrel" { r = $2 } END { print v "-" r }'
}
aur_commits() { git -C "$tmp/aur.git" rev-list --count master 2>/dev/null || echo 0; }

expect() { # NAME STATUS zero|nonzero VERSION WANT_VERSION COMMITS WANT_COMMITS
    if [ "$3" = zero ]; then status_ok=$([ "$2" = 0 ] && echo y); else status_ok=$([ "$2" != 0 ] && echo y); fi
    if [ "$status_ok" = y ] && [ "$4" = "$5" ] && [ "$6" = "$7" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: status=$2 (want $3) aur=$4 (want $5) commits=$6 (want $7): $(cat "$tmp/out")"
        failed=1
    fi
}

aur 1.1.0 1; sync 1.1.0 1
expect "matching AUR: nothing pushed"       "$?" zero    "$(aur_version)" 1.1.0-1 "$(aur_commits)" 1

aur 1.1.0 1; sync 1.2.0 1
expect "newer release: pushed"              "$?" zero    "$(aur_version)" 1.2.0-1 "$(aur_commits)" 2
if git -C "$tmp/aur.git" log -1 --format=%s master | grep -qx 'Update tidewave-bin to 1.2.0'; then
    echo "ok   commit message names the version"
else
    echo "FAIL commit message names the version"
    failed=1
fi

aur 1.1.0 1; sync 1.1.0 2
expect "pkgrel bump: pushed"                "$?" zero    "$(aur_version)" 1.1.0-2 "$(aur_commits)" 2

aur 1.2.0 1; sync 1.1.0 1
expect "older pkgver: AUR left alone"       "$?" nonzero "$(aur_version)" 1.2.0-1 "$(aur_commits)" 1

aur 1.1.0 2; sync 1.1.0 1
expect "older pkgrel: AUR left alone"       "$?" nonzero "$(aur_version)" 1.1.0-2 "$(aur_commits)" 1

aur 1.1.0 1 "" fuse2; sync 1.1.0 1
expect "same version, AUR fixed by hand: AUR left alone" "$?" nonzero "$(aur_version)" 1.1.0-1 "$(aur_commits)" 1

aur 1.0.0 1 1; sync 2.0.0 1
expect "AUR epoch outranks pkgver: AUR left alone" "$?" nonzero "$(aur_version)" 1.0.0-1 "$(aur_commits)" 1

aur 1.0.0 1 1; sync 1.1.0 1 1
expect "newer release at same epoch: pushed" "$?" zero   "$(aur_version)" 1.1.0-1 "$(aur_commits)" 2

aur 1.2.0 1
nocompare="$tmp/nocompare"
mkdir "$nocompare"
for c in git awk mktemp cp rm cat; do ln -s "$(command -v "$c")" "$nocompare/$c"; done
rm -rf "$tmp/repo"
package "$tmp/repo" 1.1.0 1
(cd "$tmp/repo" && PATH="$nocompare" /bin/sh "$script" "$tmp/aur.git") > "$tmp/out" 2>&1
expect "vercmp missing: fails, AUR left alone" "$?" nonzero "$(aur_version)" 1.2.0-1 "$(aur_commits)" 1

aur "" ""; sync 1.1.0 1
expect "empty AUR repo: first push"         "$?" zero    "$(aur_version)" 1.1.0-1 "$(aur_commits)" 1

exit "$failed"
