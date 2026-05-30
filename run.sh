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
  ROOTFS=$(nix-build default.nix -A rootfs --no-out-link)
fi

echo "rootfs: $ROOTFS"

WORKDIR=$(mktemp -d /tmp/thermos-run.XXXXXX)
cleanup() { sudo rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "preparing copy"
cp -a "$ROOTFS" "$WORKDIR/rootfs"
chmod -R u+w "$WORKDIR/rootfs"

# Unlock root. Password: thermos
HASH='$6$thermos$H0ll22GovTVsmgXyGSxBB1rAwU.QF6D/nFspidCXj0vFJ6YzUUzhs1r8/mEiXnb0IUUP8t2tChAmwA.vEXH9G/'
sed -i "s|^root:!:|root:${HASH}:|" "$WORKDIR/rootfs/etc/shadow"
sudo chown root:root "$WORKDIR/rootfs/etc/shadow"
sudo chmod 0640 "$WORKDIR/rootfs/etc/shadow"


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
  echo "  │  ThermOS - nspawn boot                              │"
  echo "  │                                                  │"
  echo "  │  Login:  root / thermos                             │"
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