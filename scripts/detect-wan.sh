#!/bin/bash
# Выводит имя WAN-интерфейса на stdout. Подсказка/prompt идут в stderr,
# чтобы вызывающая сторона могла захватить результат через $(...).
set -euo pipefail

default=$(ip -c route | grep "default" | awk '{print $5}')

# `read` сам по себе пишет prompt в stderr, что нам и нужно.
read -r -p "Имя WAN-интерфейса ([ENTER] = ${default}): " name 1>&2
echo "${name:-${default}}"
