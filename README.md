# ThermOS

Think: NixOS meets macOS.

A declarative Linux system. Easy to use, intuitive to configure.

> [!NOTE]
> Under active research. Contributions welcome

## For users

NixOS proved that declarative system management works. But it was built
by hackers for hackers. Configuring it means editing Nix code, and
there is no boundary between what users should see and what modules use
internally. There have been [attempts](https://github.com/nix-gui/nix-gui)
at a GUI, and tools like [MyNixOS](https://mynixos.com/) exist, but they
feel bolted on: form renderers for thousands of options, most of which
no user should ever touch.

ThermOS draws that boundary. Module options that face users are separated
from the internal wiring that modules use to talk to each other. This
makes a real configuration interface possible. Something like GNOME
Settings, where enabling SSH or adding a user goes through the same
deterministic layers that Nix users rely on today.

## For engineers

NixOS modules share a global `config` namespace. Any module can read any
option without declaring the dependency. An internal refactoring is
indistinguishable from a user-facing breakage. Every release cycle,
things break because the coupling points are everywhere. There is
[ongoing](https://github.com/NixOS/rfcs/pull/189)
[work](https://github.com/NixOS/nixpkgs/pull/506343) to add contracts to
NixOS, but it's retrofitting them onto the global namespace.

ThermOS is built on [Adios](https://github.com/adisbladis/adios), where
contracts are the foundation. Explicit inputs, typed options, pub/sub.
Modules declare what they need. Conflicts are caught at eval time. The
dependency graph is visible and inspectable.

## How it works

Modules publish typed data to **contracts** (etc files, systemd units, users,
packages). **Builders** subscribe to contracts and produce derivations.

This diagram is rendered [interactive on the website](https://hsjobeki.github.io/ThermOS/)

```
core/base.nix        publishes /etc entries, users, units
services/getty.nix    publishes units, /etc/pam.d
        |
        v
  contracts/         typed schemas with merge functions
        |            (conflict detection, deep merge, set union)
        v
  builders/          subscribe, produce store paths
        |
        v
  rootfs             FHS tree ready for nspawn or disk image
  initrd + image     kernel modules, ext4 disk for QEMU boot
```

## Try it

Requires Nix. Container boot needs `systemd-nspawn`, QEMU boot needs
`qemu-system-x86_64` with KVM.

```
./run.sh              # nspawn container
./run.sh --qemu       # QEMU VM (serial console + SSH on :2222)
./run.sh --shell      # root shell without systemd
```

Login: `root` / `thermos`. Stop nspawn: `poweroff`. Stop QEMU: `Ctrl-a x`.

### SSH in (QEMU)

`./run.sh --qemu` forwards host port 2222 to the VM's sshd. Root login is
key-only; the authorized key is in `systems/qemu.nix`. Swap in your own key
(`~/.ssh/id_ed25519.pub`).

```
ssh -p 2222 root@localhost
```

The VM uses a static `10.0.2.15/24` because DHCP needs AF_PACKET, which the
kernel does not load yet.

## Status

Boots on real HW directly from UEFI

Upcomming: systemd-boot

### Roadmap

- [x] Contract-based module system with pub/sub data flow
- [x] Boot in nspawn container (systemd, PAM, SSH, D-Bus)
- [x] Boot in QEMU with kernel, initrd, and ext4 disk image
- [x] SSH login verified end-to-end in a VM
- [x] Boot on real hardware (direct UEFI currently)
- [ ] Live system management: rebuild, switch, rollback
- [ ] A Wayland desktop on the same verified base
- [ ] Secret and state provisioning outside the root image
- [ ] Immutable, cryptographically verified images (UKI, dm-verity, Secure Boot)
- [ ] Atomic A/B updates with rollback
- [ ] Settings-style configuration UI over the contract layer

## Layout

```
entrypoint.nix          wires module groups into the adios tree
systems/
  test.nix              nspawn configuration (SSH key, root password)
  qemu.nix              QEMU configuration (serial console, no VTs)
modules/
  contracts/            typed data schemas (etc, units, users, ...)
  builders/             derivation producers (rootfs, initrd, image, etc, units, users)
  core/                 base system (root user, FHS, default target)
  middleware/           data transformers (PAM store path resolution)
  services/             service modules (getty, dbus, openssh)
```

## Tests

```
nix-unit tests/eval.nix              # eval tests (contract merges, tree structure)
nix-build tests/build.nix            # build tests (file formats, rootfs layout)
nix-build tests/container.nix        # container tests (real systemd boot, PAM auth)
```
