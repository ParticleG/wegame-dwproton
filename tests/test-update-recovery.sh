#!/usr/bin/bash
# SPDX-FileCopyrightText: 2026 ParticleG
# SPDX-License-Identifier: 0BSD
# shellcheck disable=SC2218 # ShellCheck 0.11 misorders calls to functions defined above.

set -euo pipefail

project_dir=$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd)
readonly project_dir
readonly launcher="$project_dir/wegame-dwproton"
sandbox=$(mktemp -d)
readonly sandbox
trap 'rm -rf -- "$sandbox"' EXIT

export HOME="$sandbox/home"
export XDG_DATA_HOME="$sandbox/data"
export XDG_STATE_HOME="$sandbox/state"
export XDG_CACHE_HOME="$sandbox/cache"
export WEGAME_DWPROTON_SHARE_DIR="$sandbox/share"
export WEGAME_DWPROTON_PROTON=/bin/true

readonly prefix="$XDG_DATA_HOME/wegame-dwproton/compatdata/pfx"
readonly install_dir="$prefix/drive_c/Program Files (x86)/WeGame"
readonly payload="$install_dir/wegame_update"
readonly status="$install_dir/update.tmp"

fail() {
    printf 'test-update-recovery: %s\n' "$*" >&2
    exit 1
}

assert_file_content() {
    local path=$1 expected=$2 actual
    [[ -f "$path" ]] || fail "missing file: $path"
    actual=$(<"$path")
    [[ "$actual" == "$expected" ]] || fail "unexpected content in $path: $actual"
}

make_confirmed_update() {
    mkdir -p -- "$payload/bin" "$install_dir/bin" "$install_dir/config"
    printf 'old-client\n' > "$install_dir/wegame.exe"
    printf 'old-library\n' > "$install_dir/bin/library.dll"
    printf 'keep\n' > "$install_dir/config/user.ini"
    printf 'new-client\n' > "$payload/wegame.exe"
    printf 'new-library\n' > "$payload/bin/library.dll"
    printf 'new-file\n' > "$payload/bin/new.dll"
    printf 'OverwriteStatus=7299004\r\nTickMoveFile=-1\r\n' > "$status"
}

make_confirmed_update
"$launcher" --recover-update

assert_file_content "$install_dir/wegame.exe" 'new-client'
assert_file_content "$install_dir/bin/library.dll" 'new-library'
assert_file_content "$install_dir/bin/new.dll" 'new-file'
assert_file_content "$install_dir/config/user.ini" 'keep'
[[ ! -e "$payload" ]] || fail 'the applied payload was not archived'
[[ ! -e "$status" ]] || fail 'the applied status file was not archived'

shopt -s nullglob
backups=("$XDG_STATE_HOME/wegame-dwproton/update-backups"/*)
shopt -u nullglob
((${#backups[@]} == 1)) || fail "expected one backup, found ${#backups[@]}"
readonly backup=${backups[0]}
assert_file_content "$backup/overwritten/wegame.exe" 'old-client'
assert_file_content "$backup/overwritten/bin/library.dll" 'old-library'
assert_file_content "$backup/wegame_update/wegame.exe" 'new-client'
assert_file_content "$backup/update.tmp" $'OverwriteStatus=7299004\r\nTickMoveFile=-1\r'

"$launcher" --recover-update
shopt -s nullglob
backups=("$XDG_STATE_HOME/wegame-dwproton/update-backups"/*)
shopt -u nullglob
((${#backups[@]} == 1)) || fail 'idempotent recovery created another backup'

mkdir -p -- "$payload"
printf 'unknown-client\n' > "$payload/wegame.exe"
printf 'OverwriteStatus=7299005\nTickMoveFile=-1\n' > "$status"
if "$launcher" --recover-update >/dev/null 2>&1; then
    fail 'an unknown update status was accepted'
fi
assert_file_content "$payload/wegame.exe" 'unknown-client'
assert_file_content "$status" $'OverwriteStatus=7299005\nTickMoveFile=-1'
assert_file_content "$install_dir/wegame.exe" 'new-client'

rm -rf -- "$payload"
mkdir -p -- "$payload"
printf 'symlink-client\n' > "$payload/wegame.exe"
ln -s -- /etc/passwd "$payload/unsafe-link"
printf 'OverwriteStatus=7299004\nTickMoveFile=-1\n' > "$status"
if "$launcher" --recover-update >/dev/null 2>&1; then
    fail 'a symbolic link in the update payload was accepted'
fi
[[ -L "$payload/unsafe-link" ]] || fail 'the rejected payload was modified'
assert_file_content "$install_dir/wegame.exe" 'new-client'

printf 'test-update-recovery: passed\n'
