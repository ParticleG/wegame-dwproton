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
export WEGAME_DWPROTON_PROTON="$sandbox/fake-proton/proton"
export FAKE_PROTON_LOG="$sandbox/proton.log"

readonly compat_data="$XDG_DATA_HOME/wegame-dwproton/compatdata"
readonly prefix="$compat_data/pfx"
readonly install_dir="$prefix/drive_c/Program Files (x86)/WeGame"
readonly client="$install_dir/wegame.exe"

fail() {
    printf 'test-launch-lifecycle: %s\n' "$*" >&2
    exit 1
}

mkdir -p -- "$WEGAME_DWPROTON_SHARE_DIR" "${WEGAME_DWPROTON_PROTON%/*}"
printf 'official-installer-placeholder\n' > "$WEGAME_DWPROTON_SHARE_DIR/WeGameMiniLoader.exe"

cat > "$WEGAME_DWPROTON_PROTON" <<'EOF'
#!/usr/bin/bash
set -euo pipefail

[[ ${1:-} == waitforexitandrun ]] || exit 20
target=${2:?missing target}
printf '%s|%s|%s\n' "$target" "${STEAM_COMPAT_DATA_PATH:?}" "${WINEPREFIX:?}" >> "${FAKE_PROTON_LOG:?}"

if [[ ${target##*/} == WeGameMiniLoader.exe ]]; then
    client="$WINEPREFIX/drive_c/Program Files (x86)/WeGame/wegame.exe"
    mkdir -p -- "${client%/*}"
    printf 'installed-client\n' > "$client"
fi
EOF
chmod 755 "$WEGAME_DWPROTON_PROTON"

"$launcher"
[[ -f "$client" ]] || fail 'the first launch did not create the expected client path'
"$launcher"
"$launcher"

mapfile -t launches < "$FAKE_PROTON_LOG"
((${#launches[@]} == 3)) || fail "expected three Proton invocations, found ${#launches[@]}"
[[ "${launches[0]}" == "$WEGAME_DWPROTON_SHARE_DIR/WeGameMiniLoader.exe|$compat_data|$prefix" ]] ||
    fail 'the first launch did not run the installer in the isolated prefix'
[[ "${launches[1]}" == "$client|$compat_data|$prefix" ]] ||
    fail 'the second launch did not run the installed client'
[[ "${launches[2]}" == "$client|$compat_data|$prefix" ]] ||
    fail 'the third launch did not reuse the installed client'

printf 'test-launch-lifecycle: passed\n'
