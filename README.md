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
sudo ./01-initial.sh
```

Скрипт `01-initial.sh` снесёт предыдущую установку WireGuard (если была), поставит свежую и сразу создаст первого клиента. На выходе — QR-код в терминале и `.conf`-файл для устройства клиента.

## Скрипты

| Скрипт | Что делает |
|---|---|
| `01-initial.sh` | Оркестратор: `20-remove.sh` → `10-install.sh` → `11-add-client.sh`. Полная свежая установка с первым клиентом. |
| `10-install.sh` | Ставит `wireguard-tools`, включает IP-форвардинг, генерирует серверные ключи, спрашивает endpoint / VPN-подсеть / DNS / WAN-интерфейс, создаёт шаблон `wg0.conf.def`. |
| `11-add-client.sh` | Добавляет нового клиента (`sudo ./11-add-client.sh user@example.com`). Создаёт ключи, пишет `[Peer]` в `wg0.conf`, применяет изменения через `wg syncconf` (без обрыва активных туннелей), показывает QR. |
| `12-remove-client.sh` | Удаляет клиента (по email или username). Чистит `wg0.conf`, директорию клиента и применяет изменения через `wg syncconf`. |
| `19-reset.sh` | Удаляет всех клиентов и останавливает WireGuard. Установка остаётся на месте. |
| `20-remove.sh` | Полная деинсталляция: останавливает сервис, сносит пакеты и `/etc/wireguard`. |
| `detect_wan.sh` | Хелпер, который определяет имя WAN-интерфейса по таблице маршрутизации. Вызывается из `10-install.sh`. |

## Разработка

Перед коммитом локально прогоните то, что делает CI:

```sh
shellcheck -S style *.sh tests/*.sh
./tests/smoke.sh
```

Smoke-тесты создают временный `wg0.conf` в `mktemp -d` и проверяют поведение `12-remove-client.sh` на нескольких сценариях — не требуют ни root, ни поднятого WireGuard, идут за миллисекунды.

Подробнее — см. [CONTRIBUTING.md](CONTRIBUTING.md). Если нашли уязвимость — [SECURITY.md](SECURITY.md).

## Лицензия

MIT, см. [LICENSE](LICENSE).

## Авторы

- Fedorov Tech
- Denis Fedorov

Форк основан на [pprometey/wireguard_aws](https://github.com/pprometey/wireguard_aws).
