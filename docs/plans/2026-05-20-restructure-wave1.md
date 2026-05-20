# Wave 1: cleanup + restructure + wgctl Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide one explicit entry point (`./wgctl` + `Makefile` + interactive menu) over a clean `scripts/` directory, translate code-level comments to Russian, drop dead files and code. Behaviour-preserving (smoke + lint stay green at every step).

**Architecture:** Three-layer surface — `scripts/` holds the actual work; `wgctl` is a single case-dispatcher in repo root; `scripts/menu.sh` (TUI) and `Makefile` (admin proxy + dev targets) are thin wrappers over `./wgctl`. No argument parsing duplication.

**Tech Stack:** bash, GNU make, shellcheck, awk. No new external deps.

**Reference:** [docs/specs/2026-05-20-restructure-wave1-design.md](../specs/2026-05-20-restructure-wave1-design.md)

---

## Task 1: Move and rename scripts into `scripts/`, update test/CI paths

This is the structural big-bang. Done in one commit so the repo never enters a half-moved state. No internal logic of scripts changes here — only their location, filenames, and the few path references in test/CI.

**Files:**
- Rename: `01-initial.sh` → `scripts/initial.sh`
- Rename: `10-install.sh` → `scripts/install.sh`
- Rename: `11-add-client.sh` → `scripts/add-client.sh`
- Rename: `12-remove-client.sh` → `scripts/remove-client.sh`
- Rename: `19-reset.sh` → `scripts/reset.sh`
- Rename: `20-remove.sh` → `scripts/uninstall.sh`
- Rename: `detect_wan.sh` → `scripts/detect-wan.sh`
- Modify: `tests/smoke.sh` (single path reference)
- Modify: `.github/workflows/ci.yml` (shellcheck glob)

- [ ] **Step 1: Create scripts/ and move all 7 files in one git operation**

```bash
mkdir -p scripts
git mv 01-initial.sh        scripts/initial.sh
git mv 10-install.sh        scripts/install.sh
git mv 11-add-client.sh     scripts/add-client.sh
git mv 12-remove-client.sh  scripts/remove-client.sh
git mv 19-reset.sh          scripts/reset.sh
git mv 20-remove.sh         scripts/uninstall.sh
git mv detect_wan.sh        scripts/detect-wan.sh
```

Verify: `ls scripts/` lists exactly those 7 files.

- [ ] **Step 2: Update path reference in `tests/smoke.sh`**

The smoke test currently invokes `12-remove-client.sh` from repo root. After the rename it must call the new path. There is exactly **one** producing reference (the script path constant is used four times via the same variable; we change the variable).

Find the line `"${repo_root}/12-remove-client.sh"` (appears in 4 invocations — `bob`, `carol@example.com`, `alice`, `nobody`). Replace each occurrence's path to `"${repo_root}/scripts/remove-client.sh"`.

- [ ] **Step 3: Update shellcheck glob in `.github/workflows/ci.yml`**

The current glob `*.sh tests/*.sh` no longer matches anything in the root after the move. Change the `shellcheck` step to:

```yaml
      - name: shellcheck
        run: shellcheck -S style scripts/*.sh tests/*.sh
```

(`wgctl` will be added to this glob in Task 2; for now keep it as `scripts/*.sh tests/*.sh` so the workflow is internally consistent after Task 1 commits.)

- [ ] **Step 4: Verify lint and smoke still pass**

```bash
shellcheck -S style scripts/*.sh tests/*.sh
./tests/smoke.sh
```

Expected:
- shellcheck: no output, exit 0.
- smoke: prints `OK`, exit 0.

If smoke fails, the most likely cause is a missed path update in `tests/smoke.sh` — check that no string `12-remove-client.sh` remains: `grep -n '12-remove-client' tests/smoke.sh` must return nothing.

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor: move scripts into scripts/ and drop numeric prefixes

Sets up the layout the wgctl dispatcher (next commit) will sit on
top of. Renames also resolve a name collision (20-remove.sh and
12-remove-client.sh both being '*remove*'): the former is now
scripts/uninstall.sh.

tests/smoke.sh and .github/workflows/ci.yml updated to reflect the
new paths. No script logic touched."
```

---

## Task 2: Add `wgctl`, `Makefile`, `scripts/menu.sh` (single entry point)

Now that `scripts/` exists, drop the dispatcher and its UX wrappers on top. CI workflow gets `wgctl` added to its shellcheck target in the same commit.

**Files:**
- Create: `wgctl`
- Create: `Makefile`
- Create: `scripts/menu.sh`
- Modify: `.github/workflows/ci.yml` (add `wgctl` to shellcheck glob)

- [ ] **Step 1: Create `wgctl` in repo root**

Exact contents (write the file then `chmod +x`):

```bash
#!/bin/bash
# wgctl — единая точка входа для wireguard_vds.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPTS="${HERE}/scripts"

usage() {
    cat <<'EOF'
Использование: wgctl <команда> [аргументы]

Команды:
  install              Полная установка (uninstall + install + первый клиент)
  add <email>          Добавить клиента
  remove <email>       Удалить клиента (email или username)
  reset                Сбросить настройки и всех клиентов
  uninstall            Полностью снести WireGuard
  menu                 Интерактивное меню (по умолчанию)
  help                 Показать это сообщение
EOF
}

cmd="${1:-menu}"
shift || true

case "${cmd}" in
    install)        "${SCRIPTS}/initial.sh" "$@" ;;
    add)            "${SCRIPTS}/add-client.sh" "$@" ;;
    remove)         "${SCRIPTS}/remove-client.sh" "$@" ;;
    reset)          "${SCRIPTS}/reset.sh" ;;
    uninstall)      "${SCRIPTS}/uninstall.sh" ;;
    menu)           "${SCRIPTS}/menu.sh" ;;
    help|-h|--help) usage ;;
    *)
        echo "wgctl: неизвестная команда '${cmd}'" >&2
        usage >&2
        exit 1
        ;;
esac
```

Make executable:

```bash
chmod +x wgctl
```

- [ ] **Step 2: Create `scripts/menu.sh`**

```bash
#!/bin/bash
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WGCTL="${HERE}/../wgctl"

while true; do
    cat <<'EOF'

=== wgctl ===
  1) Установить (полная установка + первый клиент)
  2) Добавить клиента
  3) Удалить клиента
  4) Сбросить настройки и клиентов
  5) Полностью снести WireGuard
  q) Выход
EOF
    read -r -p "Выбор: " choice
    case "${choice}" in
        1) "${WGCTL}" install ;;
        2) read -r -p "Email: " email; "${WGCTL}" add "${email}" ;;
        3) read -r -p "Email или username: " arg; "${WGCTL}" remove "${arg}" ;;
        4) "${WGCTL}" reset ;;
        5) "${WGCTL}" uninstall ;;
        q|Q|"") exit 0 ;;
        *) echo "Неизвестный выбор: ${choice}" ;;
    esac
done
```

Make executable:

```bash
chmod +x scripts/menu.sh
```

- [ ] **Step 3: Create `Makefile`**

```makefile
SHELL := /bin/bash
.PHONY: help install add remove reset uninstall menu test lint

help:
	@echo "wireguard_vds — Makefile targets"
	@echo
	@echo "  make install                  полная свежая установка"
	@echo "  make add EMAIL=user@x.com     добавить клиента"
	@echo "  make remove EMAIL=user@x.com  удалить клиента"
	@echo "  make reset                    сбросить настройки"
	@echo "  make uninstall                снести wireguard"
	@echo "  make menu                     интерактивное меню"
	@echo
	@echo "  make test                     прогнать smoke tests"
	@echo "  make lint                     прогнать shellcheck"

install:   ; ./wgctl install
add:       ; ./wgctl add "$(EMAIL)"
remove:    ; ./wgctl remove "$(EMAIL)"
reset:     ; ./wgctl reset
uninstall: ; ./wgctl uninstall
menu:      ; ./wgctl menu

test:      ; ./tests/smoke.sh
lint:      ; shellcheck -S style scripts/*.sh tests/*.sh wgctl
```

(Indentation in recipe lines is a **literal TAB**, not spaces — make is strict about this.)

- [ ] **Step 4: Update `.github/workflows/ci.yml` to include `wgctl`**

Change the shellcheck step to:

```yaml
      - name: shellcheck
        run: shellcheck -S style scripts/*.sh tests/*.sh wgctl
```

- [ ] **Step 5: Run lint via Makefile (cross-checks Makefile, wgctl, menu.sh all parse)**

```bash
make lint
make test
```

Expected:
- `make lint` runs the shellcheck command and exits 0 with no output.
- `make test` runs `./tests/smoke.sh` and prints `OK`.

- [ ] **Step 6: Smoke-test `wgctl help` and unknown command manually**

```bash
./wgctl help
./wgctl bogus
echo "exit=$?"
```

Expected:
- `help` prints the usage block and exits 0.
- `bogus` prints `wgctl: неизвестная команда 'bogus'` to stderr + usage to stderr, exits 1.

- [ ] **Step 7: Commit**

```bash
git add wgctl Makefile scripts/menu.sh .github/workflows/ci.yml
git commit -m "feat: add wgctl dispatcher, Makefile, interactive menu

Single entry point over scripts/. wgctl is a case-dispatcher in
repo root; scripts/menu.sh is a TUI that calls ./wgctl <cmd>;
Makefile proxies admin targets to ./wgctl and runs dev targets
(test/lint) directly. No duplication of argument parsing.

CI workflow now lints wgctl as well."
```

---

## Task 3: Fix detect-wan.sh contract so install.sh actually receives the WAN interface name

**Pre-existing bug (not introduced by Wave 1, but worth fixing while we are in this area):** the current `scripts/detect-wan.sh` runs in its own subshell when invoked as `./detect-wan.sh`. The `read`-prompted value `WAN_INTERFACE_NAME` is set **only inside that subshell** and lost on exit. Consequently, `scripts/install.sh` substitutes an empty `${WAN_INTERFACE_NAME}` into the heredoc, producing a broken `PostUp ... -o  -j MASQUERADE;` line in `wg0.conf.def`.

Fix by inverting the contract: `detect-wan.sh` prints exactly one line (the chosen interface) to stdout, sends the prompt to stderr (so it remains visible to the operator but does not pollute the captured value). `install.sh` captures the result with `$(...)`.

Plus the design-doc cosmetic fix: explicit absolute path so the call works regardless of cwd.

**Files:**
- Modify: `scripts/detect-wan.sh`
- Modify: `scripts/install.sh`
- Modify: `scripts/initial.sh` (orchestrator path fix — was `./20-remove.sh && ./10-install.sh && ./11-add-client.sh`)

- [ ] **Step 1: Rewrite `scripts/detect-wan.sh`**

Full new contents:

```bash
#!/bin/bash
# Выводит имя WAN-интерфейса на stdout. Подсказка/prompt идут в stderr,
# чтобы вызывающая сторона могла захватить результат через $(...).
set -euo pipefail

default=$(ip -c route | grep "default" | awk '{print $5}')

# `read` сам по себе пишет prompt в stderr, что нам и нужно.
read -r -p "Имя WAN-интерфейса ([ENTER] = ${default}): " name 1>&2
echo "${name:-${default}}"
```

- [ ] **Step 2: Patch the call in `scripts/install.sh`**

Find the existing block:

```bash
# set wan interface
./detect_wan.sh
```

(or after Task 1 it is `./detect-wan.sh` — the path was already kebab-cased by the move). Replace with:

```bash
# определить WAN-интерфейс
HERE_INSTALL=$(cd "$(dirname "$0")" && pwd)
WAN_INTERFACE_NAME=$("${HERE_INSTALL}/detect-wan.sh")
```

Place this **before** the heredoc that writes `wg0.conf.def` (i.e. the existing position in the file is correct — same line, just replace the body).

The variable `HERE_INSTALL` is scoped to `install.sh` to avoid collision with the `HERE` used inside `wgctl` / `menu.sh`.

- [ ] **Step 3: Patch the orchestrator in `scripts/initial.sh`**

The current contents (after Task 1's rename) are:

```bash
#!/bin/bash

echo "# Installing Wireguard"

./20-remove.sh && \

./10-install.sh && \

./11-add-client.sh

echo "# Wireguard installed"
```

Those `./` paths are broken (the targets no longer exist under those names). Replace whole body with:

```bash
#!/bin/bash
# Полный сценарий первой установки: снести предыдущую установку,
# поставить заново, выдать конфиг первому клиенту.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)

echo "# Installing WireGuard"

"${HERE}/uninstall.sh"
"${HERE}/install.sh"
"${HERE}/add-client.sh"

echo "# WireGuard installed"
```

Notice: dropped the `&&`-chain in favour of `set -euo pipefail` (any failure aborts naturally), and switched to absolute paths.

- [ ] **Step 4: Verify lint and smoke still pass**

```bash
make lint
make test
```

Expected: both green. (Smoke tests cover `remove-client.sh` only — they don't exercise the install path, so we can't end-to-end-test the WAN fix locally without a VM. The lint pass is the floor.)

- [ ] **Step 5: Commit**

```bash
git add scripts/detect-wan.sh scripts/install.sh scripts/initial.sh
git commit -m "fix: detect-wan.sh propagates choice; initial.sh uses absolute paths

Pre-existing bug: detect_wan.sh set WAN_INTERFACE_NAME inside its
own subshell, so install.sh always rendered an empty interface name
into wg0.conf.def's PostUp line. Inverting the contract: detect-wan
prints the final interface to stdout (prompt to stderr), install.sh
captures via \$(...).

initial.sh paths to its subordinate scripts were also broken by the
rename in the prior commit (still pointed at ./20-remove.sh etc.).
Switched to \${HERE}/... and dropped the && chain in favour of set
-euo pipefail."
```

---

## Task 4: Remove dead commented-out code

**Files:**
- Modify: `scripts/install.sh` (one line)
- Modify: `scripts/uninstall.sh` (one line)

- [ ] **Step 1: Delete the commented `PostUp` line in `scripts/install.sh`**

Find and delete the entire line:

```
#PostUp = wg set %i private-key <(pass wg/keys/%i.key) # read man 1 pass
```

(It sits inside the heredoc that writes `wg0.conf.def`, between `ListenPort = ...` and the live `PostUp = iptables ...` line.)

- [ ] **Step 2: Delete the commented `apt autoremove` line in `scripts/uninstall.sh`**

Find and delete the entire line:

```
#yes | apt autoremove software-properties-common
```

- [ ] **Step 3: Verify lint and smoke still pass**

```bash
make lint
make test
```

Expected: both green.

- [ ] **Step 4: Commit**

```bash
git add scripts/install.sh scripts/uninstall.sh
git commit -m "chore: drop dead commented-out lines

- scripts/install.sh: stale 'PostUp' alternative using the pass(1)
  password store. We're not using pass and there's no signal that
  anyone was about to.
- scripts/uninstall.sh: dead 'apt autoremove software-properties-common'."
```

---

## Task 5: Translate all `#`-comments to Russian and fix typos

`echo`-output (operator-facing runtime messages like `# Reseting`, `Username is ...`) is intentionally left untouched — that's runtime UX, separate concern.

**Files (every script gets a pass):**
- Modify: `scripts/initial.sh`
- Modify: `scripts/install.sh`
- Modify: `scripts/add-client.sh`
- Modify: `scripts/remove-client.sh`
- Modify: `scripts/reset.sh`
- Modify: `scripts/uninstall.sh`
- Modify: `scripts/detect-wan.sh`
- Modify: `scripts/menu.sh`
- Modify: `tests/smoke.sh`
- Modify: `wgctl`

- [ ] **Step 1: Pass through `scripts/install.sh` translating comments**

Apply these exact translations (each is a single-line replacement):

| Найти | Заменить на |
|---|---|
| `# work direcrory` | `# рабочая директория` |
| `# установка wireguard` | (оставить без изменений — уже на русском) |
| `# разрешить перенаправлени пакетов` | `# разрешить перенаправление пакетов` |
| `# перейти в рабочую директорию` | (оставить — уже на русском) |
| `# change default umask` | `# дефолтный umask` |
| `# generate server keys` | `# сгенерировать серверные ключи` |
| `#set endpoit — wan server ip's` | `# определить endpoint — внешний IP сервера` |
| `# set vpn-server vpn address` | `# адрес сервера в VPN-подсети` |
| `# set vpn-server subnet` | `# подсеть VPN` |

After Task 3 the file also gained `# определить WAN-интерфейс` — leave it as-is.

- [ ] **Step 2: Pass through `scripts/add-client.sh`**

| Найти | Заменить на |
|---|---|
| `# work direcrory` | `# рабочая директория` |
| `# We read from the input parameter the name of the client` | `# имя клиента из аргумента или интерактивного ввода` |
| `# Go to the wireguard directory and create a directory structure in which we will store client configuration files` | `# создать директорию для конфига и ключей клиента` |
| `# We get the following client IP address` | `# выделить следующий свободный IP в пуле` |
| `# Create a blank configuration file client` | `# создать клиентский конфиг` |
| `# Add new client data to the Wireguard configuration file` | `# дописать [Peer] в wg0.conf` |
| `# Apply updated wg0.conf without dropping active peers.` | `# применить wg0.conf без обрыва активных туннелей` |
| `# Show QR config to display` | `# вывести QR на экран` |
| `# Show config file` | `# вывести содержимое конфига` |
| `# Save QR config to png file` | `# сохранить QR в PNG` |

- [ ] **Step 3: Pass through `scripts/remove-client.sh`**

| Найти | Заменить на |
|---|---|
| `# Find the matching [Peer] line. Accept either a full email or a bare username.` | `# найти [Peer]-блок по email или username (по префиксу до @)` |

(`remove-client.sh` is otherwise sparse on comments — only that one line needs translation. Verify by `grep -n '^\s*#' scripts/remove-client.sh` and translating any others if found.)

- [ ] **Step 4: Pass through `scripts/reset.sh`**

| Найти | Заменить на |
|---|---|
| `# Delete the folder with customer data` | `# удалить директории клиентов` |
| `# Zero IP counter` | `# обнулить счётчик IP` |
| `# Resetting the server configuration template to default settings` | `# восстановить серверный конфиг из шаблона` |

- [ ] **Step 5: Pass through remaining files**

For each of `scripts/initial.sh`, `scripts/uninstall.sh`, `scripts/detect-wan.sh`, `scripts/menu.sh`, `wgctl`, run:

```bash
grep -n '^\s*#' <file> | grep -v '^\s*#!'
```

If any English `#`-comment appears, translate it in place. Most of these files were newly written in Tasks 2–3 already in Russian, so this is mostly a verification step.

For `tests/smoke.sh`, the existing scenario comments are in English; translate:

| Найти | Заменить на |
|---|---|
| `# Scenario 1: remove middle peer by bare username` | `# Сценарий 1: удалить пира из середины по username` |
| `# Scenario 2: remove last peer by full email` | `# Сценарий 2: удалить последнего пира по полному email` |
| `# Scenario 3: remove first peer` | `# Сценарий 3: удалить первого пира` |
| `# Scenario 4: non-existent peer fails non-destructively` | `# Сценарий 4: отсутствующий пир — ошибка без побочных эффектов` |

- [ ] **Step 6: Verify lint and smoke still pass**

```bash
make lint
make test
```

Expected: both green (comment changes can't break logic, but lint catches accidental edits to live code).

- [ ] **Step 7: Commit**

```bash
git add scripts/ tests/smoke.sh wgctl
git commit -m "style: translate code comments to Russian, fix typos

Echo/printf operator-facing messages are intentionally untouched
(runtime UX, separate concern). Only #-comments converted."
```

---

## Task 6: Delete `wireguard-aws.code-workspace` and extend `.gitignore`

**Files:**
- Delete: `wireguard-aws.code-workspace`
- Modify: `.gitignore`

- [ ] **Step 1: Delete the VSCode workspace file**

```bash
git rm wireguard-aws.code-workspace
```

- [ ] **Step 2: Extend `.gitignore`**

Current contents (single line):

```
CLAUDE.md
```

Replace with:

```
# Локальный гайд для Claude Code — не для репозитория
CLAUDE.md

# Редактор / IDE-мусор
.idea/
.vscode/

# Временные файлы
*.bak
*.swp
*.tmp
```

- [ ] **Step 3: Verify lint and smoke**

```bash
make lint
make test
```

Expected: both green.

- [ ] **Step 4: Commit**

```bash
git add .gitignore wireguard-aws.code-workspace
git commit -m "chore: drop VSCode workspace, broaden .gitignore"
```

---

## Task 7: Update `README.md` and `CONTRIBUTING.md`

**Files:**
- Modify: `README.md` (replace Scripts table with Commands/Make sections, update Quick start)
- Modify: `CONTRIBUTING.md` (update lint/test commands)

- [ ] **Step 1: Rewrite the «Быстрый старт» section in `README.md`**

Locate the existing block:

```markdown
## Быстрый старт

```sh
git clone https://github.com/blackden/wireguard_vds.git
cd wireguard_vds
sudo ./01-initial.sh
```

Скрипт `01-initial.sh` снесёт предыдущую установку WireGuard ...
```

Replace with:

```markdown
## Быстрый старт

```sh
git clone https://github.com/blackden/wireguard_vds.git
cd wireguard_vds
sudo make install
```

`make install` (то же, что `sudo ./wgctl install`) снесёт предыдущую установку WireGuard (если была), поставит свежую и сразу создаст первого клиента. На выходе — QR-код в терминале и `.conf`-файл для устройства клиента.
```

- [ ] **Step 2: Replace the «Скрипты» section with «Команды» + «Makefile»**

Locate the existing table starting with `## Скрипты` and ending before `## Разработка`. Replace the entire block with:

```markdown
## Команды

Единая точка входа — `wgctl`:

| Команда | Что делает |
|---|---|
| `wgctl install` | Полная установка (uninstall + install + первый клиент). |
| `wgctl add <email>` | Добавить клиента. Создаёт ключи, дописывает `[Peer]` в `wg0.conf`, применяет `wg syncconf` (без обрыва активных туннелей), показывает QR. |
| `wgctl remove <email\|username>` | Удалить клиента. Чистит `wg0.conf`, директорию клиента, применяет `wg syncconf`. |
| `wgctl reset` | Удалить всех клиентов, остановить сервер. Установка остаётся. |
| `wgctl uninstall` | Полная деинсталляция: остановка сервиса, `apt remove`, `rm -rf /etc/wireguard`. |
| `wgctl menu` | Интерактивное меню (вызывается без аргументов по умолчанию). |
| `wgctl help` | Справка по командам. |

## Makefile

Удобная обёртка для админских и dev-операций:

```sh
sudo make install                # полная свежая установка
sudo make add EMAIL=u@example.com
sudo make remove EMAIL=u@example.com
sudo make reset
sudo make uninstall
make menu                        # TUI

make test                        # ./tests/smoke.sh
make lint                        # shellcheck по всему репо
make help                        # список целей
```
```

- [ ] **Step 3: Update «Разработка» in `README.md`**

Locate:

```markdown
## Разработка

Перед коммитом локально прогоните то, что делает CI:

```sh
shellcheck -S style *.sh tests/*.sh
./tests/smoke.sh
```
```

Replace with:

```markdown
## Разработка

Перед коммитом локально прогоните то, что делает CI:

```sh
make lint
make test
```
```

(остальной текст раздела — про smoke и ссылки на CONTRIBUTING/SECURITY — оставить как есть).

- [ ] **Step 4: Update `CONTRIBUTING.md`**

Locate the "Перед коммитом" block:

```markdown
## Перед коммитом

Прогоните локально то, что прогонит CI:

```sh
shellcheck -S style *.sh tests/*.sh
./tests/smoke.sh
```
```

Replace the code block:

```sh
make lint
make test
```

Locate the stylistic rules section ("## Стиль") — no changes needed there (`${VAR}`, `read -r`, `cd ... || exit`, shebang) — но добавьте одну строку в список:

```markdown
- Новые подкоманды добавляются в `wgctl` (case-arm) и `scripts/menu.sh` (пункт), плюс в `Makefile`-цель если она admin-уровня. Один новый файл `scripts/<name>.sh` на команду.
```

- [ ] **Step 5: Verify lint and smoke still pass**

```bash
make lint
make test
```

Expected: both green (we touched only Markdown).

- [ ] **Step 6: Commit**

```bash
git add README.md CONTRIBUTING.md
git commit -m "docs: update README and CONTRIBUTING for wgctl + Makefile

- Quick start uses 'sudo make install'.
- Scripts table replaced with Commands (wgctl) + Makefile targets.
- Development section uses 'make lint' / 'make test'.
- CONTRIBUTING mentions where to add a new subcommand."
```

---

## Task 8: Add smoke scenario for `wgctl remove` proxying

The new dispatcher is currently exercised only manually (Task 2 step 6). Lock down that `./wgctl remove <email>` actually proxies to `scripts/remove-client.sh` so a future refactor of `wgctl` can't silently break it.

**Files:**
- Modify: `tests/smoke.sh`

- [ ] **Step 1: Add a new scenario at the end of `tests/smoke.sh`**

Locate the existing final block:

```bash
echo "OK"
```

Insert **before** that line:

```bash
# Сценарий 5: wgctl действительно проксирует remove в scripts/remove-client.sh
setup_fixture "$d"
WORK_DIR="$d" "${repo_root}/wgctl" remove bob >/dev/null
assert_not_contains "$d/wg0.conf" "bob@example.com"
assert_dir_absent   "$d/clients/bob"

```

- [ ] **Step 2: Run smoke to confirm the new scenario passes**

```bash
./tests/smoke.sh
```

Expected: `OK`, exit 0. If it fails with "bob@example.com still present", check that `wgctl` exists and is executable (`ls -l wgctl`), and that the proxy actually invokes `scripts/remove-client.sh` (look for typo in the case arm).

- [ ] **Step 3: Verify lint still passes**

```bash
make lint
```

Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add tests/smoke.sh
git commit -m "test: smoke covers wgctl-remove proxying

Scenario 5 invokes ./wgctl remove bob (instead of
./scripts/remove-client.sh directly) so the dispatcher's case-arm
stays under test."
```

---

## Task 9: Push and verify CI

- [ ] **Step 1: Review the full commit list locally**

```bash
git log --oneline origin/master..HEAD
```

Expected: 8 commits in this order (Tasks 1–8). Each commit message matches the templates above.

- [ ] **Step 2: Push**

```bash
git push origin master
```

- [ ] **Step 3: Watch CI**

Open https://github.com/blackden/wireguard_vds/actions and wait for the workflow on the latest commit. Expected: green within ~1 minute.

- [ ] **Step 4: Sanity check rendered README on GitHub**

Open https://github.com/blackden/wireguard_vds and visually confirm: CI badge green, Quick start uses `sudo make install`, Commands and Makefile sections render correctly, no broken links to LICENSE/CONTRIBUTING/SECURITY.

---

## What stays unchanged

- `wg0.conf` format on the server.
- `*.var` state files (`endpoint.var`, `dns.var`, `vpn_subnet.var`, `last_used_ip.var`) — Wave 2 will consolidate them.
- Runtime `echo` messages.
- LICENSE, SECURITY.md, .editorconfig (already in place).
- All public command behaviour: `install`, `add`, `remove`, `reset`, `uninstall` do the same things they did before, just reachable through a different entry point.

## Failure recovery

Each task ends in a commit. If a task's verification step fails (lint or smoke goes red), revert just that task's working changes (`git checkout -- <files>` for the modified set) and re-do the task from Step 1. Do **not** roll back prior commits — they're independently green by design.

## Self-review checklist (executed during plan writing)

- **Spec coverage:** every bullet in `docs/specs/2026-05-20-restructure-wave1-design.md` maps to a task: cleanup ↔ Tasks 4 + 6; restructure ↔ Tasks 1 + 2; comments ↔ Task 5; path fixes ↔ Task 3; side-file updates ↔ Tasks 1 + 2 + 7; new smoke scenario ↔ Task 8.
- **Placeholders:** none — every step has either exact code or exact commands with expected output.
- **Type/name consistency:** `WAN_INTERFACE_NAME` is set the same way in detect-wan and consumed in install.sh; `HERE` is used in wgctl/menu, `HERE_INSTALL` in install.sh to avoid collision.
- **Spec gap I added:** detect-wan.sh variable-propagation fix is in Task 3 — the spec said «абсолютный путь», I expanded to «абс путь + capture контракт» because the abs-path-only change is meaningless on the broken script. Flagged in the response that introduces this plan.
