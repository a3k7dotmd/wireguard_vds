# Wave 2: state.env + CIDR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Replace four separate `*.var` files (`endpoint.var`, `dns.var`, `vpn_subnet.var`, `last_used_ip.var`) with a single shell-source-able `state.env`. Switch `VPN_SUBNET` from trailing-dot hack (`10.8.8.`) to proper CIDR (`10.8.8.0/24`).

**Architecture:** `state.env` written wholesale via heredoc, sourced via `. state.env` at the start of each consuming script. Updates re-write the whole file. CIDR parsed by bash IFS=. split.

**Tech Stack:** bash. No new deps.

**Reference:** [docs/specs/2026-05-20-restructure-wave2-design.md](../specs/2026-05-20-restructure-wave2-design.md)

---

## Task 1: Switch `scripts/install.sh` to write `state.env` + CIDR subnet

**Files:**
- Modify: `scripts/install.sh`

- [ ] **Step 1: Locate and replace the four state writes**

The current `scripts/install.sh` writes:

```bash
# (around line 38–41) endpoint
read -r -p "Enter the endpoint ... " ENDPOINT
if [ -z "${ENDPOINT}" ]
  then echo "${WAN_IP}:51820" | tee ./endpoint.var;
  else echo "${ENDPOINT}" > ./endpoint.var
fi
```

```bash
# (around line 55) subnet (trailing-dot hack)
echo "${SERVER_IP}" | grep -o -E '([0-9]+\.){3}' > ./vpn_subnet.var
```

```bash
# (around line 61) dns
echo "${DNS}" > ./dns.var
```

```bash
# (around line 63) last-used-ip counter
echo 1 > ./last_used_ip.var
```

Rework so:

1. **Endpoint** — instead of writing `./endpoint.var` in the `if/else`, normalise into a variable and defer to the final heredoc:

```bash
read -r -p "Enter the endpoint (external ip and port) in format [ipv4:port]. ([ENTER] set ${WAN_IP}:51820): " ENDPOINT
if [ -z "${ENDPOINT}" ]; then
    ENDPOINT="${WAN_IP}:51820"
fi
```

2. **Subnet** — replace the `grep -o -E` with bash IFS parsing into CIDR:

```bash
# построить CIDR из выбранного SERVER_IP (например 10.8.8.1 → 10.8.8.0/24)
IFS=. read -r SUBNET_O1 SUBNET_O2 SUBNET_O3 _ <<<"${SERVER_IP}"
VPN_SUBNET="${SUBNET_O1}.${SUBNET_O2}.${SUBNET_O3}.0/24"
```

(Удаляем вызов `echo "${SERVER_IP}" | grep -o -E '([0-9]+\.){3}' > ./vpn_subnet.var`.)

3. **DNS** — нормализуем в переменную (она уже есть), убираем запись в `./dns.var`.

4. **Last-used-ip** — убираем `echo 1 > ./last_used_ip.var`, заводим переменную `LAST_USED_IP=1`.

- [ ] **Step 2: Add the unified `state.env` write at the end**

Right before the final `cp -f ./wg0.conf.def ./wg0.conf` line, insert:

```bash
# единый state-файл для последующих скриптов
cat > ./state.env <<EOF
ENDPOINT="${ENDPOINT}"
DNS="${DNS}"
VPN_SUBNET="${VPN_SUBNET}"
LAST_USED_IP=${LAST_USED_IP}
EOF
```

- [ ] **Step 3: Verify lint and smoke**

```bash
cd /Users/ragnar/fedorov_tech/wireguard_vds
make lint
make test
```

Both green. (Smoke doesn't exercise install, but lint will catch any syntax error.)

- [ ] **Step 4: Verify no leftover `.var` references in install.sh**

```bash
grep -nE '\.var\b' scripts/install.sh
```

Expected: zero matches.

- [ ] **Step 5: Commit**

```bash
git add scripts/install.sh
git commit -m "refactor(install): write single state.env, CIDR for subnet

Four .var files (endpoint, dns, vpn_subnet, last_used_ip) collapsed
into one heredoc-written state.env in shell-source format.

vpn_subnet now stored as proper CIDR (10.8.8.0/24) instead of the
trailing-dot hack (10.8.8.) — built via IFS=. split from SERVER_IP."
```

---

## Task 2: Switch `scripts/add-client.sh` to source `state.env` + CIDR parse

**Files:**
- Modify: `scripts/add-client.sh`

- [ ] **Step 1: Replace the four `read -r` lines with `source state.env`**

Current (just after `cd "${WORK_DIR}" || exit 1`):

```bash
read -r DNS < ./dns.var
read -r ENDPOINT < ./endpoint.var
read -r VPN_SUBNET < ./vpn_subnet.var
```

(`last_used_ip.var` is read later, around line 51.) Replace **all four** reads (across the file) with a single `source` at the top:

```bash
# shellcheck source=/dev/null
. "${WORK_DIR}/state.env"
```

And delete:
- The three top reads of `DNS`, `ENDPOINT`, `VPN_SUBNET`.
- The later `read -r OCTET_IP < /etc/wireguard/last_used_ip.var` (~line 51).

`OCTET_IP` should be derived from `LAST_USED_IP` after sourcing, **before** the boundary check:

```bash
OCTET_IP="${LAST_USED_IP}"
if [[ "${OCTET_IP}" -ge 254 ]]; then
    echo "Пул исчерпан!"
    exit 1
fi

OCTET_IP=$((OCTET_IP+1))
LAST_USED_IP=${OCTET_IP}
```

- [ ] **Step 2: Switch CLIENT_IP build to CIDR parsing**

Current (~line 61): `CLIENT_IP="${VPN_SUBNET}${OCTET_IP}/32"` (relies on `VPN_SUBNET` ending with a dot).

Replace with:

```bash
# извлечь первые три октета из CIDR (например 10.8.8.0/24 → 10.8.8)
IFS=. read -r PREFIX_O1 PREFIX_O2 PREFIX_O3 _ <<<"${VPN_SUBNET%/*}"
CLIENT_IP="${PREFIX_O1}.${PREFIX_O2}.${PREFIX_O3}.${OCTET_IP}/32"
```

- [ ] **Step 3: Replace the LAST_USED_IP persist write with full state.env rewrite**

Current (~line 59): `echo "${OCTET_IP}" > /etc/wireguard/last_used_ip.var`.

Replace with full rewrite (uses sourced `${ENDPOINT}`, `${DNS}`, `${VPN_SUBNET}` plus the new `${LAST_USED_IP}`):

```bash
# обновить state.env с новым LAST_USED_IP
cat > "${WORK_DIR}/state.env" <<EOF
ENDPOINT="${ENDPOINT}"
DNS="${DNS}"
VPN_SUBNET="${VPN_SUBNET}"
LAST_USED_IP=${LAST_USED_IP}
EOF
```

- [ ] **Step 4: Verify lint and smoke**

```bash
make lint
make test
```

**Smoke is the critical floor here** — it doesn't exercise install/add directly, but it does run through `scripts/remove-client.sh` which is unchanged. If lint passes, the syntactic changes are clean.

- [ ] **Step 5: Verify no leftover `.var` references in add-client.sh**

```bash
grep -nE '\.var\b' scripts/add-client.sh
```

Expected: zero matches.

- [ ] **Step 6: Commit**

```bash
git add scripts/add-client.sh
git commit -m "refactor(add-client): source state.env, parse CIDR for client IP

Four .var reads replaced by a single \`. state.env\`. CLIENT_IP
built from the CIDR by IFS=. splitting the network address. The
LAST_USED_IP write at the end is now a full state.env rewrite
(transactionally consistent with ENDPOINT/DNS/VPN_SUBNET)."
```

---

## Task 3: Switch `scripts/reset.sh` to update `state.env`

**Files:**
- Modify: `scripts/reset.sh`

- [ ] **Step 1: Replace last_used_ip write**

Current contents (relevant part):

```bash
cd /etc/wireguard || exit 1

# удалить директории клиентов
rm -rf ./clients

# обнулить счётчик IP
echo "1" > last_used_ip.var

# восстановить серверный конфиг из шаблона
cp -f wg0.conf.def wg0.conf
```

Replace the `echo "1" > last_used_ip.var` block with:

```bash
# обнулить счётчик IP в state.env
# shellcheck source=/dev/null
. ./state.env
LAST_USED_IP=1
cat > ./state.env <<EOF
ENDPOINT="${ENDPOINT}"
DNS="${DNS}"
VPN_SUBNET="${VPN_SUBNET}"
LAST_USED_IP=${LAST_USED_IP}
EOF
```

- [ ] **Step 2: Verify lint and smoke**

```bash
make lint
make test
```

- [ ] **Step 3: Verify no `.var` references in reset.sh**

```bash
grep -nE '\.var\b' scripts/reset.sh
```

Expected: zero.

- [ ] **Step 4: Commit**

```bash
git add scripts/reset.sh
git commit -m "refactor(reset): update state.env instead of last_used_ip.var

source + LAST_USED_IP=1 + full re-write."
```

---

## Task 4: Repo-wide sanity grep + push

- [ ] **Step 1: Final cross-cutting grep**

```bash
grep -rnE 'endpoint\.var|dns\.var|vpn_subnet\.var|last_used_ip\.var' scripts/ tests/ wgctl Makefile
```

Expected: zero matches anywhere (docs may still mention them historically — fine).

- [ ] **Step 2: Lint + smoke one more time**

```bash
make lint
make test
```

- [ ] **Step 3: Push**

```bash
git push origin master
```

- [ ] **Step 4: Watch CI**

```bash
gh run list --branch master --limit 1
gh run watch <run-id>
```

Expected: green. If CI fails, investigate before moving to Wave 3.

---

## What stays unchanged

- `scripts/remove-client.sh` — does not source state, does not touch counters.
- `scripts/uninstall.sh` — `rm -rf /etc/wireguard` handles everything regardless of format.
- `tests/smoke.sh` — coverage unchanged (still only `remove-client.sh`).
- `scripts/detect-wan.sh`, `scripts/initial.sh`, `scripts/menu.sh`, `wgctl`, `Makefile` — none of them touch state files.
