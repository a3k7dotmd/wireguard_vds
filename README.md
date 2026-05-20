# wireguard_vds

[![CI](https://github.com/blackden/wireguard_vds/actions/workflows/ci.yml/badge.svg)](https://github.com/blackden/wireguard_vds/actions/workflows/ci.yml)

Набор bash-скриптов для автоматической установки и настройки WireGuard на сервере с Ubuntu Server 18.04 и новее. Поднимает сервер, генерирует серверные ключи, выдаёт клиентские конфиги (с QR-кодом для мобильных) и умеет добавлять/удалять клиентов на лету.

## Требования

- Ubuntu Server 18.04 или новее.
- Права root (все скрипты выполняются через `sudo`).
- Доступ в интернет (для `apt install` и определения внешнего IP).

## Быстрый старт

```sh
git clone https://github.com/blackden/wireguard_vds.git
cd wireguard_vds
sudo make install
```

`make install` (то же, что `sudo ./wgctl install`) снесёт предыдущую установку WireGuard (если была), поставит свежую и сразу создаст первого клиента. На выходе — QR-код в терминале и `.conf`-файл для устройства клиента.

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

## Разработка

Перед коммитом локально прогоните то, что делает CI:

```sh
make lint
make test
```

Smoke-тесты создают временный `wg0.conf` в `mktemp -d` и проверяют поведение `scripts/remove-client.sh` на нескольких сценариях — не требуют ни root, ни поднятого WireGuard, идут за миллисекунды.

Подробнее — см. [CONTRIBUTING.md](CONTRIBUTING.md). Если нашли уязвимость — [SECURITY.md](SECURITY.md).

## Лицензия

MIT, см. [LICENSE](LICENSE).

## Авторы

- Fedorov Tech
- Denis Fedorov

Форк основан на [pprometey/wireguard_aws](https://github.com/pprometey/wireguard_aws).
