#!/usr/bin/env bash
# Boot ThermOS via nspawn.
#
# Usage:
#   ./run.sh              # build + boot with systemd
#   ./run.sh --shell      # build + drop into root shell (no systemd)
#   ./run.sh /nix/...     # boot a pre-built rootfs path
#
# Stop: type 'poweroff' inside the container,
#       or run 'sudo machinectl poweroff thermos' from another terminal.
set -euo pipefail

MACHINE="thermos"
MODE="boot"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shell) MODE="shell"; shift ;;
    -h|--help) echo "Usage: $0 [--shell] [rootfs-store-path]"; exit 0 ;;
    *) ROOTFS="$1"; shift ;;
  esac
done

if [[ -z "${ROOTFS:-}" ]]; then
  echo "building rootfs"
  ROOTFS=$(nix-build systems/test.nix -A rootfs --no-out-link)
fi

echo "rootfs: $ROOTFS"

WORKDIR=$(mktemp -d /tmp/thermos-run.XXXXXX)
cleanup() { sudo rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "preparing copy"
sudo cp -a "$ROOTFS" "$WORKDIR/rootfs"
sudo chmod -R u+w "$WORKDIR/rootfs"

sudo rm -rf "/run/systemd/nspawn/unix-export/$MACHINE"

if [[ "$MODE" == "shell" ]]; then
  echo ""
  echo "root shell (no systemd)"
  echo ""
  sudo systemd-nspawn \
    --machine="$MACHINE" \
    -D "$WORKDIR/rootfs" \
    --bind-ro=/nix/store
else
  echo ""
  echo "  ┌──────────────────────────────────────────────────┐"
  echo "  │  ThermOS - nspawn boot                           │"
  echo "  │                                                  │"
  echo "  │  Login:  root / thermos                          │"
  echo "  │  Stop:   poweroff                                │"
  echo "  │    or:   sudo machinectl poweroff $MACHINE       │"
  echo "  └──────────────────────────────────────────────────┘"
  echo ""
  sudo systemd-nspawn \
    --boot \
    --machine="$MACHINE" \
    -D "$WORKDIR/rootfs" \
    --bind-ro=/nix/store
fi