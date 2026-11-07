# Device Strategy — going local-first, away from Xiaomi cloud

Context: Xiaomi is splitting the Mainland-China and international regions; the
international Mi Home app is dropping CN-region support, and CN cloud logins are
getting flaky (`70016`, `87001` captcha, `auth error`, China-server latency).
The goal is to stop depending on the Xiaomi cloud entirely.

## Xiaomi account and region (actual, verified 2026-11-07)

- **All Xiaomi/Yeelight Wi-Fi devices live in one Xiaomi account,
  `stivo32@gmail.com`, region China (Mainland), server `cn`.** This includes the
  three Yeelight ceilings — an earlier version of this doc said "EU", which was
  wrong.
- Mi Home on the phone must stay on region **China**. The app keeps trying to
  update, and new versions drop CN-region support → **keep Mi Home auto-update
  off** (Play Store → Mi Home → ⋮ → untick auto-update) for as long as the app is
  still needed to (re)pair devices.
- **Do not use the Yeelight app.** It only offers China / Singapore / USA, the
  devices are not visible there and can't be added. Everything it would do is
  done via Mi Home (pairing) and HA (LAN Control, see runbook below).
- Mi Home's own "local control" setting requires a Xiaomi hub / Home Screen 11 /
  smart storage — unrelated to Yeelight LAN Control, ignore it.

## Current device landscape

| Device | Market | Transport | Status |
|---|---|---|---|
| Aqara Wall Switch E1 ×4 (спальня, детская, гостиная, кухня) | CN (AliExpress) | Zigbee | ✅ ZHA on the SONOFF coordinator, fully local |
| Mi Robot Vacuum 1S (`roborock.vacuum.m1s`) | CN | Wi-Fi | Local by token (start/stop/dock). Zones need cloud — dropped |
| Yeelight ceiling lights ×3 | CN account | Wi-Fi | ✅ Native `yeelight` integration, LAN Control, fully local |
| Yeelight Mesh Downlight M2 ×6 (kitchen spots) | — | **BLE Mesh** | No LAN Control (mesh). On/off via the kitchen E1 switch; dimming/color set-and-forget in Mi Home |
| Yeelight bedside lamp (bslamp2), детская | CN account | Wi-Fi | On `xiaomi_miot` (cloud login needed). Rejects the LAN Control command — stays on miot |
| Xiaomi/BLE thermometer, gateway | CN | BLE/Zigbee via gateway | On `xiaomi_miot` (cloud); superseded by Zigbee coordinator |

### Yeelight lights — room map

| Room | Model | Yeelight id | IP (2026-11-07) | Wall switch |
|---|---|---|---|---|
| Спальня | Arwen Ceiling Light (`ceilb`) | `0x182d2b96` | 192.168.1.37 | switch спальня |
| Гостиная | LED Ceiling Light Pro 2 (`ceila`) | `0x1a61970c` | 192.168.1.65 | switch гостинная |
| Детская | LED Ceiling Light Pro (`ceila`) | `0x17a26c8e` | 192.168.1.44 (was .42 before re-pair) | switch детская |
| Детская | Mi Bedside Lamp 2 (`bslamp2`) | — | 192.168.1.68 | — |

IPs come from DHCP and can change; the native `yeelight` integration finds a
lamp by its id and updates the host on its own. A DHCP reservation in the router
is still recommended.

The ceilings sit behind power-cutting wall switches: **switch off → lamp has no
power → `unavailable` in HA and "offline" in Mi Home. That is expected.** Before
debugging a "dead" ceiling, check that its wall switch is on.

## Strategy by transport

### Zigbee (the wall switches) — done
Paired to a dedicated Zigbee coordinator (SONOFF ZBDongle-P) via ZHA. Region and
cloud are irrelevant — no Aqara/Xiaomi cloud, no region lock, lowest latency.
The no-neutral E1 switches occasionally drop/rejoin (weak power through the
load); a bypass capacitor or a Zigbee router nearby helps.

### BLE Mesh (6 kitchen Yeelight M2 downlights) — via the wall switch
Yeelight Mesh (Bluetooth Mesh) has no LAN Control and only works through a mesh
gateway + Mi Home cloud — not practically localizable in HA. All 6 kitchen spots
are on **one Aqara E1 wall switch**, so HA gets on/off via that switch.
Brightness/color stay set-and-forget in Mi Home. HA does not manage the spots
individually — by design.

### Wi-Fi (vacuum, Yeelights) — local by token
- HA controls Wi-Fi devices locally by IP+token. **Tokens change whenever a
  device is re-added in Mi Home**, so after any re-pair HA must fetch fresh
  tokens from the cloud (runbook below).
- **Yeelight ceilings: LAN Control is enabled by HA via the token** (no app
  needed). With LAN Control on, the native `yeelight` integration works with no
  cloud at all.
- **Vacuum:** local start/stop/dock/full-clean works without cloud. Room/zone
  cleaning needs the cloud-hosted map (gen1 map lives in Xiaomi cloud; no local
  extraction without a BGA-solder root) — accepted as not worth it. If zones
  matter later, replace with a vacuum that supports local segments (newer
  Roborock via its own integration, or a Valetudo-supported model without BGA
  soldering).

## Runbook: keeping the Xiaomi connection alive

`xiaomi_miot` still needs a working cloud login for the bedside lamp, gateway,
thermometer and vacuum, and to fetch fresh tokens. Xiaomi periodically
invalidates the session and then demands a captcha (log:
`Login to xiaomi error ... "code":87001 ... "type":"manMachine"`, entities go
`unavailable`).

**Re-login via HA (do it whenever miot devices go unavailable, and every now
and then preventively):**

1. HA (phone app or browser) → Settings → Devices & services → **Xiaomi Miot**.
2. ⋮ → **Reconfigure** (or "Re-authenticate" if HA offers it).
3. Account `stivo32@gmail.com`, server **cn**, password, solve the captcha.
4. Check the log for `Got N devices from xiaomi cloud`; miot entities come back.

Only a human can do this step (password + captcha).

## Runbook: bringing a Yeelight ceiling back into HA

1. **Wall switch on**, wait ~1 min for the lamp to join Wi-Fi.
2. If the lamp lit up but is **offline in Mi Home** → it lost Wi-Fi: delete it in
   Mi Home, reset it (power-cycle it with the wall switch ~5 times, ~2 s on each,
   leave it on — it blinks when reset), add it again in Mi Home (region China,
   2.4 GHz Wi-Fi, phone close to the lamp).
3. **Refresh tokens in HA.** `xiaomi_miot` caches the device list for 24 h, so a
   restart alone uses stale tokens. On the Pi, set `update_time` to `0` in
   `homeassistant/.storage/xiaomi_miot/devices-<uid>-cn.json` (keep a backup
   copy), then `docker restart homeassistant`. The file is rewritten with fresh
   tokens within ~20 s.
4. **Enable LAN Control via the token**, from inside the HA container:
   ```python
   from miio import Device
   Device("<lamp ip>", "<token from devices-*.json>").send("set_ps", ["cfg_lan_ctrl", "1"])
   ```
   `get_prop ["lan_ctrl"]` should then return `1` and TCP port 55443 opens.
5. `docker restart homeassistant` (or wait ≤10 min for the retry). The native
   `yeelight` entity becomes `on`/`off`; a new IP is picked up automatically.

## Token backup (cloud-independence insurance)

Tokens for all Wi-Fi devices are cached by the `xiaomi_miot` integration
(`homeassistant/.storage/xiaomi_miot/devices-*.json`) and were copied to a
secured location on the Pi (outside git):

- Pi: `/home/admin/xiaomi_tokens_backup/` (`devices-*.json`, `auth-*.json`, chmod 600)

These let HA re-add any Wi-Fi device by IP+token with **no cloud**. The backup
goes stale for any device re-added in Mi Home (all three ceilings were re-paired
by 2026-11-07) — refresh it after re-pairing. Keep an off-device copy (personal
cloud / password manager). **Never commit tokens to git.**

## Rules for future purchases

Prefer **local-first** hardware so this never happens again:

1. **Zigbee or Matter** — pair to your own coordinator; zero cloud, zero region lock. Best default.
2. **Shelly / ESPHome / Tasmota-flashable** Wi-Fi — full local API.
3. **Yeelight with LAN Control**, **Aqara over Zigbee** (not Wi-Fi cloud models).
4. **Avoid** devices whose key feature is cloud-only and region-locked (e.g. vacuum maps tied to a regional cloud).

## End state

Switches local in HA (Zigbee), ceilings local via LAN Control, vacuum
local-basic. The Xiaomi cloud can degrade or die — daily control of switches and
ceilings is unaffected; only the bedside lamp, gateway/thermometer and token
refresh still need a periodic Xiaomi re-login.
