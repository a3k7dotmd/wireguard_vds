# Волна 3: подкоманды `list`, `status`, `regenerate`, `export`

**Дата:** 2026-05-20
**Статус:** утверждён к реализации
**Предыдущая волна:** [wave 2](./2026-05-20-restructure-wave2-design.md) (выполнена, на master)
**Последняя в серии.**

## Контекст

После волн 1+2 у скриптов есть единая точка входа и аккуратный `state.env`, но функционал по-прежнему ограничен «установить/добавить/удалить/сбросить/снести». На практике админу нужно ещё четыре вещи:

- **`list`** — посмотреть, кто сейчас в `wg0.conf` (текущий способ — `grep '\[Peer\]' /etc/wireguard/wg0.conf -A 3`).
- **`status`** — глянуть состояние сервиса и активные сессии (`wg show wg0`).
- **`regenerate`** — пересоздать ключи клиенту (после компрометации устройства), сохранив за ним тот же IP.
- **`export`** — снова получить QR-код и конфиг ранее созданного клиента, не пересоздавая ключи.

Волна 3 добавляет четыре подкоманды `wgctl`. Существующие команды не меняются.

## Архитектура

Никаких новых концепций. Каждая фича — отдельный скрипт в `scripts/`, добавляемый в case-arm `wgctl`, пункт `scripts/menu.sh`, цель `Makefile`. Структура задана волной 1 и не нуждается в правках.

### `scripts/list.sh`

Читает `wg0.conf`, выводит таблицу через awk:

```
EMAIL                          IP                 PUBLIC KEY
─────                          ──                 ──────────
alice@example.com              10.8.8.2/32        AAAA...
bob@example.com                10.8.8.3/32        CCCC...
```

Парсинг состоит из накопления `email` из строки `[Peer] # email`, `pubkey` из `PublicKey = ...`, `ip` из `AllowedIPs = ...`, и печати тройки на следующем `AllowedIPs`. `PrivateKey` в `[Interface]` не путает парсер, потому что фильтр стартует только при встрече `[Peer]`-маркера.

Не требует root для тестирования (только читает `wg0.conf`). Параметризуется через `WORK_DIR` для smoke-тестов.

### `scripts/status.sh`

```bash
if command -v systemctl >/dev/null && systemctl is-active --quiet wg-quick@wg0; then
    wg show wg0
else
    echo "WireGuard сервис не запущен"
fi
```

Smoke-тестируется по «негативной» ветке (на CI/macOS нет systemctl или нет активного wg) — должна напечатать «WireGuard сервис не запущен» и выйти с кодом 0.

### `scripts/regenerate.sh`

Самый сложный из четырёх. Workflow:

1. Аргумент: email или username. Найти `[Peer]`-блок по тому же шаблону, что в `remove-client.sh` (полный email или `username@*` префикс).
2. Извлечь существующий `AllowedIPs` (= `CLIENT_IP`) из найденного блока.
3. Сгенерировать новые `CLIENT_PRESHARED_KEY`, `CLIENT_PRIVKEY`, `CLIENT_PUBLIC_KEY`.
4. Удалить старый `[Peer]`-блок awk'ом (точно как в `remove-client.sh`).
5. Добавить новый `[Peer]`-блок с новыми ключами и тем же `CLIENT_IP`.
6. `. state.env` для `ENDPOINT` и `DNS`. Перезаписать `./clients/${userName}/${userName}.{conf,key,pub,preshared}`.
7. Применить через `wg syncconf` (как в `add-client.sh`/`remove-client.sh`).
8. Вывести QR + содержимое нового конфига + сохранить QR в PNG.

`LAST_USED_IP` **не трогаем** — IP клиента сохраняется.

### `scripts/export.sh`

Тривиальный:

1. Аргумент: email или username. Найти клиента (но проще — просто проверить, существует ли директория `./clients/${userName}`; если нет — ошибка).
2. `cat ./clients/${userName}/${userName}.conf`
3. `qrencode -t ansiutf8 < ./clients/${userName}/${userName}.conf`

Если пользователь дал email с `@`, локальная часть достаётся awk'ом.

## Изменения по wiring

Каждая из четырёх фич, помимо собственного скрипта, требует:

1. **`wgctl`** — case-arm:
   ```
   list)           "${SCRIPTS}/list.sh" ;;
   status)         "${SCRIPTS}/status.sh" ;;
   regenerate)     "${SCRIPTS}/regenerate.sh" "$@" ;;
   export)         "${SCRIPTS}/export.sh" "$@" ;;
   ```
   И добавить строки в `usage()`.

2. **`scripts/menu.sh`** — пункты:
   ```
   6) Список клиентов
   7) Статус WireGuard
   8) Пересоздать ключи клиента
   9) Экспорт конфига клиента
   ```

3. **`Makefile`** — цели:
   ```
   list:        ; ./wgctl list
   status:      ; ./wgctl status
   regenerate:  ; ./wgctl regenerate "$(EMAIL)"
   export:      ; ./wgctl export "$(EMAIL)"
   ```
   Обновить `make help` соответственно.

4. **`README.md`** — раздел «Команды»: добавить четыре строки в таблицу. Раздел «Makefile»: добавить новые цели в cheatsheet.

5. **`tests/smoke.sh`** — новые сценарии:
   - **Сценарий 6** (`list`): три пира в фикстуре → `WORK_DIR=$d wgctl list` → проверить, что вывод содержит все три email и три IP.
   - **Сценарий 7** (`status`): `WORK_DIR=$d wgctl status` без systemd → должно напечатать «WireGuard сервис не запущен», exit 0.
   - **Сценарий 8** (`regenerate`): три пира → `WORK_DIR=$d wgctl regenerate bob` → IP `bob` остаётся, `PublicKey` меняется (сохраняем старое значение, сравниваем).
   - **Сценарий 9** (`export`): сделать `./clients/alice/alice.conf` в фикстуре → `WORK_DIR=$d wgctl export alice` → вывод содержит знакомое содержимое.

## Принципы реализации

- Каждая фича — отдельный коммит, **end-to-end**: новый `scripts/<f>.sh` + case-arm в `wgctl` + пункт в `menu.sh` + цель в `Makefile` + smoke-сценарий. Это даёт чистое поведение каждого коммита: после `git checkout <feat-commit>` фича уже доступна.
- README обновляется отдельным финальным коммитом (документация).
- Каждый скрипт должен быть testable так же, как `remove-client.sh`: `WORK_DIR` через env, `wg syncconf` за `command -v systemctl`.
- Соблюдаем стиль волн 1+2: `${VAR}` в кавычках, `read -r`, `set -euo pipefail`, абсолютные пути через `HERE=$(cd "$(dirname "$0")" && pwd)`, источание `state.env` через `. "${WORK_DIR}/state.env"`.

## Тестирование

`tests/smoke.sh` дорастает с 5 до 9 сценариев. Каждый новый — на одну фичу, fixture аналогична существующей (`setup_fixture` + локальный `wg0.conf` + локальная `clients/`-структура).

`status` тестируется только в «негативной» ветке (без systemd). Полное end-to-end на VM — out of scope, как и в волнах 1+2.

## Что НЕ входит в волну 3

- **`wgctl rotate-server-keys`** — пересоздание серверных ключей (заодно ломает всех клиентов). Соблазнительно, но другая операция. Не делаем.
- **`wgctl rename <old> <new>`** — переименовать клиента. Не делаем.
- **`wgctl edit <email>`** — поправить отдельные поля клиента (DNS, AllowedIPs). Не делаем.
- **Pre-existing баг с пустым `SERVER_PRIVKEY` при повторной установке** (volume 1 review flagged) — отдельный fix, не привязан к волне 3.
- **Параметризация имени интерфейса** (`wg0` хардкод) — отдельный refactor.

## Связь с состоянием проекта

После волны 3 у `wgctl` будет 11 подкоманд:

```
install  add  remove  reset  uninstall  menu  help
list  status  regenerate  export
```

Это уже близко к плотности, при которой манифест команд (один файл-реестр вместо case-arms) начинает окупаться — но порог 20+ команд из брэйншторма не достигнут. Продолжаем хардкодом.
