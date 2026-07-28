# Device Strategy — going local-first, away from Xiaomi cloud

Context: Xiaomi is splitting the Mainland-China and international regions; the
international Mi Home app is dropping CN-region support, and CN cloud logins are
getting flaky (`70016`, `auth error`, China-server latency). The CN-market
devices here are only the **vacuum + 3 switches**. The goal is to stop depending
on the Xiaomi cloud entirely.

## Current device landscape

| Device | Market | Transport | Plan |
|---|---|---|---|
| Aqara Wall Switch E1 (QBKG38LM) ×3 | CN (AliExpress) | Zigbee | Phase 2 → local Zigbee coordinator |
| Mi Robot Vacuum 1S (`roborock.vacuum.m1s`) | CN | Wi-Fi | Local by token (start/stop/dock). Zones need cloud — dropped |
| Yeelight ceiling lights + chandeliers | EU (bought in Lithuania) | Wi-Fi | Local by token; enable Yeelight "LAN Control" for pure-local |
| Xiaomi/BLE thermometer, gateway | CN | BLE/Zigbee via gateway | Superseded by Zigbee coordinator in Phase 2 |

## Strategy by transport

### Zigbee (the 3 switches) — biggest win
Move to a dedicated Zigbee coordinator (SONOFF ZBDongle-P) via ZHA/Zigbee2MQTT
(Phase 2). Once paired locally, **region and cloud are irrelevant** — no
Aqara/Xiaomi cloud, no region lock, lowest latency. This fully closes the "CN
device" problem for the switches.

### Wi-Fi (vacuum, Yeelights) — local by token
- All Wi-Fi device tokens are backed up (see below) → HA controls them locally by
  IP+token even if the CN cloud dies completely.
- **Yeelight: enable "LAN Control"** in the Yeelight app for pure-local control
  with no cloud dependency at all.
- **Vacuum:** local start/stop/dock/full-clean works without cloud. Room/zone
  cleaning needs the cloud-hosted map (gen1 map lives in Xiaomi cloud; no local
  extraction without a BGA-solder root) — accepted as not worth it. If zones
  matter later, replace with a vacuum that supports local segments (newer
  Roborock via its own integration, or a Valetudo-supported model without BGA
  soldering).

## Token backup (cloud-independence insurance)

Tokens for all Wi-Fi devices are cached by the `xiaomi_miot` integration and were
copied to a secured location on the Pi (outside git):

- Pi: `/home/admin/xiaomi_tokens_backup/` (`devices-*.json`, `auth-*.json`, chmod 600)

These let HA re-add any Wi-Fi device by IP+token with **no cloud**. Keep an
off-device copy (personal cloud / password manager). **Never commit tokens to git.**

## Rules for future purchases

Prefer **local-first** hardware so this never happens again:

1. **Zigbee or Matter** — pair to your own coordinator; zero cloud, zero region lock. Best default.
2. **Shelly / ESPHome / Tasmota-flashable** Wi-Fi — full local API.
3. **Yeelight with LAN Control**, **Aqara over Zigbee** (not Wi-Fi cloud models).
4. **Avoid** devices whose key feature is cloud-only and region-locked (e.g. vacuum maps tied to a regional cloud).

## End state after Phase 2

Switches local in HA (Zigbee), lights local by token/LAN, vacuum local-basic. The
Xiaomi cloud can degrade or die — daily control is unaffected.
