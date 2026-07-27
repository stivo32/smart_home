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

## Mac dry-run

Docker Desktop on macOS has no `network_mode: host`, so use the override
(maps port 8123, no LAN device discovery — for validating boot/config/HACS only):

```bash
docker compose -f docker-compose.yml -f docker-compose.mac.yml up -d
open http://localhost:8123
```
