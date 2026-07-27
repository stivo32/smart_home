# Smart Home Hub — Design Spec

**Date:** 2026-07-27
**Status:** Approved design, pre-implementation

## Goal

Unify a collection of Xiaomi sub-brand smart devices — currently controlled through many separate apps — into a single Android app, with a Raspberry Pi as the local hub. Primary pain point: current devices are provisioned against the Xiaomi Mainland-China cloud, giving 1–2 second command latency. Local control must cut this to near-zero.

## Requirements

- **One app** on Android for all devices.
- **One-time key/token setup** — configure Xiaomi credentials once, cached afterward.
- **Plugin/integration support** so new device types can be added.
- **Robot vacuum room-based cleaning** must be preserved (per-room / segment cleaning).
- **Low latency** — prefer local LAN control over cloud round-trips.
- **Non-disruptive** — Aqara Zigbee devices already work via their native Aqara hub; leave that as-is.
- **Runs in Docker** on a Raspberry Pi 3 that already hosts other jobs; must be resource-conscious.

## Chosen Approach

**Home Assistant (Container / Docker)** on the Raspberry Pi 3, with the official Home Assistant **Companion App** on Android as the single UI.

Rejected alternatives:
- **Full local reflashing (Valetudo / custom firmwares):** maximum privacy/speed but bricking risk and high effort — deferred as an optional future step, YAGNI at start.
- **Custom stack (python-miio broker + custom Kotlin app):** months of work reinventing what HA already provides — rejected.

## Architecture

```
┌─────────────────┐         ┌──────────────────────────┐
│  Android phone  │◄───────►│   Raspberry Pi 3 (LAN)   │
│  HA Companion   │  local  │  ┌────────────────────┐  │
│      app        │  HTTP   │  │ homeassistant      │  │
└─────────────────┘         │  │ (Docker container) │  │
                            │  └─────────┬──────────┘  │
                            │            │             │
                            │   existing jobs          │
                            └────────────┼─────────────┘
                                         │ LAN
                    ┌────────────────────┼────────────────────┐
                    ▼                    ▼                    ▼
            Wi-Fi devices          Xiaomi vacuum         Aqara hub
          (lights/switches)    (segments/rooms)      (Zigbee, as-is)
                    │
                    ▼ (once, for tokens)
              Xiaomi Cloud (CN)
```

- Home Assistant runs in one Docker container alongside existing Pi jobs.
- Xiaomi device tokens are fetched from the cloud **once** during setup and cached.
- After setup, commands travel over the LAN → millisecond latency.

## Components

1. **Home Assistant Container** — Docker container (`homeassistant/home-assistant:stable`), host networking (needed for device discovery), persistent `/config` volume, auto-restart. Memory-conscious config for Pi 3 (disable unused default integrations, recorder purge tuned).

2. **Xiaomi Miot Auto integration** (via HACS) — primary integration for Xiaomi Wi-Fi sub-brand devices. Pulls tokens from Xiaomi cloud on setup, then controls devices locally over LAN where the device/model supports it.

3. **HACS (Home Assistant Community Store)** — plugin manager, satisfies the "plugin support" requirement. Installed once into the HA config.

4. **Vacuum room cleaning** — `xiaomi_miio` vacuum entity for segment/room cleaning commands, plus **Xiaomi Cloud Map Extractor** custom card to display the live map and allow per-room selection in the dashboard.

5. **Aqara hub** — added as its own integration (Xiaomi/Aqara), left functionally untouched. Low priority.

6. **Android Companion App** — official HA app, points to the Pi's local URL, one-time login. Single UI for everything.

## Data Flow

- **Setup:** HA → Xiaomi Cloud (CN) once → retrieve device list + tokens → cache in HA config.
- **Runtime control:** Android app → HA (LAN) → device (LAN). No cloud round-trip for supported devices.
- **Vacuum map:** map data pulled (cloud or local depending on model) → rendered in HA dashboard card → room selection → segment-clean command sent to vacuum.

## Error Handling

- Token fetch failure at setup → retry with re-auth; document Xiaomi account 2FA / region caveats.
- Device offline → HA marks entity unavailable, surfaces in dashboard rather than hanging.
- Container crash → Docker `restart: unless-stopped` brings HA back.
- Config corruption → `/config` is a mounted volume, backed up (HA built-in backups + host-level copy).

## Testing / Validation

- HA container starts and web UI reachable on LAN.
- At least one Wi-Fi light: toggle from Android app, measure latency (target < ~300 ms, vs. 1–2 s cloud baseline).
- Vacuum: trigger a single-room clean from the dashboard, confirm it cleans only that room.
- Aqara device still controllable (regression check).
- Reboot Pi → HA comes back automatically.

## Out of Scope (for now)

- Custom Android app development.
- Reflashing device firmware (Valetudo, etc.).
- Zigbee migration off the Aqara hub.
- Voice assistants, automations beyond basic validation (can be added later via HACS).

## Future Options

- Move individual devices to local firmware to fully drop the China cloud dependency.
- Build automations/scenes once the base is stable.
