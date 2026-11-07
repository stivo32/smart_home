# Smart Home Hub

Home Assistant in Docker on a Raspberry Pi 3, for local control of Xiaomi Wi-Fi devices.

## Deploy (Raspberry Pi)

On the dev machine (`pi` is the ssh alias → admin@192.168.1.41):

```bash
export PI_HOST=pi
export PI_DIR=/home/admin/smart_home
rsync -av --exclude='homeassistant/secrets.yaml' --exclude='homeassistant/.storage' \
  --exclude='homeassistant/home-assistant_v2.db' ./ "$PI_HOST:$PI_DIR/"
```

On the Pi:

```bash
cd /home/admin/smart_home
docker compose up -d
docker compose logs -f homeassistant
```

Open `http://<pi-ip>:8123`.

### Dashboard reboot / power-off buttons

The "Малинка" buttons call `shell_command.pi_reboot` / `pi_poweroff`, which SSH
from the HA container to the host as a locked-down `ha-power` user. That host
side (user, dispatcher, sudoers, key, pinned host key) is not in the HA config,
so after reinstalling the Pi run once, on the Pi:

```bash
cd /home/admin/smart_home
sudo sh scripts/pi-power/setup.sh
docker compose restart homeassistant
```

It is idempotent and ends with a harmless self-test (`pi-power: ready`). The
private key lives in `homeassistant/.ssh/` (git-ignored); if it survived the
reinstall it is reused, otherwise a new one is generated.

## Mac dry-run

Docker Desktop on macOS has no `network_mode: host`, so use the override
(maps port 8123, no LAN device discovery — for validating boot/config/HACS only):

```bash
docker compose -f docker-compose.yml -f docker-compose.mac.yml up -d
open http://localhost:8123
```
