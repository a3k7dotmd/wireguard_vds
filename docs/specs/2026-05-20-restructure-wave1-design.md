# Волна 1: чистка, реструктуризация, единая точка входа

**Дата:** 2026-05-20
**Статус:** утверждён к реализации
**Следующая волна:** state-refactor (`state.env` + CIDR)
**После неё:** новые подкоманды `list / status / regenerate / export`

## Контекст

К этому моменту репозиторий уже прошёл через волны bug-fix'ов и shellcheck-чистки, есть CI и smoke-тесты. Но сама поверхность остаётся «сырой»: пользователь видит в `ls` семь скриптов с числовыми префиксами (`01-`, `10-`, `11-`, `12-`, `19-`, `20-`, плюс `detect_wan.sh`), `wireguard-aws.code-workspace` от чужого автора, закомментированный мёртвый PostUp в `install.sh`, смесь русских и английских комментариев. Точкой входа де-факто служит сам список файлов — это не «профессиональный вид».

Цель волны 1: дать **одну явную точку входа** (`./wgctl <команда>` или интерактивное меню), убрать визуальный шум, унифицировать комментарии. Без изменения формата хранения состояния и без новых фич — это разделено на отдельные волны.

## Архитектура

Три слоя, одна логика:

```
┌───────────────────────────────────────────────────────────┐
│  Makefile           scripts/menu.sh                       │
│  (dev + admin       (TUI — while/read loop)               │
│   прокси)                                                 │
└────────┬────────────────────┬─────────────────────────────┘
         │                    │
         └────── ./wgctl ─────┘
                    │
                    │  case <cmd> in ... esac
                    │
                    ▼
              scripts/*.sh        ← ядро (источник истины)
```

- **`scripts/`** — единственное место, где живёт реальная логика.
- **`wgctl`** — case-диспетчер. Парсинг аргументов **только здесь**, ниже его нет; ядро получает уже разобранные параметры.
- **`scripts/menu.sh`** не знает про `scripts/*.sh`, он зовёт `./wgctl <cmd>`.
- **`Makefile`** для admin-целей проксирует в `./wgctl`, для dev (`test`, `lint`) идёт прямо в `./tests/smoke.sh` и `shellcheck`.

Никакого тройного дублирования парсинга, никаких трёх параллельных интерфейсов к одной логике.

## Изменения по файлам

### Чистка
- Удалить `wireguard-aws.code-workspace` (VSCode-workspace конкретного автора).
- Расширить `.gitignore`: добавить `*.bak`, `*.swp`, `.idea/`, `.vscode/`, `*.tmp`.
- В `scripts/install.sh` удалить строку `#PostUp = wg set %i private-key <(pass wg/keys/%i.key) # read man 1 pass` (мёртвый альтернативный путь).
- В `scripts/uninstall.sh` удалить строку `#yes | apt autoremove software-properties-common` (закомментированный код).

### Переезд и переименование
Семь скриптов переезжают в `scripts/` с одновременным переименованием. Числовые префиксы исчезают — порядок выражает диспетчер.

| было | стало |
|---|---|
| `01-initial.sh` | `scripts/initial.sh` |
| `10-install.sh` | `scripts/install.sh` |
| `11-add-client.sh` | `scripts/add-client.sh` |
| `12-remove-client.sh` | `scripts/remove-client.sh` |
| `19-reset.sh` | `scripts/reset.sh` |
| `20-remove.sh` | `scripts/uninstall.sh` |
| `detect_wan.sh` | `scripts/detect-wan.sh` |

`20-remove.sh` переименован в `uninstall.sh`, чтобы не путать с `remove-client.sh`. `detect_wan.sh` приведён к kebab-case ради консистентности с остальными.

### Скрытый баг по пути
В нынешнем `10-install.sh:66` после `cd /etc/wireguard` идёт `./detect_wan.sh`. Это вызывает скрипт **из текущей директории**, которая уже не та, где лежит репо. Скрипт никто не копирует в `/etc/wireguard`, так что вызов работает только если пользователь случайно запустил `01-initial.sh` находясь в самом `/etc/wireguard` (что бывает не у всех). При переезде это чиним абсолютным путём:
```bash
HERE=$(cd "$(dirname "$0")" && pwd)
# ... после cd "${WORK_DIR}" ...
"${HERE}/detect-wan.sh"
```
То же для `scripts/initial.sh` — он зовёт `uninstall.sh`, `install.sh`, `add-client.sh` через `${HERE}/`, а не через `./`.

### Новые файлы

#### `wgctl` (в корне)

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

#### `scripts/menu.sh`

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

#### `Makefile`

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

### Комментарии

Все `#`-комментарии в скриптах приводятся к **русскому**, попутно чинятся очевидные typos. `echo`-сообщения (`# Reseting`, `# Removing`, `Username is ...` и т.п.) **не трогаем** — это runtime UX, и менять его в этой волне не входит.

Конкретные правки (неполный список, для ориентира — фактический проход по каждому файлу):
- `# work direcrory` → `# рабочая директория`
- `# разрешить перенаправлени пакетов` → `# разрешить перенаправление пакетов`
- `# change default umask` → `# дефолтный umask`
- `# generate server keys` → `# сгенерировать серверные ключи`
- `#set endpoit — wan server ip's` → `# определить endpoint — внешний IP сервера`
- `# We read from the input parameter the name of the client` → `# имя клиента из аргумента или интерактивного ввода`
- `# Apply updated wg0.conf without dropping active peers.` → `# применить wg0.conf без обрыва активных туннелей`
- и т.д. по всем скриптам, включая `tests/smoke.sh` (`# Scenario 1: ...` → `# Сценарий 1: ...`).

### Подгонки сопутствующих файлов

- **`tests/smoke.sh`**: путь `${repo_root}/12-remove-client.sh` → `${repo_root}/scripts/remove-client.sh`. Комментарии — на русский. Добавлен один новый сценарий: «удаление через `wgctl remove`», чтобы зафиксировать что диспетчер действительно проксирует.
- **`.github/workflows/ci.yml`**: команда shellcheck → `shellcheck -S style scripts/*.sh tests/*.sh wgctl`.
- **`README.md`**: раздел «Скрипты» заменён на «Команды `wgctl`» + «Цели `Makefile`». Быстрый старт → `sudo make install` (с альтернативой `sudo ./wgctl install`). Раздел «Разработка» → `make test` и `make lint`.
- **`CONTRIBUTING.md`**: команды перед коммитом → `make lint && make test`.

## Тестирование

Локально и в CI:
- `make lint` — shellcheck по `scripts/*.sh tests/*.sh wgctl`, должен быть чист.
- `make test` — `./tests/smoke.sh`, все сценарии зелёные (старые после подгонки путей + новый сценарий `wgctl remove`).

End-to-end на Ubuntu-VM (вне scope локальной верификации, но проверочный сценарий после реализации):
```
sudo make install                 # = sudo ./wgctl install
sudo make add EMAIL=bob@x
sudo make remove EMAIL=bob
sudo ./wgctl menu                 # глянуть TUI
```

## Что НЕ входит в волну 1

- **Формат хранения состояния** — `*.var`-файлы и формат подсети с trailing dot остаются как есть. Это волна 2 (`state.env` + CIDR).
- **Новые подкоманды** — `list`, `status`, `regenerate`, `export`. Это волна 3.
- **`echo`-сообщения** — не переводятся и не переписываются.
- **Переименование скриптов внутри `scripts/` ещё раз** (например, `initial.sh` → `bootstrap.sh`) — нет, имена выбраны окончательно.
- **Прямые ссылки на старые `01-*.sh`** в README/командах в комментариях/wild references — в README они обновляются, но если кто-то имеет внешний `bash <(curl)`-runner на эти файлы, у него сломается. Этим репо пользуются маленький круг людей, риск приемлем.

## Связь с будущими волнами

- Волна 2 (state-refactor) работает уже внутри `scripts/install.sh`, `scripts/add-client.sh`, `scripts/reset.sh` — структура волны 1 даёт ей готовое место.
- Волна 3 (фичи) добавляет файлы вида `scripts/list.sh`, `scripts/status.sh`, `scripts/regenerate.sh`, `scripts/export.sh` и case-arm в `wgctl`. Каркас уже готов.
