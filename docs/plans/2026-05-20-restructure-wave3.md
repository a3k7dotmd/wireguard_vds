# Wave 3: list/status/regenerate/export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Add four read/admin subcommands to `wgctl`: `list`, `status`, `regenerate`, `export`. Each feature lands end-to-end (script + wgctl case + menu item + Makefile target + smoke scenario) in a single commit.

**Architecture:** No new infrastructure — uses the wgctl/menu/Makefile layering from Wave 1 and the `state.env` source-format from Wave 2. Each new script is parametrised by `WORK_DIR` (for smoke), uses `command -v systemctl` guard for live `wg` calls.

**Tech Stack:** bash, awk. No new deps.

**Reference:** [docs/specs/2026-05-20-restructure-wave3-design.md](../specs/2026-05-20-restructure-wave3-design.md)

---

## Task 1: `wgctl list`

**Files:**
- Create: `scripts/list.sh` (`chmod +x`)
- Modify: `wgctl` (case-arm + usage)
- Modify: `scripts/menu.sh` (new item)
- Modify: `Makefile` (new target + help)
- Modify: `tests/smoke.sh` (new scenario)

- [ ] **Step 1: Create `scripts/list.sh`**

Exact contents (`chmod +x` after writing):

```bash
#!/bin/bash
# Список зарегистрированных клиентов (email, IP, public key).
set -euo pipefail

WORK_DIR="${WORK_DIR:-/etc/wireguard}"

cd "${WORK_DIR}" || exit 1

if [ ! -f wg0.conf ]; then
    echo "[#] wg0.conf не найден. WireGuard не установлен?" >&2
    exit 1
fi

awk '
BEGIN {
    printf "%-30s %-18s %s\n", "EMAIL", "IP", "PUBLIC KEY"
    printf "%-30s %-18s %s\n", "─────", "──", "──────────"
}
/^\[Peer\] # / {
    email = substr($0, 10)
    next
}
/^PublicKey = / {
    pubkey = $3
    next
}
/^AllowedIPs = / {
    ip = $3
    if (email != "") {
        printf "%-30s %-18s %s\n", email, ip, pubkey
        email = ""
        pubkey = ""
    }
    next
}
' wg0.conf
```

- [ ] **Step 2: Add `list` to `wgctl`**

In `wgctl`, locate the case block. Add **before** the `menu)` arm:

```bash
    list)           "${SCRIPTS}/list.sh" ;;
```

Also add to the `usage()` heredoc (after the `uninstall` line, before `menu`):

```
  list                 Показать список клиентов (email, IP, public key)
```

- [ ] **Step 3: Add menu item to `scripts/menu.sh`**

In the heredoc menu listing, add **before** the `q) Выход` line:

```
  6) Список клиентов
```

In the case statement, add **before** the `q|Q|""` arm:

```bash
        6) "${WGCTL}" list ;;
```

- [ ] **Step 4: Add `list` target to `Makefile`**

In the `.PHONY:` line, add `list`. Add the rule:

```makefile
list:      ; ./wgctl list
```

In the `help:` recipe, add a line before the dev section:

```bash
	@echo "  make list                     список клиентов"
```

- [ ] **Step 5: Add smoke scenario**

In `tests/smoke.sh`, insert **before** the final `echo "OK"`:

```bash
# Сценарий 6: list выводит всех трёх пиров
setup_fixture "$d"
output=$(WORK_DIR="$d" "${repo_root}/wgctl" list)
echo "$output" | grep -qF "alice@example.com" || { echo "FAIL: list missing alice"; exit 1; }
echo "$output" | grep -qF "bob@example.com"   || { echo "FAIL: list missing bob"; exit 1; }
echo "$output" | grep -qF "carol@example.com" || { echo "FAIL: list missing carol"; exit 1; }
echo "$output" | grep -qF "10.8.8.2/32"       || { echo "FAIL: list missing alice IP"; exit 1; }
echo "$output" | grep -qF "10.8.8.3/32"       || { echo "FAIL: list missing bob IP"; exit 1; }
echo "$output" | grep -qF "10.8.8.4/32"       || { echo "FAIL: list missing carol IP"; exit 1; }

```

- [ ] **Step 6: Verify**

```bash
cd /Users/ragnar/fedorov_tech/wireguard_vds
chmod +x scripts/list.sh
make lint
make test
```

Expected: lint silent, test prints `OK`.

- [ ] **Step 7: Commit**

```bash
git add scripts/list.sh wgctl scripts/menu.sh Makefile tests/smoke.sh
git commit -m "feat: wgctl list — show registered clients

Parses wg0.conf, prints a table of email/IP/public-key for each
[Peer] block. Smoke covers a three-peer fixture."
```

---

## Task 2: `wgctl status`

**Files:**
- Create: `scripts/status.sh` (`chmod +x`)
- Modify: `wgctl` (case-arm + usage)
- Modify: `scripts/menu.sh`
- Modify: `Makefile`
- Modify: `tests/smoke.sh`

- [ ] **Step 1: Create `scripts/status.sh`**

```bash
#!/bin/bash
# Состояние WireGuard-сервиса.
set -euo pipefail

if command -v systemctl >/dev/null && systemctl is-active --quiet wg-quick@wg0; then
    wg show wg0
else
    echo "WireGuard сервис не запущен"
fi
```

- [ ] **Step 2: Add `status` to `wgctl`**

In `wgctl` case block, **before** `menu)`:
```bash
    status)         "${SCRIPTS}/status.sh" ;;
```
In `usage()`:
```
  status               Состояние WireGuard-сервиса
```

- [ ] **Step 3: Add menu item to `scripts/menu.sh`**

Heredoc, **before** `q)`:
```
  7) Статус WireGuard
```
Case statement:
```bash
        7) "${WGCTL}" status ;;
```

- [ ] **Step 4: Add `status` target to `Makefile`**

`.PHONY:` line — append `status`. Rule:
```makefile
status:    ; ./wgctl status
```
`help:` recipe — add line after `make list`:
```bash
	@echo "  make status                   состояние сервиса"
```

- [ ] **Step 5: Add smoke scenario**

In `tests/smoke.sh`, **before** the final `echo "OK"`:

```bash
# Сценарий 7: status (без systemd) сообщает что сервис не запущен
output=$("${repo_root}/wgctl" status)
echo "$output" | grep -qF "не запущен" || { echo "FAIL: status didn't report inactive"; exit 1; }

```

(`setup_fixture` not needed — `status` doesn't read state.)

- [ ] **Step 6: Verify**

```bash
chmod +x scripts/status.sh
make lint
make test
```

- [ ] **Step 7: Commit**

```bash
git add scripts/status.sh wgctl scripts/menu.sh Makefile tests/smoke.sh
git commit -m "feat: wgctl status — show service state

Runs 'wg show wg0' when the systemd unit is active; otherwise
prints 'WireGuard сервис не запущен' and exits 0. Smoke covers
the negative branch (no systemd / inactive)."
```

---

## Task 3: `wgctl regenerate <email|username>`

**Files:**
- Create: `scripts/regenerate.sh` (`chmod +x`)
- Modify: `wgctl`
- Modify: `scripts/menu.sh`
- Modify: `Makefile`
- Modify: `tests/smoke.sh`

- [ ] **Step 1: Create `scripts/regenerate.sh`**

```bash
#!/bin/bash
# Пересоздать ключи существующего клиента, сохранив его IP.
set -euo pipefail

WORK_DIR="${WORK_DIR:-/etc/wireguard}"

if [ -z "${1:-}" ]; then
    read -r -p "Введите email или username клиента: " ARG
    if [ -z "${ARG}" ]; then
        echo "[#] Пустой ввод. Выход" >&2
        exit 1
    fi
else
    ARG="${1}"
fi

cd "${WORK_DIR}" || exit 1

# найти [Peer]-блок по email или username (по префиксу до @)
if [[ "${ARG}" == *@* ]]; then
    PEER_LINE=$(grep -F "[Peer] # ${ARG}" wg0.conf)
else
    PEER_LINE=$(grep -E "^\[Peer\] # ${ARG}@" wg0.conf)
fi

MATCHES=$(echo -n "${PEER_LINE}" | grep -c .)
if [[ "${MATCHES}" -eq 0 ]]; then
    echo "[#] Клиент '${ARG}' не найден в wg0.conf. Выход" >&2
    exit 1
fi
if [[ "${MATCHES}" -gt 1 ]]; then
    echo "[#] Найдено несколько клиентов по '${ARG}'. Уточните:" >&2
    echo "${PEER_LINE}" >&2
    exit 1
fi

EMAIL=$(echo "${PEER_LINE}" | awk -F '# ' '{print $2}')
userName=$(echo "${EMAIL}" | awk -F "@" '{print $1}')

# извлечь существующий CLIENT_IP из его [Peer]-блока
CLIENT_IP=$(awk -v target="[Peer] # ${EMAIL}" '
    $0 == target { found = 1; next }
    found && /^AllowedIPs = / { print $3; exit }
    found && /^\[/ { exit }
' wg0.conf)

if [ -z "${CLIENT_IP}" ]; then
    echo "[#] Не удалось извлечь AllowedIPs для ${EMAIL}. Выход" >&2
    exit 1
fi

echo "Пересоздаём ключи для ${userName} (${EMAIL}), сохраняем IP ${CLIENT_IP}"

# shellcheck source=/dev/null
. "${WORK_DIR}/state.env"

# новые ключи
CLIENT_PRESHARED_KEY=$( wg genpsk )
CLIENT_PRIVKEY=$( wg genkey )
CLIENT_PUBLIC_KEY=$( echo "${CLIENT_PRIVKEY}" | wg pubkey )

read -r SERVER_PUBLIC_KEY < ./server.pub

# удалить старый [Peer]-блок
awk -v target="[Peer] # ${EMAIL}" '
    $0 == target { skip = 1; next }
    skip && /^$/ { skip = 0; next }
    skip && /^\[/ { skip = 0; print; next }
    skip { next }
    { print }
' wg0.conf > wg0.conf.tmp && mv wg0.conf.tmp wg0.conf

# добавить новый [Peer]-блок с теми же AllowedIPs
cat >> ./wg0.conf <<_EOF_

[Peer] # ${EMAIL}
PublicKey = ${CLIENT_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = ${CLIENT_IP}
_EOF_

# перезаписать клиентские файлы
mkdir -p "./clients/${userName}"
PRESHARED_KEY=".preshared"
PRIV_KEY=".key"
PUB_KEY=".pub"
ALLOWED_IP="0.0.0.0/0"

echo "${CLIENT_PRESHARED_KEY}" > "./clients/${userName}/${userName}${PRESHARED_KEY}"
echo "${CLIENT_PRIVKEY}" > "./clients/${userName}/${userName}${PRIV_KEY}"
echo "${CLIENT_PUBLIC_KEY}" > "./clients/${userName}/${userName}${PUB_KEY}"

cat > "./clients/${userName}/${userName}.conf" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVKEY}
Address = ${CLIENT_IP}
DNS = ${DNS}

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = ${ALLOWED_IP}
Endpoint = ${ENDPOINT}
PersistentKeepalive=25
EOF

# применить wg0.conf без обрыва активных туннелей
if command -v systemctl >/dev/null && systemctl is-active --quiet wg-quick@wg0; then
    wg syncconf wg0 <(wg-quick strip wg0)
fi

# вывести QR на экран
qrencode -t ansiutf8 < "./clients/${userName}/${userName}.conf"

echo "# Конфиг ${userName}.conf"
cat "./clients/${userName}/${userName}.conf"

# сохранить QR в PNG
qrencode -t png -o "./clients/${userName}/${userName}.png" < "./clients/${userName}/${userName}.conf"
```

- [ ] **Step 2: Add `regenerate` to `wgctl`**

Case-arm **before** `menu)`:
```bash
    regenerate)     "${SCRIPTS}/regenerate.sh" "$@" ;;
```
`usage()`:
```
  regenerate <email>   Пересоздать ключи клиента, сохранив IP
```

- [ ] **Step 3: Add menu item to `scripts/menu.sh`**

Heredoc, **before** `q)`:
```
  8) Пересоздать ключи клиента
```
Case:
```bash
        8) read -r -p "Email или username: " arg || continue; "${WGCTL}" regenerate "${arg}" ;;
```

- [ ] **Step 4: Add `regenerate` target to `Makefile`**

`.PHONY:` — append `regenerate`. Rule:
```makefile
regenerate: ; ./wgctl regenerate "$(EMAIL)"
```
`help:` recipe — add after admin section:
```bash
	@echo "  make regenerate EMAIL=u@x.com пересоздать ключи клиента"
```

- [ ] **Step 5: Add smoke scenario**

In `tests/smoke.sh`, **before** the final `echo "OK"`:

```bash
# Сценарий 8: regenerate сохраняет IP, меняет PublicKey
setup_fixture "$d"
# в fixture у bob PublicKey=BBB, AllowedIPs=10.8.8.3/32 — нужен server.pub
echo "FAKEFAKEFAKE" > "$d/server.pub"
WORK_DIR="$d" "${repo_root}/wgctl" regenerate bob >/dev/null 2>&1 || true
# проверить что bob всё ещё на 10.8.8.3 и его старый PublicKey ушёл
grep -A 3 'bob@example.com' "$d/wg0.conf" | grep -qF "10.8.8.3/32" \
    || { echo "FAIL: regenerate lost bob's IP"; exit 1; }
grep -A 3 'bob@example.com' "$d/wg0.conf" | grep -qF "PublicKey = BBB" \
    && { echo "FAIL: regenerate kept old PublicKey"; exit 1; }

```

Note: `regenerate` calls `wg genkey` / `wg genpsk` / `qrencode` which may not be available on the CI runner (Ubuntu image has them; macOS may not). The smoke uses `|| true` after the invocation and asserts on the side-effects in `wg0.conf` — so we tolerate the binary missing as long as the wg0.conf rewrite has happened. **If `wg` is not installed locally, this scenario will fail silently — that's a known limitation.** Note this in the task report.

Actually — to be safe, **skip the scenario** if `wg` is missing:

```bash
if command -v wg >/dev/null; then
    # Сценарий 8: regenerate сохраняет IP, меняет PublicKey
    setup_fixture "$d"
    echo "FAKEFAKEFAKE" > "$d/server.pub"
    WORK_DIR="$d" "${repo_root}/wgctl" regenerate bob >/dev/null 2>&1
    grep -A 3 'bob@example.com' "$d/wg0.conf" | grep -qF "10.8.8.3/32" \
        || { echo "FAIL: regenerate lost bob's IP"; exit 1; }
    if grep -A 3 'bob@example.com' "$d/wg0.conf" | grep -qF "PublicKey = BBB"; then
        echo "FAIL: regenerate kept old PublicKey"
        exit 1
    fi
fi
```

Ubuntu CI has `wireguard-tools` after `apt install` in the workflow — but the workflow as it stands does not `apt install` anything. Add `apt-get install -y wireguard-tools qrencode` to the CI workflow before the smoke step. This is the only meaningful CI change in Wave 3.

- [ ] **Step 6: Update CI workflow**

Edit `.github/workflows/ci.yml`. Before the `smoke tests` step, insert:

```yaml
      - name: install wg + qrencode
        run: sudo apt-get update && sudo apt-get install -y wireguard-tools qrencode
```

- [ ] **Step 7: Verify**

```bash
chmod +x scripts/regenerate.sh
make lint
make test
```

On macOS, scenario 8 will skip if `wg` is not present (likely). On Linux CI, it should run end-to-end.

- [ ] **Step 8: Commit**

```bash
git add scripts/regenerate.sh wgctl scripts/menu.sh Makefile tests/smoke.sh .github/workflows/ci.yml
git commit -m "feat: wgctl regenerate — rotate keys, keep IP

Re-generates client keys (privkey, pubkey, preshared) and overwrites
the client's conf/key/pub/preshared/png. The [Peer] block in
wg0.conf is replaced (same AllowedIPs), and wg syncconf reapplies.

CI workflow now installs wireguard-tools + qrencode for the new
smoke scenario."
```

---

## Task 4: `wgctl export <email|username>`

**Files:**
- Create: `scripts/export.sh` (`chmod +x`)
- Modify: `wgctl`
- Modify: `scripts/menu.sh`
- Modify: `Makefile`
- Modify: `tests/smoke.sh`

- [ ] **Step 1: Create `scripts/export.sh`**

```bash
#!/bin/bash
# Вывести сохранённый конфиг клиента + QR.
set -euo pipefail

WORK_DIR="${WORK_DIR:-/etc/wireguard}"

if [ -z "${1:-}" ]; then
    read -r -p "Введите email или username клиента: " ARG
    if [ -z "${ARG}" ]; then
        echo "[#] Пустой ввод. Выход" >&2
        exit 1
    fi
else
    ARG="${1}"
fi

# из email достаём local-part
if [[ "${ARG}" == *@* ]]; then
    userName=$(echo "${ARG}" | awk -F "@" '{print $1}')
else
    userName="${ARG}"
fi

cd "${WORK_DIR}" || exit 1

CONF="./clients/${userName}/${userName}.conf"

if [ ! -f "${CONF}" ]; then
    echo "[#] Конфиг ${CONF} не найден" >&2
    exit 1
fi

if command -v qrencode >/dev/null; then
    qrencode -t ansiutf8 < "${CONF}"
fi

echo "# Конфиг ${userName}.conf"
cat "${CONF}"
```

- [ ] **Step 2: Add `export` to `wgctl`**

Case-arm **before** `menu)`:
```bash
    export)         "${SCRIPTS}/export.sh" "$@" ;;
```
`usage()`:
```
  export <email>       Вывести сохранённый конфиг клиента + QR
```

- [ ] **Step 3: Add menu item to `scripts/menu.sh`**

Heredoc, **before** `q)`:
```
  9) Экспорт конфига клиента
```
Case:
```bash
        9) read -r -p "Email или username: " arg || continue; "${WGCTL}" export "${arg}" ;;
```

- [ ] **Step 4: Add `export` target to `Makefile`**

`.PHONY:` — append `export`. Rule:
```makefile
export:    ; ./wgctl export "$(EMAIL)"
```
`help:` recipe — add line:
```bash
	@echo "  make export EMAIL=u@x.com     вывести сохранённый конфиг"
```

- [ ] **Step 5: Add smoke scenario**

In `tests/smoke.sh`, **before** the final `echo "OK"`:

```bash
# Сценарий 9: export выводит сохранённый конфиг
setup_fixture "$d"
mkdir -p "$d/clients/alice"
cat > "$d/clients/alice/alice.conf" <<'CONF'
[Interface]
PrivateKey = ALICEPRIV
Address = 10.8.8.2/32
CONF
output=$(WORK_DIR="$d" "${repo_root}/wgctl" export alice 2>/dev/null)
echo "$output" | grep -qF "ALICEPRIV" || { echo "FAIL: export missing content"; exit 1; }
echo "$output" | grep -qF "10.8.8.2/32" || { echo "FAIL: export missing address"; exit 1; }

```

- [ ] **Step 6: Verify**

```bash
chmod +x scripts/export.sh
make lint
make test
```

- [ ] **Step 7: Commit**

```bash
git add scripts/export.sh wgctl scripts/menu.sh Makefile tests/smoke.sh
git commit -m "feat: wgctl export — show saved client config + QR

Reads ./clients/<user>/<user>.conf and prints it. QR is rendered
via qrencode when available; absent qrencode degrades gracefully
to printing only the conf."
```

---

## Task 5: Update README + CONTRIBUTING

**Files:**
- Modify: `README.md`
- Modify: `CONTRIBUTING.md`

- [ ] **Step 1: Extend the «Команды» table in `README.md`**

Add four rows to the existing wgctl command table, after `wgctl uninstall`:

```markdown
| `wgctl list` | Показать таблицу клиентов (email, IP, public key) из `wg0.conf`. |
| `wgctl status` | Показать `wg show wg0` если сервис активен, иначе сообщить что сервис не запущен. |
| `wgctl regenerate <email\|username>` | Пересоздать ключи клиента (новые priv/pub/preshared), сохранив его IP. Обновляет `wg0.conf` и `./clients/<user>/`. |
| `wgctl export <email\|username>` | Вывести сохранённый `./clients/<user>/<user>.conf` + QR без пересоздания. |
```

- [ ] **Step 2: Extend the «Makefile» cheatsheet in `README.md`**

Replace the cheatsheet block with the full set of admin + dev targets:

```sh
sudo make install                # полная свежая установка
sudo make add EMAIL=u@example.com
sudo make remove EMAIL=u@example.com
sudo make regenerate EMAIL=u@example.com
sudo make export EMAIL=u@example.com
sudo make list                   # таблица клиентов
sudo make status                 # состояние сервиса
sudo make reset
sudo make uninstall
make menu                        # TUI

make test                        # ./tests/smoke.sh
make lint                        # shellcheck по всему репо
make help                        # список целей
```

- [ ] **Step 3: Verify**

```bash
make lint
make test
```

- [ ] **Step 4: Commit**

```bash
git add README.md CONTRIBUTING.md
git commit -m "docs: README — document wave 3 commands

Four new wgctl subcommands (list, status, regenerate, export)
and corresponding Makefile targets added to the README tables."
```

(Note: only `README.md` actually changes — CONTRIBUTING already says "new subcommands go in wgctl + menu + Makefile", which still holds. If you don't end up editing CONTRIBUTING, that's fine — adjust the `git add` accordingly.)

---

## Task 6: Push and verify CI

- [ ] **Step 1: Final cross-cutting checks**

```bash
git log --oneline origin/master..HEAD
make lint
make test
```

Expected: 6 commits (Tasks 1–5 plus the design doc and plan), both make targets green.

- [ ] **Step 2: Push**

```bash
git push origin master
```

- [ ] **Step 3: Watch CI**

```bash
gh run list --branch master --limit 1
```

Wait for `completed success`. If it fails, investigate (`gh run view <id> --log-failed`) before declaring Wave 3 done.

---

## What stays unchanged

- Existing 7 wgctl commands (install/add/remove/reset/uninstall/menu/help) — behaviour identical.
- `scripts/install.sh`, `scripts/add-client.sh`, `scripts/remove-client.sh`, `scripts/reset.sh`, `scripts/uninstall.sh`, `scripts/detect-wan.sh`, `scripts/initial.sh` — not touched.
- `state.env` format — same fields, same writers.
- `wg0.conf` format — same `[Peer] # email` convention.
