# ThermOS

Think: NixOS meets macOS.

A declarative Linux system. Easy to use, joyful to configure.

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
makes a real configuration interface possible. Not a code editor, but
something closer to GNOME Settings, where enabling SSH or adding a user
just works.

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
```

## Try it

Requires Nix and `systemd-nspawn` (any systemd-based Linux host).

```
./run.sh
```

This builds the rootfs and boots it in a container. Login: `root` / `thermos`.
Type `poweroff` to stop.

```
./run.sh --shell      # root shell without systemd
./run.sh /nix/...     # boot a pre-built rootfs path
```

## Status

**POC**. Currently Boots to a root shell via `systemd-nspawn`. Getty, PAM, static
`/etc/passwd`.

It will be extended further to proof it can solve the stated problems.

### Roadmap

- Boot a real system with its own kernel, initrd, and boot chain
- Immutable, cryptographically verified disk images
- Live system management: rebuild, switch, rollback
- Configuration interface with CLI and GUI

ThermOS has the benefit of a proper user model from day one.

Insights may feed back into the NixOS module system and options, but retrofitting
this will take some time to deliver the same experience.

## Layout

```
entrypoint.nix          wires module groups into the adios tree
modules/
  contracts/            typed data schemas (etc, units, users, ...)
  builders/             derivation producers (rootfs, toplevel, etc, units, users)
  core/                 base system (root user, FHS, default target)
  services/             service modules (getty)
```

## Tests

Eval tests:

```
nix-unit tests/eval.nix
```

Build tests:

```
nix-build tests/build.nix
nix-build tests/build.nix -A unitVerify
```

Container tests:

```
nix-build tests/container.nix
```

VM Tests:

Comming, as soon as we can boot our own!
