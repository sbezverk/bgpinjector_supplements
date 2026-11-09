#!/usr/bin/env bash

set -euo pipefail

# XRd needs higher host kernel limits than a default Ubuntu installation.
# Run this after every host reboot and before starting the Compose testbed.

if [[ ${EUID} -ne 0 ]]; then
  echo "ERROR: run this script as root (for example: sudo $0)" >&2
  exit 1
fi

modprobe br_netfilter || true

if [[ ! -e /proc/sys/net/bridge/bridge-nf-call-iptables ]]; then
  echo "ERROR: br_netfilter sysctls are unavailable after loading the module" >&2
  exit 1
fi

sysctl -w net.bridge.bridge-nf-call-iptables=0
sysctl -w net.bridge.bridge-nf-call-ip6tables=0
sysctl -w fs.inotify.max_user_instances=65536
sysctl -w fs.inotify.max_user_watches=65536
sysctl -w net.ipv4.udp_mem="1124736 10000000 67108864"
sysctl -w net.core.netdev_max_backlog=300000
sysctl -w net.core.optmem_max=67108864
sysctl -w net.core.rmem_max=67108864
sysctl -w net.core.rmem_default=67108864
sysctl -w net.core.wmem_max=67108864
sysctl -w net.core.wmem_default=67108864

echo "XRd host kernel parameters are ready."
