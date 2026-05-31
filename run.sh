#!/usr/bin/env bash
# Boot ThermOS via nspawn or QEMU.
#
# Usage:
#   ./run.sh              # build + boot nspawn
#   ./run.sh --shell      # build + drop into root shell (no systemd)
#   ./run.sh --qemu       # build + boot QEMU (serial console)
#   ./run.sh /nix/...     # boot a pre-built rootfs path (nspawn)
#
# Stop nspawn: type 'poweroff' inside the container,
#              or run 'sudo machinectl poweroff thermos' from another terminal.
# Stop QEMU:  Ctrl-a x
set -euo pipefail

MACHINE="thermos"
MODE="boot"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shell) MODE="shell"; shift ;;
    --qemu) MODE="qemu"; shift ;;
    -h|--help) echo "Usage: $0 [--shell|--qemu] [rootfs-store-path]"; exit 0 ;;
    *) ROOTFS="$1"; shift ;;
  esac
done

if [[ "$MODE" == "qemu" ]]; then
  SYSTEM="systems/qemu.nix"
  echo "building kernel + initrd + image"
  KERNEL=$(nix-build "$SYSTEM" -A kernel --no-out-link)
  INITRD=$(nix-build "$SYSTEM" -A initrd --no-out-link)
  IMAGE=$(nix-build "$SYSTEM" -A image --no-out-link)

  WORKDIR=$(mktemp -d /tmp/thermos-qemu.XXXXXX)
  cleanup() { rm -rf "$WORKDIR"; }
  trap cleanup EXIT

  # Image must be writable (QEMU writes to it)
  cp "$IMAGE" "$WORKDIR/disk.img"
  chmod u+w "$WORKDIR/disk.img"

  echo ""
  echo "  ThermOS - QEMU boot"
  echo "  Login:  root / thermos"
  echo "  Stop:   Ctrl-a x"
  echo ""

  qemu-system-x86_64 \
    -nographic \
    -no-reboot \
    -kernel "$KERNEL/bzImage" \
    -initrd "$INITRD/initrd" \
    -append "root=/dev/vda console=ttyS0 loglevel=4" \
    -drive "file=$WORKDIR/disk.img,if=virtio,format=raw" \
    -m 512 \
    -smp 2 \
    -enable-kvm

  exit 0
fi

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
