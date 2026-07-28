# Smart Home Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify all smart devices under one Home Assistant instance on the Raspberry Pi, controlled locally (low latency) through the official Android Companion app.

**Architecture:** A single `homeassistant/home-assistant` Docker container runs on the Pi with host networking and a persistent `/config` volume. HACS provides plugin management; Xiaomi Miot Auto controls Mi Home Wi-Fi devices over the LAN. Zigbee devices (Aqara switches, ceiling lights) move onto a dedicated USB Zigbee coordinator via ZHA/Zigbee2MQTT (Phase 2), retiring the vendor hubs/clouds. Config lives in this git repo, deployed to the Pi over SSH.

**Tech Stack:** Docker + docker compose, Home Assistant (Container/stable), HACS, Xiaomi Miot Auto, Xiaomi vacuum map card, HA Android Companion app, SONOFF ZBDongle-P (TI CC2652P) + ZHA/Zigbee2MQTT (Phase 2).

## Actual Environment (discovered on deploy — supersedes earlier assumptions)

- Hardware is a **Raspberry Pi 4 (4GB, aarch64, Debian 12 bookworm)** — NOT a Pi 3. Resources are comfortable.
- SSH alias `pi` → `admin@192.168.1.41`, key `~/.ssh/id_ed25519_pi`, passwordless sudo.
- TZ **Europe/Vilnius**. Pi runs other jobs on the same SD card.
- Deploy dir on Pi: **`/home/admin/smart_home`**. Image pulled from **docker.io** (ghcr.io stalled).
- `mem_limit` is a no-op — kernel has `cgroup_disable=memory` in cmdline; not worth a reboot to change on 4GB.
- SD card had corruption (from a prior power loss) — cleared; a true offline root fsck is not achievable via reboot on RPi OS (no initramfs). Card usable but under mild suspicion → Phase 2 hardening candidate.

## Device Inventory (from Xiaomi Miot cn account, 33 entities)

- **Vacuum:** `vacuum.roborock_m1s_f706` (Roborock M1S) + status/battery/mode/segment buttons.
- **Lights:** Yeelight `yeelink_ceila`, `yeelink_ceilb` (ceiling), `yeelink_bslamp2` (lamp).
- **Sensor:** `miaomiaoce_t2` temp/humidity.
- **Switch:** `switch.lumi_b1lc04_2231` (one Lumi/Aqara switch that is linked to Mi Home).
- **Xiaomi Multimode Gateway** `lumi_mgl03_3110` (the "Xiaomi Smart Home Hub") — present, few children.
- **Not yet in HA:** Aqara **M2 hub** + its ceiling Zigbee lights; **Aqara Wall Switch E1 (QBKG38LM**, single-button, no-neutral, Zigbee, CN) units — currently only reachable via Apple Home. These are Phase 2.

## Deployment Model

Config authored in this repo, synced to the Pi and applied there:

```bash
export PI_HOST=pi
export PI_DIR=/home/admin/smart_home
rsync -a --exclude='.git' --exclude='homeassistant/secrets.yaml' --exclude='homeassistant/.storage' \
  --exclude='homeassistant/home-assistant_v2.db' --exclude='homeassistant/custom_components' \
  ./ "$PI_HOST:$PI_DIR/"
ssh pi "cd $PI_DIR && docker compose up -d"
```

## Global Constraints

- HA runs as a **Docker container** (not HA OS), alongside existing Pi jobs.
- Host networking is required (Xiaomi/mDNS discovery does not work in bridge mode).
- Secrets never committed — `homeassistant/secrets.yaml` is git-ignored.
- Latency target for local control: < ~300 ms (baseline 1–2 s via China cloud).

---

# PHASE 1 — Current devices + mobile app

Goal: confirm everything already in HA (Xiaomi Mi Home devices) works locally, preserve vacuum room cleaning, and get the Android app as the single UI. No new hardware.

## Done so far (✅)

- ✅ Scaffold: `docker-compose.yml` (docker.io image, host net, Vilnius TZ), `.gitignore`, `README.md`, Mac dry-run override.
- ✅ Pi 4 prepared: old crashlooping HA + corrupted image removed, SD errors cleared.
- ✅ HA deployed fresh on Pi, onboarding done (owner account created).
- ✅ HACS installed and configured.
- ✅ Xiaomi Miot Auto installed; **cn account added** → 33 entities imported.

### Task 1.1: Verify Xiaomi devices reachable + measure local latency

**Files:** none (validation only).

- [ ] **Step 1: Confirm entities are `available` (not `unavailable`)**

In HA: Developer Tools → States. Filter for `light.yeelink`, `vacuum.roborock`, `switch.lumi`. Confirm state is on/off/docked, not `unavailable`.

- [ ] **Step 2: Toggle a light from the dashboard**

Toggle `light.yeelink_ceilb_5b2c_light` in the UI. Confirm the physical light responds.

- [ ] **Step 3: Measure command latency (local vs old cloud baseline)**

Create a long-lived token (HA profile → Security → Long-lived tokens), store as `$HA_TOKEN`, then from the dev machine:
```bash
time curl -s -X POST -H "Authorization: Bearer $HA_TOKEN" -H "Content-Type: application/json" \
  -d '{"entity_id":"light.yeelink_ceilb_5b2c_light"}' \
  http://192.168.1.41:8123/api/services/light/toggle
```
Expected: light reacts, `real` well under 1 s (target < ~300 ms) vs the 1–2 s cloud baseline. If latency is high, check whether Miot is controlling this device locally or via cloud (integration options → enable local/LAN mode).

### Task 1.2: Vacuum room / segment cleaning

**Files:** Create `docs/runbook-xiaomi-tokens.md` (token/region + vacuum notes).

- [ ] **Step 1: Confirm vacuum entity + get room mapping**

Developer Tools → Actions → `vacuum.send_command`, target `vacuum.roborock_m1s_f706`, command `get_room_mapping`. Read the segment ID → room name mapping from the response/state.

- [ ] **Step 2: Install a vacuum map card via HACS**

HACS → Frontend → search "Xiaomi Vacuum Map" (`PiotrMachowski/lovelace-xiaomi-vacuum-map-card`) → Download → restart HA (via SSH: `ssh pi 'cd /home/admin/smart_home && docker compose restart homeassistant'`).

- [ ] **Step 3: Add the map card + validate a single-room clean**

Add the card to the dashboard, configure rooms with the IDs from Step 1. Then trigger one room and confirm the vacuum cleans only that room:
```yaml
# vacuum.send_command
command: app_segment_clean
params: [<segment_id>]
```
Expected: vacuum cleans only the selected room, returns to dock.

- [ ] **Step 4: Write runbook + commit**

Document region/token workflow and the `get_room_mapping` / `app_segment_clean` commands in `docs/runbook-xiaomi-tokens.md`.
```bash
git add docs/runbook-xiaomi-tokens.md && git commit -m "docs: Xiaomi token/region + vacuum room runbook"
```

### Task 1.3: Android Companion app as the single UI

**Files:** Modify `README.md` (operations section).

- [ ] **Step 1: Install + connect the app**

Install "Home Assistant" from the Play Store. It auto-discovers the Pi on the LAN (or enter `http://192.168.1.41:8123`). Log in with the owner account.
Validation: dashboard loads on the phone; toggling a light works from the phone.

- [ ] **Step 2: Confirm remote-friendly basics**

Confirm the app stays logged in and controls devices over Wi-Fi. (External/remote access — Nabu Casa or VPN — is out of scope for Phase 1; LAN only.)

- [ ] **Step 3: Enable HA backups + commit ops notes**

HA: Settings → System → Backups → create a full backup. Append an operations section to `README.md`.
```bash
git add README.md && git commit -m "docs: operations + Android app notes"
```

### Task 1.4: (optional) Bluetooth capabilities

The container logs `Missing NET_ADMIN/NET_RAW capabilities for Bluetooth`. Only do this if BLE devices (e.g. Xiaomi thermometers) need direct HA Bluetooth.

- [ ] Add to `docker-compose.yml` under the service: `cap_add: [NET_ADMIN, NET_RAW]` and volume `- /run/dbus:/run/dbus:ro`, redeploy, restart. Otherwise leave Bluetooth disabled.

---

# PHASE 2 — Zigbee coordinator + Aqara/ceiling lights (when the stick arrives)

Goal: bring the Aqara E1 wall switches and ceiling Zigbee lights into HA **locally**, on a dedicated coordinator, retiring the Aqara/Xiaomi vendor hubs and Apple Home dependency for these devices.

**Hardware:** SONOFF **ZBDongle-P** (TI CC2652P + CP2102N). Plug via a **USB 2.0 extension cable** into a **USB 2.0 (black) port** on the Pi 4 (USB3 ports cause 2.4GHz interference). Appears as `/dev/ttyUSB0` (cp210x driver built into Linux).

### Task 2.1: Wire the coordinator into the container

**Files:** Modify `docker-compose.yml`.

- [ ] Confirm the device node on the Pi: `ssh pi 'ls -l /dev/ttyUSB* && dmesg | grep -i cp210'`.
- [ ] Add to the `homeassistant` service in `docker-compose.yml`:
  ```yaml
  devices:
    - /dev/ttyUSB0:/dev/ttyUSB0
  ```
- [ ] Redeploy (rsync) + `docker compose up -d`. Commit.

### Task 2.2: Choose + set up the Zigbee stack

Decision: **ZHA** (built into HA, no broker, simplest) vs **Zigbee2MQTT** (broader Aqara support, needs an MQTT broker container). Lean **Zigbee2MQTT** for the Aqara E1 quirks — revisit at execution.

- [ ] If Z2M: add `eclipse-mosquitto` + `zigbee2mqtt` containers (or HA MQTT add-on equivalent), point Z2M at `/dev/ttyUSB0`, add the MQTT integration in HA.
- [ ] If ZHA: Settings → Devices & Services → Add Integration → ZHA → select `/dev/ttyUSB0` → CC2652P/znp radio.
- [ ] Validation: the Zigbee network forms; coordinator online.

### Task 2.3: Pair devices + retire vendor hubs

- [ ] Factory-reset each **Aqara E1 switch** and pair to the new coordinator (permit-join). Note: no-neutral single-live-wire switches may need a light load/bypass to power on.
- [ ] Factory-reset + pair the **ceiling Zigbee lights** currently on the Aqara M2.
- [ ] Confirm each appears as an HA entity and toggles locally.
- [ ] Once all Zigbee devices are on the new coordinator, remove the Aqara hub from Apple Home and retire the Aqara M2 / Xiaomi gateway for Zigbee (or repurpose).
- [ ] Reconcile the **EU-region** device: if it never reappears in Mi Home, pair it to the Zigbee coordinator too.

### Task 2.4: (optional) SD hardening

- [ ] Consider migrating HA/boot to a USB SSD, or enable initramfs to allow real offline root fsck, given the SD's prior corruption. Keep recorder purge low (already 7 days) to limit SD wear.

---

## Self-Review

**Phase 1 coverage:** current Xiaomi devices verified (1.1), vacuum rooms (1.2), Android app (1.3), Bluetooth optional (1.4). **Phase 2 coverage:** coordinator wiring (2.1), stack choice (2.2), pairing + hub retirement + EU device (2.3), SD hardening (2.4).

**Placeholder scan:** `<segment_id>`, `<...>` are user-supplied runtime values with documented sources, not gaps.

**Consistency:** deploy vars (`PI_HOST=pi`, `PI_DIR=/home/admin/smart_home`), image (docker.io), device node (`/dev/ttyUSB0`), and entity IDs match the discovered inventory throughout.
