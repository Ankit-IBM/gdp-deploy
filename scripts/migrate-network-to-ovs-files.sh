#!/usr/bin/env bash
# Write NetworkManager keyfiles for the existing OVS bridge and activate them.
# Run only from iLO/iDRAC/physical console because the live link will flap.
set -euo pipefail

PHYS_IF="${PHYS_IF:-enp3s0f0}"
BRIDGE="${BRIDGE:-br0}"
BRIDGE_NM="${BRIDGE}-nm"
HOST_IP="${HOST_IP:-192.168.2.9/24}"
GATEWAY="${GATEWAY:-192.168.2.99}"
DNS1="${DNS1:-192.168.2.1}"
DNS2="${DNS2:-8.8.8.8}"
PROFILE_DIR=/etc/NetworkManager/system-connections
STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP_DIR="/root/network-profile-backup-$STAMP"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
new_uuid() { cat /proc/sys/kernel/random/uuid; }

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root from iLO: sudo $0"; exit 1; }
command -v nmcli >/dev/null || { echo "nmcli is required"; exit 1; }
command -v ovs-vsctl >/dev/null || { echo "ovs-vsctl is required"; exit 1; }
ovs-vsctl br-exists "$BRIDGE" || { echo "OVS bridge $BRIDGE does not exist"; exit 1; }

mkdir -p "$BACKUP_DIR"
cp -a "$PROFILE_DIR"/. "$BACKUP_DIR"/ 2>/dev/null || true
log "Backed up NetworkManager profiles to $BACKUP_DIR"

BRIDGE_UUID="$(new_uuid)"
BRIDGE_PORT_UUID="$(new_uuid)"
BRIDGE_IF_UUID="$(new_uuid)"
PHYS_PORT_UUID="$(new_uuid)"
PHYS_IF_UUID="$(new_uuid)"

cat > "$PROFILE_DIR/$BRIDGE-nm.nmconnection" <<EOF
[connection]
id=$BRIDGE_NM
uuid=$BRIDGE_UUID
type=ovs-bridge
interface-name=$BRIDGE
autoconnect=yes
autoconnect-priority=100

[ovs-bridge]
EOF

cat > "$PROFILE_DIR/$BRIDGE-port.nmconnection" <<EOF
[connection]
id=$BRIDGE-port
uuid=$BRIDGE_PORT_UUID
type=ovs-port
interface-name=$BRIDGE
master=$BRIDGE_NM
slave-type=ovs-bridge
autoconnect=yes

[ovs-port]
EOF

cat > "$PROFILE_DIR/$BRIDGE-int.nmconnection" <<EOF
[connection]
id=$BRIDGE-int
uuid=$BRIDGE_IF_UUID
type=ovs-interface
interface-name=$BRIDGE
master=$BRIDGE-port
slave-type=ovs-port
autoconnect=yes

[ovs-interface]

[ipv4]
method=manual
address1=$HOST_IP,$GATEWAY
dns=$DNS1;$DNS2;
ignore-auto-dns=yes

[ipv6]
method=disabled
EOF

cat > "$PROFILE_DIR/$PHYS_IF-port.nmconnection" <<EOF
[connection]
id=$PHYS_IF-port
uuid=$PHYS_PORT_UUID
type=ovs-port
interface-name=$PHYS_IF
master=$BRIDGE_NM
slave-type=ovs-bridge
autoconnect=yes

[ovs-port]
EOF

cat > "$PROFILE_DIR/$PHYS_IF.nmconnection" <<EOF
[connection]
id=$PHYS_IF-ovs
uuid=$PHYS_IF_UUID
type=ethernet
interface-name=$PHYS_IF
master=$PHYS_IF-port
slave-type=ovs-port
autoconnect=yes

[ethernet]

[ipv4]
method=disabled

[ipv6]
method=disabled
EOF

chmod 600 "$PROFILE_DIR"/*.nmconnection
nmcli connection reload

log "Activating $BRIDGE and moving host IP to $BRIDGE-int"
nmcli connection up "$BRIDGE_NM" || true
nmcli connection up "$BRIDGE-port" || true
nmcli connection up "$BRIDGE-int"

log "Activating physical uplink $PHYS_IF through OVS"
nmcli connection up "$PHYS_IF-port" || true
nmcli connection up "$PHYS_IF-ovs"

sleep 5
if ping -c 3 -W 2 "$GATEWAY" >/dev/null 2>&1; then
  log "SUCCESS: gateway $GATEWAY reachable through $BRIDGE"
  log "OVS ports:"
  ovs-vsctl list-ports "$BRIDGE"
  exit 0
fi

log "FAILURE: gateway $GATEWAY is unreachable; rolling back"
for profile in "$PHYS_IF-ovs" "$PHYS_IF-port" "$BRIDGE-int" "$BRIDGE-port" "$BRIDGE_NM"; do
  nmcli connection down "$profile" 2>/dev/null || true
done
rm -f "$PROFILE_DIR/$BRIDGE-nm.nmconnection" \
      "$PROFILE_DIR/$BRIDGE-port.nmconnection" \
      "$PROFILE_DIR/$BRIDGE-int.nmconnection" \
      "$PROFILE_DIR/$PHYS_IF-port.nmconnection" \
      "$PROFILE_DIR/$PHYS_IF.nmconnection"
cp -a "$BACKUP_DIR"/. "$PROFILE_DIR"/
chmod 600 "$PROFILE_DIR"/*.nmconnection
nmcli connection reload
nmcli connection up "$PHYS_IF" 2>/dev/null || true
log "Rollback complete; backup retained at $BACKUP_DIR"
exit 1
