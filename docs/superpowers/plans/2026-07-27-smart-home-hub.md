# Smart Home Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up Home Assistant in Docker on a Raspberry Pi 3 to control Xiaomi Wi-Fi devices locally (low latency), preserve robot-vacuum room cleaning, and expose everything through the official Android Companion app.

**Architecture:** A single `homeassistant/home-assistant` Docker container runs on the Pi 3 with host networking and a persistent `/config` volume. HACS provides plugin management; the Xiaomi Miot Auto integration fetches device tokens from the Xiaomi cloud once, then controls Wi-Fi devices over the LAN. The vacuum uses `xiaomi_miio` segment cleaning plus a map card. Config lives in this git repo and is deployed to the Pi over SSH.

**Tech Stack:** Docker + docker compose, Home Assistant (Container/stable), HACS, Xiaomi Miot Auto integration, Xiaomi Cloud Map Extractor card, HA Android Companion app.

## Global Constraints

- Target device: Raspberry Pi 3 (ARM, ~1GB RAM) — memory-conscious config, no heavy add-ons.
- HA runs as a **Docker container** (not HA OS), alongside existing Pi jobs.
- Container image: `ghcr.io/home-assistant/home-assistant:stable`.
- Host networking is required (Xiaomi/mDNS device discovery does not work in bridge mode).
- Secrets (Xiaomi account, tokens) must never be committed — kept in `homeassistant/secrets.yaml`, git-ignored.
- Aqara Zigbee hub stays untouched; Zigbee is lowest priority.
- Latency target for local Wi-Fi control: < ~300 ms (baseline is 1–2 s via China cloud).

## Deployment Model

All config files are authored in this repo on the dev machine, then synced to the Pi at `~/smart_home/` and applied there. Set these shell vars on the dev machine before running deploy commands:

```bash
export PI_HOST=pi@raspberrypi.local   # adjust to your Pi's user@host or IP
export PI_DIR=/home/pi/smart_home
```

Deploy helper (used throughout):

```bash
rsync -av --exclude='homeassistant/secrets.yaml' --exclude='homeassistant/.storage' \
  --exclude='homeassistant/home-assistant_v2.db' \
  ./ "$PI_HOST:$PI_DIR/"
```

## File Structure

- `docker-compose.yml` — HA container definition (host network, restart policy, volume).
- `homeassistant/configuration.yaml` — base HA config tuned for Pi 3.
- `homeassistant/secrets.yaml.example` — template for secrets (real one git-ignored).
- `.gitignore` — excludes secrets, HA runtime state, DB.
- `README.md` — deploy + operations runbook.
- `docs/runbook-xiaomi-tokens.md` — how to obtain Xiaomi tokens / set region.

---

### Task 1: Repo scaffolding + HA container running on the Pi

**Files:**
- Create: `docker-compose.yml`
- Create: `.gitignore`
- Create: `README.md`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a running HA instance reachable at `http://<pi-ip>:8123`; the `$PI_DIR` deploy layout; the `homeassistant/` config directory mounted into the container at `/config`.

- [ ] **Step 1: Write `.gitignore`**

```gitignore
homeassistant/secrets.yaml
homeassistant/.storage/
homeassistant/home-assistant_v2.db
homeassistant/*.log
homeassistant/.cloud/
homeassistant/tts/
homeassistant/deps/
```

- [ ] **Step 2: Write `docker-compose.yml`**

```yaml
services:
  homeassistant:
    container_name: homeassistant
    image: ghcr.io/home-assistant/home-assistant:stable
    restart: unless-stopped
    network_mode: host
    privileged: false
    volumes:
      - ./homeassistant:/config
      - /etc/localtime:/etc/localtime:ro
    environment:
      - TZ=Europe/Warsaw
    # Pi 3 is memory-limited; cap so HA can't starve existing jobs.
    mem_limit: 768m
```

- [ ] **Step 3: Write `README.md` deploy section**

````markdown
# Smart Home Hub

Home Assistant in Docker on a Raspberry Pi 3, for local control of Xiaomi Wi-Fi devices.

## Deploy

On the dev machine:

```bash
export PI_HOST=pi@raspberrypi.local
export PI_DIR=/home/pi/smart_home
rsync -av --exclude='homeassistant/secrets.yaml' --exclude='homeassistant/.storage' \
  --exclude='homeassistant/home-assistant_v2.db' ./ "$PI_HOST:$PI_DIR/"
```

On the Pi:

```bash
cd ~/smart_home
docker compose up -d
docker compose logs -f homeassistant
```

Open `http://<pi-ip>:8123`.
````

- [ ] **Step 4: Deploy to the Pi and start the container**

Run (dev machine):
```bash
rsync -av --exclude='homeassistant/secrets.yaml' ./ "$PI_HOST:$PI_DIR/"
ssh "$PI_HOST" "cd $PI_DIR && docker compose up -d"
```
Expected: `docker compose up -d` reports `Container homeassistant Started`.

- [ ] **Step 5: Validate HA is reachable**

Run (dev machine):
```bash
curl -s -o /dev/null -w "%{http_code}\n" http://<pi-ip>:8123/
```
Expected: `200` (HA onboarding page). If `000`, check `ssh "$PI_HOST" "docker compose -f $PI_DIR/docker-compose.yml logs --tail=50 homeassistant"`.

- [ ] **Step 6: Commit**

```bash
git add .gitignore docker-compose.yml README.md
git commit -m "feat: HA docker-compose scaffold + deploy runbook"
```

---

### Task 2: Base HA config tuned for Pi 3 + onboarding

**Files:**
- Create: `homeassistant/configuration.yaml`
- Create: `homeassistant/secrets.yaml.example`

**Interfaces:**
- Consumes: running container from Task 1 (mounts `homeassistant/` → `/config`).
- Produces: a `configuration.yaml` with recorder tuned for low disk/memory; a `secrets.yaml` convention (`!secret` keys) for later tasks.

- [ ] **Step 1: Write `homeassistant/secrets.yaml.example`**

```yaml
# Copy to secrets.yaml (git-ignored) and fill in real values.
# Xiaomi cloud account used to fetch device tokens (Task 4).
xiaomi_username: "your-xiaomi-account@example.com"
xiaomi_password: "your-password"
xiaomi_country: "cn"   # region devices are provisioned in; "cn" = Mainland China
```

- [ ] **Step 2: Write `homeassistant/configuration.yaml`**

```yaml
# Loads HA defaults (frontend, history, etc.)
default_config:

# Pi 3 is I/O and memory constrained — keep the recorder small.
recorder:
  purge_keep_days: 7
  commit_interval: 30
  exclude:
    domains:
      - updater
      - sun

# Trust the LAN and reverse proxies on the Pi itself.
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 127.0.0.1
    - ::1

logger:
  default: warning
```

- [ ] **Step 3: Deploy and restart HA**

Run:
```bash
rsync -av --exclude='homeassistant/secrets.yaml' ./ "$PI_HOST:$PI_DIR/"
ssh "$PI_HOST" "cd $PI_DIR && docker compose restart homeassistant"
```
Expected: container restarts without error.

- [ ] **Step 4: Validate config is accepted**

Run:
```bash
ssh "$PI_HOST" "docker exec homeassistant python -m homeassistant --script check_config -c /config"
```
Expected: `Testing configuration at /config` then no `ERROR` lines; ends with the config summary.

- [ ] **Step 5: Complete onboarding in the browser**

Open `http://<pi-ip>:8123`, create the owner account, set home location/timezone. This account is what the Android app logs into.
Validation: you reach the empty HA dashboard (Overview).

- [ ] **Step 6: Commit**

```bash
git add homeassistant/configuration.yaml homeassistant/secrets.yaml.example
git commit -m "feat: Pi 3-tuned HA base config + secrets template"
```

---

### Task 3: Install HACS (plugin manager)

**Files:**
- Modify: none in repo (HACS installs into `homeassistant/custom_components/` which is runtime state on the Pi).
- Modify: `.gitignore` (ignore HACS-managed runtime files).

**Interfaces:**
- Consumes: onboarded HA from Task 2.
- Produces: a working HACS panel used by Tasks 4 and 5 to install `Xiaomi Miot Auto` and the map card.

- [ ] **Step 1: Add HACS runtime paths to `.gitignore`**

```gitignore
homeassistant/custom_components/
homeassistant/www/community/
```

- [ ] **Step 2: Install HACS onto the Pi**

Run (installs into the mounted config dir via the official script inside the container):
```bash
ssh "$PI_HOST" "docker exec homeassistant bash -c 'wget -O - https://get.hacs.xyz | bash -'"
ssh "$PI_HOST" "cd $PI_DIR && docker compose restart homeassistant"
```
Expected: script prints `INFO: Installation complete.` then container restarts.

- [ ] **Step 3: Validate HACS files exist**

Run:
```bash
ssh "$PI_HOST" "ls $PI_DIR/homeassistant/custom_components/hacs/manifest.json"
```
Expected: the path prints (file exists).

- [ ] **Step 4: Add the HACS integration in the UI**

In HA: Settings → Devices & Services → Add Integration → search "HACS" → follow the GitHub device-code auth. (Requires a free GitHub account.)
Validation: a "HACS" entry appears in the left sidebar.

- [ ] **Step 5: Commit**

```bash
git add .gitignore
git commit -m "chore: ignore HACS runtime paths"
```

---

### Task 4: Xiaomi Wi-Fi devices — local control via Xiaomi Miot Auto

**Files:**
- Create: `docs/runbook-xiaomi-tokens.md`

**Interfaces:**
- Consumes: HACS from Task 3; `secrets.yaml` region from Task 2.
- Produces: HA entities for Wi-Fi lights/switches controllable over the LAN; the documented token/region workflow reused by Task 5's vacuum.

- [ ] **Step 1: Write `docs/runbook-xiaomi-tokens.md`**

````markdown
# Xiaomi Tokens & Region

Xiaomi Miot Auto signs into your Xiaomi cloud account **once** to fetch each
device's local token, then controls devices over the LAN.

## Region matters
Devices provisioned in the Mi Home app under **Mainland China** must be read
with country `cn`. Using the wrong region returns an empty device list.
Set `xiaomi_country` in `secrets.yaml` to match the app region.

## If a device stays cloud-only
Some models only accept cloud control. Miot Auto can fall back to cloud per
device — acceptable, but those keep the higher latency. Prefer models that
report a local token.

## 2FA
If the account has 2FA, approve the login prompt in the Mi Home app / email
during integration setup.
````

- [ ] **Step 2: Install "Xiaomi Miot Auto" via HACS**

In HA: HACS → Integrations → search "Xiaomi Miot Auto" (`al-one/hass-xiaomi-miot`) → Download → restart HA when prompted.
Validation: after restart, Settings → Devices & Services → Add Integration lists "Xiaomi Miot Auto".

- [ ] **Step 3: Add the integration with cloud account**

Add Integration → "Xiaomi Miot Auto" → choose "Add devices using Xiaomi Account" → enter the account and the **region matching Mainland China (cn)**.
Validation: your Wi-Fi devices (lights, switches, luster) appear as devices with entities.

- [ ] **Step 4: Validate local control + measure latency**

Toggle one Wi-Fi light from the HA dashboard. Then time an API call from the dev machine (get a long-lived token via HA profile first, store as `$HA_TOKEN`):
```bash
time curl -s -X POST -H "Authorization: Bearer $HA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"entity_id":"light.<your_light>"}' \
  http://<pi-ip>:8123/api/services/light/toggle
```
Expected: light reacts and `real` time is well under 1 s (target < ~300 ms) — versus the 1–2 s cloud baseline.

- [ ] **Step 5: Commit**

```bash
git add docs/runbook-xiaomi-tokens.md
git commit -m "docs: Xiaomi token/region runbook"
```

---

### Task 5: Robot vacuum — room / segment cleaning

**Files:**
- Modify: `docs/runbook-xiaomi-tokens.md` (append vacuum section)

**Interfaces:**
- Consumes: Xiaomi Miot Auto + token workflow from Task 4; HACS from Task 3.
- Produces: a `vacuum.*` entity that accepts segment (room) cleaning commands, plus a map card that shows rooms in the dashboard.

- [ ] **Step 1: Confirm the vacuum entity exists**

The vacuum should already appear from Task 4's Miot Auto setup. In HA: Settings → Devices & Services → Xiaomi Miot Auto → find the vacuum device.
Validation: a `vacuum.<name>` entity exists and shows state (docked/idle).

- [ ] **Step 2: Find the room/segment IDs**

In HA: Developer Tools → Actions (Services) → `vacuum.send_command` → target the vacuum, then call with:
```yaml
command: get_room_mapping
```
Then read the result in Developer Tools → States or the response.
Validation: you get a mapping of segment IDs → room names (e.g. `16: Kitchen`).

- [ ] **Step 3: Install "Xiaomi Cloud Map Extractor" card via HACS**

In HA: HACS → Frontend → search "Xiaomi Cloud Map Extractor" (`PiotrMachowski/lovelace-xiaomi-vacuum-map-card` for interactive rooms, or the cloud map extractor for image) → Download.
Validation: the card type is available when editing a dashboard.

- [ ] **Step 4: Add the vacuum map card to a dashboard**

Edit the Overview dashboard → Add Card → "Xiaomi Vacuum Map" → set entity to your `vacuum.*` and configure the room presets using the IDs from Step 2. Example card config:
```yaml
type: custom:xiaomi-vacuum-map-card
entity: vacuum.your_vacuum
map_source:
  camera: camera.your_vacuum_map   # if using the map extractor camera
map_modes:
  - name: Rooms
    selection_type: ROOM
    rooms:
      - id: 16
        name: Kitchen
      - id: 17
        name: Bedroom
```

- [ ] **Step 5: Validate a single-room clean**

From the map card, select one room and start cleaning (or via Developer Tools):
```yaml
# vacuum.send_command
command: app_segment_clean
params: [16]
```
Expected: the vacuum leaves the dock and cleans only the selected room, then returns.

- [ ] **Step 6: Append vacuum notes to the runbook and commit**

Append to `docs/runbook-xiaomi-tokens.md`:
````markdown
## Vacuum rooms
Get segment IDs with `vacuum.send_command` → `get_room_mapping`.
Clean one room with `app_segment_clean` and `params: [<id>]`.
Room→ID mapping can change if you re-map the floor plan in the vacuum app.
````
```bash
git add docs/runbook-xiaomi-tokens.md
git commit -m "docs: vacuum room-cleaning runbook"
```

---

### Task 6: Android app, Aqara regression check, backups, final validation

**Files:**
- Modify: `README.md` (append operations section)

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: the single Android UI onto the hub; a backup routine; a documented "it all works" checklist.

- [ ] **Step 1: Connect the Android Companion app**

Install "Home Assistant" from the Play Store → it auto-discovers the Pi on the LAN (or enter `http://<pi-ip>:8123`) → log in with the owner account from Task 2.
Validation: the dashboard (with lights + vacuum map) loads on the phone; toggling a light works.

- [ ] **Step 2: Aqara hub regression check**

If the Aqara hub is desired in HA now, add it: Settings → Devices & Services → Add Integration → "Xiaomi Miot" / "Aqara". Otherwise confirm the native Aqara app still controls Zigbee devices unchanged.
Validation: Aqara-connected lights still switch (via native app at minimum). No regression.

- [ ] **Step 3: Enable HA backups**

In HA: Settings → System → Backups → Create backup (full). Optionally schedule via an automation. Also copy config off the Pi:
```bash
ssh "$PI_HOST" "cd $PI_DIR && tar czf ha-config-backup.tgz --exclude=homeassistant/home-assistant_v2.db homeassistant"
scp "$PI_HOST:$PI_DIR/ha-config-backup.tgz" ./backups/
```
Validation: `backups/ha-config-backup.tgz` exists on the dev machine.

- [ ] **Step 4: Reboot-survival test**

Run:
```bash
ssh "$PI_HOST" "sudo reboot"
# wait ~60s
curl -s -o /dev/null -w "%{http_code}\n" http://<pi-ip>:8123/
```
Expected: `200` — HA came back automatically (via `restart: unless-stopped`).

- [ ] **Step 5: Append operations section to `README.md` and commit**

Append to `README.md`:
````markdown
## Operations

- Android app: HA Companion, points to `http://<pi-ip>:8123`, one-time login.
- Backups: Settings → System → Backups; config tarball synced to `./backups/`.
- Reboot: HA auto-starts (`restart: unless-stopped`).
- Latency check: `time curl` the `light/toggle` service (see Task 4).
- Aqara Zigbee stays on its native hub; lowest priority.
````
```bash
mkdir -p backups && echo "*.tgz" > backups/.gitignore
git add README.md backups/.gitignore
git commit -m "docs: operations runbook + backup ignore"
```

---

## Self-Review

**Spec coverage:**
- One app → Task 6 (Android Companion). ✓
- One-time key setup → Task 4 (cloud account fetches tokens once). ✓
- Plugin support → Task 3 (HACS). ✓
- Vacuum room cleaning → Task 5. ✓
- Low latency / local control → Task 4 Step 4 (latency validation). ✓
- Aqara untouched → Task 6 Step 2. ✓
- Docker on Pi 3, resource-conscious → Task 1 (`mem_limit`), Task 2 (recorder tuning). ✓
- Secrets not committed → Task 1 `.gitignore`, Task 2 `secrets.yaml.example`. ✓

**Placeholder scan:** No TBD/TODO; `<pi-ip>`, `<your_light>`, `<name>`, `<id>` are user-supplied runtime values with documented sources, not plan gaps.

**Type consistency:** `secrets.yaml` keys (`xiaomi_username/password/country`) defined in Task 2, reused in Task 4. `vacuum.send_command` with `get_room_mapping` / `app_segment_clean` consistent across Task 5. Deploy vars `$PI_HOST`/`$PI_DIR` consistent throughout.
