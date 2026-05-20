#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)

setup_fixture() {
    local d="$1"
    cat > "${d}/wg0.conf" <<'EOF'
[Interface]
Address = 10.8.8.1
ListenPort = 51820

[Peer] # alice@example.com
PublicKey = AAA
PresharedKey = aaa
AllowedIPs = 10.8.8.2/32

[Peer] # bob@example.com
PublicKey = BBB
PresharedKey = bbb
AllowedIPs = 10.8.8.3/32

[Peer] # carol@example.com
PublicKey = CCC
PresharedKey = ccc
AllowedIPs = 10.8.8.4/32
EOF
    mkdir -p "${d}/clients/alice" "${d}/clients/bob" "${d}/clients/carol"
}

assert_contains()     { grep -qF "$2" "$1" || { echo "FAIL: $1 must contain '$2'"; exit 1; }; }
assert_not_contains() { ! grep -qF "$2" "$1" || { echo "FAIL: $1 must NOT contain '$2'"; exit 1; }; }
assert_dir_exists()   { [ -d "$1" ] || { echo "FAIL: $1 should exist"; exit 1; }; }
assert_dir_absent()   { [ ! -d "$1" ] || { echo "FAIL: $1 should NOT exist"; exit 1; }; }

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT

# Сценарий 1: удалить пира из середины по username
setup_fixture "$d"
WORK_DIR="$d" "${repo_root}/scripts/remove-client.sh" bob >/dev/null
assert_contains     "$d/wg0.conf" "alice@example.com"
assert_contains     "$d/wg0.conf" "carol@example.com"
assert_not_contains "$d/wg0.conf" "bob@example.com"
assert_dir_exists   "$d/clients/alice"
assert_dir_absent   "$d/clients/bob"

# Сценарий 2: удалить последнего пира по полному email
setup_fixture "$d"
WORK_DIR="$d" "${repo_root}/scripts/remove-client.sh" carol@example.com >/dev/null
assert_contains     "$d/wg0.conf" "alice@example.com"
assert_contains     "$d/wg0.conf" "bob@example.com"
assert_not_contains "$d/wg0.conf" "carol@example.com"

# Сценарий 3: удалить первого пира
setup_fixture "$d"
WORK_DIR="$d" "${repo_root}/scripts/remove-client.sh" alice >/dev/null
assert_not_contains "$d/wg0.conf" "alice@example.com"
assert_contains     "$d/wg0.conf" "bob@example.com"
assert_contains     "$d/wg0.conf" "carol@example.com"

# Сценарий 4: отсутствующий пир — ошибка без побочных эффектов
setup_fixture "$d"
before=$(sha256sum "$d/wg0.conf")
if WORK_DIR="$d" "${repo_root}/scripts/remove-client.sh" nobody >/dev/null 2>&1; then
    echo "FAIL: removing non-existent peer should exit non-zero"
    exit 1
fi
after=$(sha256sum "$d/wg0.conf")
[ "$before" = "$after" ] || { echo "FAIL: wg0.conf changed on no-op remove"; exit 1; }

echo "OK"
