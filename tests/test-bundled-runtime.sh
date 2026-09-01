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
export FAKE_WINESERVER_LOG="$sandbox/wineserver.log"
unset WEGAME_DWPROTON_PROTON

readonly prefix="$XDG_DATA_HOME/wegame-dwproton/compatdata/pfx"
readonly bundled_runtime="$WEGAME_DWPROTON_SHARE_DIR/dwproton"
readonly fallback_runtime="$XDG_DATA_HOME/lutris/runners/wine/dwproton-fallback"

fail() {
    printf 'test-bundled-runtime: %s\n' "$*" >&2
    exit 1
}

mkdir -p -- "$prefix" "$bundled_runtime/files/bin" "$fallback_runtime/files/bin"

cat > "$bundled_runtime/proton" <<'EOF'
#!/usr/bin/bash
exit 90
EOF
cat > "$bundled_runtime/files/bin/wineserver" <<'EOF'
#!/usr/bin/bash
set -euo pipefail
printf '%s|%s\n' "${WINEPREFIX:?}" "$*" > "${FAKE_WINESERVER_LOG:?}"
EOF
cat > "$fallback_runtime/proton" <<'EOF'
#!/usr/bin/bash
exit 91
EOF
cat > "$fallback_runtime/files/bin/wineserver" <<'EOF'
#!/usr/bin/bash
exit 92
EOF
chmod 755 \
    "$bundled_runtime/proton" \
    "$bundled_runtime/files/bin/wineserver" \
    "$fallback_runtime/proton" \
    "$fallback_runtime/files/bin/wineserver"

output=$("$launcher" --stop)
[[ "$output" == *"Using DWProton: $bundled_runtime/proton"* ]] ||
    fail 'the bundled runtime was not preferred'
[[ -f "$FAKE_WINESERVER_LOG" ]] || fail 'the bundled wineserver was not called'
actual=$(<"$FAKE_WINESERVER_LOG")
[[ "$actual" == "$prefix|-k" ]] || fail "unexpected wineserver invocation: $actual"

printf 'test-bundled-runtime: passed\n'
