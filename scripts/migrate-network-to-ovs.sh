#!/usr/bin/env bash
# Migrates the host's network config from the physical NIC directly onto the
# existing OVS bridge (br0), and adds the NIC as a trunk port on that bridge.
# This lets guest VMs attached to br0 reach the same LAN as the host.
#
# Run this ONLY from an out-of-band console (iLO/iDRAC/physical), not over a
# session that depends on the NIC being migrated (enp3s0f0). If run over SSH/RDP
# through enp3s0f0, the session may drop during the migration.
#
# Usage: sudo ./scripts/migrate-network-to-ovs.sh
set -euo pipefail

PHYS_IF="${PHYS_IF:-enp3s0f0}"
BRIDGE="${BRIDGE:-br0}"
HOST_IP="${HOST_IP:-192.168.2.9/24}"
GATEWAY="${GATEWAY:-192.168.2.99}"
DNS1="${DNS1:-192.168.2.1}"
DNS2="${DNS2:-8.8.8.8}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root (sudo)."; exit 1; }

BACKUP_DIR="/root/network-migration-backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"
log "Backing up current NetworkManager profiles to $BACKUP_DIR"
cp -a /etc/NetworkManager/system-connections/. "$BACKUP_DIR/" 2>/dev/null || true

log "Verifying $PHYS_IF is currently connected and $BRIDGE exists via OVS"
nmcli -t -f DEVICE,STATE dev status | grep -q "^${PHYS_IF}:connected" || { echo "ERROR: $PHYS_IF is not connected"; exit 1; }
ovs-vsctl br-exists "$BRIDGE" || { echo "ERROR: OVS bridge $BRIDGE does not exist"; exit 1; }

log "Creating NetworkManager-managed OVS bridge/port/interface profiles for $BRIDGE"
nmcli con add type ovs-bridge conn.interface "$BRIDGE" con-name "${BRIDGE}-nm"
nmcli con add type ovs-port conn.interface "$BRIDGE" master "${BRIDGE}-nm" con-name "${BRIDGE}-port"
nmcli con add type ovs-interface slave-type ovs-port conn.interface "$BRIDGE" master "${BRIDGE}-port" con-name "${BRIDGE}-int" \
  ipv4.method manual ipv4.addresses "$HOST_IP" ipv4.gateway "$GATEWAY" ipv4.dns "${DNS1},${DNS2}" ipv6.method disabled

log "Creating OVS port/interface profiles for $PHYS_IF (trunk into $BRIDGE)"
nmcli con add type ovs-port conn.interface "$PHYS_IF" master "${BRIDGE}-nm" con-name "${PHYS_IF}-port"
nmcli con add type ethernet conn.interface "$PHYS_IF" master "${PHYS_IF}-port" con-name "${PHYS_IF}-ovs"

log "Bringing up the bridge (host regains its IP via $BRIDGE) before touching $PHYS_IF"
nmcli con up "${BRIDGE}-nm"
nmcli con up "${BRIDGE}-port"
nmcli con up "${BRIDGE}-int"

sleep 3
log "Retiring the direct $PHYS_IF connection and enslaving it to $BRIDGE"
nmcli con down "$PHYS_IF" || true
nmcli con up "${PHYS_IF}-ovs"

sleep 3
log "Verifying connectivity"
if ping -c 3 -W 2 "$GATEWAY" >/dev/null 2>&1; then
  log "SUCCESS: gateway $GATEWAY is reachable via $BRIDGE"
else
  log "WARNING: gateway $GATEWAY is NOT reachable. Rolling back."
  nmcli con down "${PHYS_IF}-ovs" 2>/dev/null || true
  nmcli con down "${BRIDGE}-int" 2>/dev/null || true
  nmcli con down "${BRIDGE}-port" 2>/dev/null || true
  nmcli con down "${BRIDGE}-nm" 2>/dev/null || true
  nmcli con delete "${PHYS_IF}-ovs" "${PHYS_IF}-port" "${BRIDGE}-int" "${BRIDGE}-port" "${BRIDGE}-nm" 2>/dev/null || true
  nmcli con up "$PHYS_IF"
  log "Rolled back to original $PHYS_IF configuration. Backup preserved at $BACKUP_DIR"
  exit 1
fi

log "Current bridge port membership:"
ovs-vsctl list-ports "$BRIDGE"
log "Migration complete. VM guests attached to $BRIDGE now share the LAN uplink."
