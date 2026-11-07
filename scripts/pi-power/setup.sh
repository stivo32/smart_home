#!/bin/sh
# Sets up the host side of the dashboard "Перезагрузить" / "Выключить" buttons.
#
# HA runs in a container, so it reaches the host over SSH on 127.0.0.1 as a
# dedicated user `ha-power`. The key is locked down three ways:
#   - authorized_keys: from="127.0.0.1",restrict,command=<dispatcher>
#   - the dispatcher (ha-pi-power) only accepts check / reboot / poweroff
#   - sudoers lets ha-power run only `systemctl --no-block reboot|poweroff`
#
# Idempotent. Run on the Pi from the repo root after a reinstall:
#   sudo sh scripts/pi-power/setup.sh
set -eu

HA_CONFIG="${HA_CONFIG:-$(cd "$(dirname "$0")/../.." && pwd)/homeassistant}"
SSH_DIR="$HA_CONFIG/.ssh"
KEY="$SSH_DIR/pi_power"
USER_NAME=ha-power
USER_HOME=/var/lib/ha-power
DISPATCHER=/usr/local/sbin/ha-pi-power
SUDOERS=/etc/sudoers.d/ha-pi-power

[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
[ -f "$HA_CONFIG/configuration.yaml" ] || { echo "no HA config at $HA_CONFIG" >&2; exit 1; }

# 1. System user. It needs a real shell: sshd runs the forced command through it.
if ! id "$USER_NAME" >/dev/null 2>&1; then
    useradd --system --home-dir "$USER_HOME" --create-home --shell /bin/sh "$USER_NAME"
fi

# 2. Dispatcher.
install -o root -g root -m 0755 "$(dirname "$0")/ha-pi-power" "$DISPATCHER"

# 3. sudoers, validated before it goes live.
tmp=$(mktemp)
printf '%s\n' "$USER_NAME ALL=(root) NOPASSWD: /usr/bin/systemctl --no-block reboot, /usr/bin/systemctl --no-block poweroff" > "$tmp"
visudo -cf "$tmp" >/dev/null
install -o root -g root -m 0440 "$tmp" "$SUDOERS"
rm -f "$tmp"

# 4. Key pair in the HA config dir (git-ignored). Reused if it survived.
install -d -o root -g root -m 0700 "$SSH_DIR"
if [ ! -f "$KEY" ]; then
    ssh-keygen -q -t ed25519 -N '' -C homeassistant-pi-power -f "$KEY"
fi
chmod 600 "$KEY"

# 5. authorized_keys, root-owned so ha-power can't loosen its own restrictions.
install -d -o root -g root -m 0755 "$USER_HOME/.ssh"
printf 'from="127.0.0.1",restrict,command="%s" %s\n' "$DISPATCHER" "$(cat "$KEY.pub")" \
    > "$USER_HOME/.ssh/authorized_keys"
chown root:root "$USER_HOME/.ssh/authorized_keys"
chmod 644 "$USER_HOME/.ssh/authorized_keys"

# 6. Pin the host key, so the container never trusts an unknown 127.0.0.1.
printf '127.0.0.1 %s\n' "$(cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub)" \
    > "$SSH_DIR/pi_power_known_hosts"
chmod 600 "$SSH_DIR/pi_power_known_hosts"

# 7. Self-test with the same options HA uses. `check` powers nothing off.
out=$(ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$SSH_DIR/pi_power_known_hosts" \
    "$USER_NAME@127.0.0.1" check)
[ "$out" = ha-pi-power-ready ] || { echo "self-test failed: $out" >&2; exit 1; }
echo "pi-power: ready"
