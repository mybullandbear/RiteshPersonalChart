#!/bin/bash
# Setup Swap File to prevent Out Of Memory (OOM) errors on small VMs (e.g. e2-micro with 1GB RAM)

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo)"
  exit 1
fi

SWAP_SIZE="2G"
SWAP_PATH="/swapfile"

if [ -f "$SWAP_PATH" ]; then
    echo "Swap file already exists."
    exit 0
fi

echo "Creating ${SWAP_SIZE} swap file at ${SWAP_PATH}..."
fallocate -l $SWAP_SIZE $SWAP_PATH
chmod 600 $SWAP_PATH
mkswap $SWAP_PATH
swapon $SWAP_PATH

# Make permanent
if ! grep -q "$SWAP_PATH" /etc/fstab; then
    echo "$SWAP_PATH none swap sw 0 0" >> /etc/fstab
fi

echo "Swap setup complete!"
free -h
