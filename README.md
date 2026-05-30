# ThermOS

A Linux system built with Nix. Configurable by anyone, hackable by engineers.

Early stage -- boots to a root shell today. Working toward a system you
can configure through a GUI, backed by the same typed infrastructure that
builds the OS.

### For users

NixOS proved that declarative system management works. But it was built
by hackers for hackers -- configuring it means editing Nix code, and
there is no boundary between what users should see and what modules use
internally. There have been [attempts](https://github.com/nix-gui/nix-gui)
at a GUI, and tools like [MyNixOS](https://mynixos.com/) exist, but they
feel bolted on -- form renderers for thousands of options, most of which
no user should ever touch.

ThermOS draws that boundary. Module options that face users are separated
from the internal wiring that modules use to talk to each other. This
makes a real configuration interface possible -- not a code editor, but
something closer to GNOME Settings, where enabling SSH or adding a user
just works.

### For engineers

NixOS modules share a global `config` namespace. Any module can read any
option without declaring the dependency. An internal refactoring is
indistinguishable from a user-facing breakage. Every release cycle,
things break because the coupling points are everywhere. There is
[ongoing](https://github.com/NixOS/rfcs/pull/189)
[work](https://github.com/NixOS/nixpkgs/pull/506343) to add contracts to
NixOS, but it's retrofitting them onto the global namespace.

ThermOS is built on [Adios](https://github.com/adisbladis/adios), where
contracts are the foundation -- explicit inputs, typed options, pub/sub.
Modules declare what they need. Conflicts are caught at eval time. The
dependency graph is visible and inspectable.

## How it works

Modules publish typed data to **contracts** (etc files, systemd units, users,
packages). **Builders** subscribe to contracts and produce derivations. The
module tree is wired in `entrypoint.nix`; there is no `eval-config.nix`.

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

Early. Boots to a root shell via `systemd-nspawn`. Getty, PAM, static
`/etc/passwd`.

### Roadmap

**System infrastructure**

- [ ] D-Bus, OpenSSH
- [ ] Kernel, initrd, boot
- [ ] Disk image builder (repart)
- [ ] System switch (rebuild + reload)
- [ ] Secure Boot / measured boot

**Configuration interface** (under research)

- [ ] Define user-facing options
- [ ] JSON schema export for module interfaces
- [ ] Configuration persistence (declarative, GUI-writable format)
- [ ] Rebuild + apply pipeline (the system is immutable -- changes require a rebuild)
- [ ] CLI for system configuration
- [ ] GUI (gtk like libadwaita?)

ThermOS has the benefit of a proper user model from day one.

Insights may feed back into the NixOS module system and options, but retrofitting
this will take years to deliver the same experience, if it ever will.

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

Eval tests (pure, fast -- no builds):

```
nix-unit tests/eval.nix
```

Build tests (builds derivations, checks structure):

```
nix-build tests/build.nix
```

Single build test:

```
nix-build tests/build.nix -A unitVerify
```

Container tests (full NixOS VM, slow):

```
nix-build tests/container.nix
```
