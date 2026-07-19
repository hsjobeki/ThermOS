# Container tests: nix-build tests/container.nix
let
  thermos = import ../default.nix { };
  pkgs = thermos.pkgs;
  thermosLib = import ./lib.nix;

  unitsDrv = (thermos.tree.modules.builders.modules.units { }).derivation;
  usersDrv = (thermos.tree.modules.builders.modules.users { }).derivation;
  rootfsDrv = (thermos.tree.modules.builders.modules.rootfs { }).derivation;

  # PAM test: build a rootfs with a known password
  passwordHash = "\$6\$thermostest\$d8h//689.ccFiiNJKscJ9ght7bWyk0WDVBXEHKrMahTIPHLfsMmKeyGgfClxvbpWsBxd/ydyeBzFVWOCLPEiZ1";
  pamThermosTree = thermos.configure {
    options = {
      "/core/base" = {
        rootHashedPassword = passwordHash;
      };
    };
  };
  pamRootfsDrv = (pamThermosTree.modules.builders.modules.rootfs { }).derivation;

  # Phase 1 desktop acceptance: rootfs with the thermos-daemon + polkit enabled and
  # a known root password (to log in over the console and exercise the daemon).
  desktopTree = thermos.configure {
    options = {
      "/core/base" = {
        rootHashedPassword = passwordHash;
      };
      "/services/polkit" = {
        enable = true;
      };
      "/services/thermos-daemon" = {
        enable = true;
      };
    };
  };
  desktopRootfsDrv = (desktopTree.modules.builders.modules.rootfs { }).derivation;

  # SSH-over-VDE boot artifacts (kernel + systemd initrd + image) for an
  # SSH-reachable ThermOS; extraOptions merges in per-test overrides.
  sshKeys = import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs;
  sshBaseOptions = {
    "/core/initrd-network" = {
      enable = true;
    };
    "/services/networkd" = {
      enable = true;
      useDHCP = false;
      addresses = [ "192.168.1.2/24" ];
    };
    "/services/openssh" = {
      permitRootLogin = "prohibit-password";
      authorizedKeys = {
        root = [ sshKeys.snakeOilEd25519PublicKey ];
      };
    };
    "/services/getty" = {
      ttys = [ ];
      serialTtys = [ ];
    };
  };
  sshArtifacts =
    extraOptions:
    let
      t = thermos.configure { options = sshBaseOptions // extraOptions; };
      i = t.modules.builders.modules.initrd { };
      img = t.modules.builders.modules.image { };
    in
    {
      kernel = i.kernel;
      initrd = i.derivation;
      image = img.derivation;
      inherit (img) rootPartUUID;
    };

in
{
  # systemd-analyze verify with real /run/systemd/
  unitVerify = pkgs.testers.runNixOSTest {
    name = "thermos-unit-verify";

    containers.verifier =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.systemd ];
      };

    testScript = ''
      verifier.start()
      verifier.wait_for_unit("multi-user.target")

      verifier.succeed(
          "find ${unitsDrv}/etc/systemd/system -type f -name '*.service' "
          "| while read unit; do "
          "  echo \"Verifying $(basename $unit)...\"; "
          "  systemd-analyze verify --recursive-errors=no $unit; "
          "done"
      )
    '';
  };

  # Boot rootfs under nspawn, verify multi-user.target
  bootRootfs = pkgs.testers.runNixOSTest {
    name = "thermos-boot-rootfs";

    nodes.host =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.systemd ];
        virtualisation.memorySize = 1024;
        virtualisation.diskSize = 4096;
      };

    testScript = ''
      host.start()
      host.wait_for_unit("multi-user.target")

      # nspawn needs writable /run, /tmp, /var
      host.succeed("cp -a ${rootfsDrv} /rootfs")
      host.succeed("chmod -R u+w /rootfs")

      host.succeed(
          "systemd-nspawn"
          " --boot"
          " -D /rootfs"
          " --bind-ro=/nix/store"
          " --register=no"
          " --quiet"
          " &>/tmp/nspawn.log &"
          " echo $! > /tmp/nspawn.pid"
      )

      import time
      for _ in range(60):
          time.sleep(1)
          rc, output = host.execute("cat /tmp/nspawn.log")
          if "login:" in output:
              break
      else:
          host.succeed("cat /tmp/nspawn.log >&2")
          raise Exception("thermos container did not reach login prompt within 60s")

      boot_log = host.succeed("cat /tmp/nspawn.log")

      assert "Welcome to ThermOS" in boot_log, f"Missing ThermOS banner in log:\n{boot_log}"
      assert "Multi-User System" in boot_log, f"multi-user.target not queued:\n{boot_log}"
      assert "login:" in boot_log, f"No login prompt in log:\n{boot_log}"
      assert "Started D-Bus System Message Bus" in boot_log, f"dbus not started:\n{boot_log}"

      host.execute("kill $(cat /tmp/nspawn.pid) 2>/dev/null; true")
    '';
  };

  # Verify users resolve via getent
  usersExist = pkgs.testers.runNixOSTest {
    name = "thermos-users-exist";

    containers.machine =
      { ... }:
      {
        systemd.tmpfiles.rules = [
          "C+ /etc/passwd  0644 root root - ${usersDrv}/etc/passwd"
          "C+ /etc/group   0644 root root - ${usersDrv}/etc/group"
          "C+ /etc/shadow  0640 root root - ${usersDrv}/etc/shadow"
        ];
      };

    testScript = ''
      machine.start()
      machine.wait_for_unit("multi-user.target")

      result = machine.succeed("getent passwd root")
      assert result.startswith("root:"), f"unexpected root entry: {result}"

      result = machine.succeed("getent passwd nobody")
      assert result.startswith("nobody:"), f"unexpected nobody entry: {result}"

      result = machine.succeed("getent group root")
      assert result.startswith("root:"), f"unexpected root group entry: {result}"

      result = machine.succeed("getent passwd messagebus")
      assert result.startswith("messagebus:"), f"unexpected messagebus entry: {result}"

      result = machine.succeed("getent group messagebus")
      assert result.startswith("messagebus:"), f"unexpected messagebus group entry: {result}"

      machine.succeed("test -f /etc/shadow")
    '';
  };

  # PAM auth end-to-end
  pamAuth = pkgs.testers.runNixOSTest {
    name = "thermos-pam-auth";

    nodes.host =
      { pkgs, ... }:
      {
        environment.systemPackages = [
          pkgs.systemd
          pkgs.expect
        ];
        virtualisation.memorySize = 1024;
        virtualisation.diskSize = 4096;
      };

    testScript = ''
      host.start()
      host.wait_for_unit("multi-user.target")

      host.succeed("cp -a ${pamRootfsDrv} /rootfs && chmod -R u+w /rootfs")

      # expect script: spawn nspawn, log in as root, verify shell works
      host.succeed("""cat > /tmp/login.exp << 'EXPECT'
      set timeout 120
      spawn systemd-nspawn --boot -D /rootfs --bind-ro=/nix/store --register=no
      expect {
          "login:" {}
          timeout { puts "FAIL: no login prompt"; exit 1 }
      }
      send "root\r"
      expect {
          "Password:" {}
          timeout { puts "FAIL: no password prompt"; exit 1 }
      }
      send "thermostest\r"
      expect {
          -re {#\s*$} {}
          timeout { puts "FAIL: no shell prompt after auth"; exit 1 }
      }
      send "whoami\r"
      expect {
          "root" {}
          timeout { puts "FAIL: whoami did not return root"; exit 1 }
      }
      send "echo AUTH_SUCCESS\r"
      expect {
          "AUTH_SUCCESS" { puts "PAM auth ok" }
          timeout { puts "FAIL: echo marker not received"; exit 1 }
      }
      send "poweroff\r"
      expect eof
      EXPECT
      """)

      result = host.succeed("expect /tmp/login.exp")
      assert "PAM auth ok" in result, f"Auth failed:\n{result}"
    '';
  };

  # Phase 1 acceptance: the thermos-daemon runs as its own system unit and user,
  # serves UpdateState over D-Bus, and its privileged StartUpdate is authorized
  # through polkit and invoked. Boots the rootfs under nspawn, logs in over the
  # console (PAM), and exercises the daemon exactly as a privileged client would.
  desktopDaemon = pkgs.testers.runNixOSTest {
    name = "thermos-desktop-daemon";

    nodes.host =
      { pkgs, ... }:
      {
        environment.systemPackages = [
          pkgs.systemd
          pkgs.expect
        ];
        virtualisation.memorySize = 1024;
        virtualisation.diskSize = 4096;
      };

    testScript = ''
      host.start()
      host.wait_for_unit("multi-user.target")

      host.succeed("cp -a ${desktopRootfsDrv} /rootfs && chmod -R u+w /rootfs")

      host.succeed("""cat > /tmp/daemon.exp << 'EXPECT'
      set timeout 240
      spawn systemd-nspawn --boot -D /rootfs --bind-ro=/nix/store --register=no
      expect { "login:" {} timeout { puts "FAIL: no login prompt"; exit 1 } }
      send "root\r"
      expect { "Password:" {} timeout { puts "FAIL: no password prompt"; exit 1 } }
      send "thermostest\r"
      expect { -re {#\s*$} {} timeout { puts "FAIL: no shell prompt after auth"; exit 1 } }

      # Wait for the daemon to own its bus name (Type=dbus).
      send "for i in \$(seq 1 30); do systemctl is-active thermos-daemon.service >/dev/null 2>&1 && break; sleep 1; done; echo WAIT_DONE\r"
      expect { "WAIT_DONE" {} timeout { puts "FAIL: daemon wait loop"; exit 1 } }

      send "systemctl is-active polkit.service; echo POLKIT_RC\$?\r"
      expect { "POLKIT_RC0" {} timeout { puts "FAIL: polkit.service not active"; exit 1 } }

      send "systemctl is-active thermos-daemon.service; echo DAEMON_RC\$?\r"
      expect { "DAEMON_RC0" {} timeout { puts "FAIL: thermos-daemon.service not active"; exit 1 } }

      send "stat -c %U /proc/\$(systemctl show thermos-daemon.service -p MainPID --value)\r"
      expect { "thermos-daemon" {} timeout { puts "FAIL: daemon not running as thermos-daemon"; exit 1 } }

      send "busctl get-property org.thermos.Daemon1 /org/thermos/Daemon1 org.thermos.Daemon1 UpdateState\r"
      expect { "idle" {} timeout { puts "FAIL: UpdateState not idle"; exit 1 } }

      send "busctl call org.thermos.Daemon1 /org/thermos/Daemon1 org.thermos.Daemon1 StartUpdate; echo CALL_RC\$?\r"
      expect { "CALL_RC0" {} timeout { puts "FAIL: StartUpdate not authorized/invoked"; exit 1 } }

      send "journalctl -u thermos-daemon --no-pager\r"
      expect { "StartUpdate authorized for" {} timeout { puts "FAIL: no authorization log line"; exit 1 } }

      send "echo DESKTOP_DAEMON_OK\r"
      expect { "DESKTOP_DAEMON_OK" { puts "desktop daemon ok" } timeout { puts "FAIL: final marker"; exit 1 } }

      send "poweroff -f\r"
      expect eof
      EXPECT
      """)

      result = host.succeed("expect /tmp/daemon.exp")
      assert "desktop daemon ok" in result, f"Daemon acceptance failed:\n{result}"
    '';
  };

  sshLogin =
    let
      inherit (sshArtifacts { })
        kernel
        initrd
        image
        rootPartUUID
        ;
    in
    pkgs.testers.runNixOSTest {
      name = "thermos-ssh-login";

      nodes.client =
        { pkgs, ... }:
        {
          environment.systemPackages = [ pkgs.openssh ];
          virtualisation.vlans = [ 1 ];
          # Hosts the thermos guest (-m 1024) as a nested QEMU; needs headroom.
          virtualisation.memorySize = 3072;
        };

      testScript = thermosLib.pythonPreamble + ''
        start_all()

        client.wait_for_unit("multi-user.target")

        client.succeed("mkdir -p /root/.ssh && chmod 700 /root/.ssh")
        client.succeed("cp ${sshKeys.snakeOilEd25519PrivateKey} /root/.ssh/id_ed25519")
        client.succeed("chmod 600 /root/.ssh/id_ed25519")

        start_command = (
            "${pkgs.qemu_kvm}/bin/qemu-system-x86_64"
            " -m 1024 -enable-kvm"
            " -kernel ${kernel}/bzImage"
            " -initrd ${initrd}/initrd"
            # rw: systemd mounts root= read-only by default; ThermOS has no fstab
            # root entry yet, so the writable rootfs needs it explicitly.
            " -append 'root=PARTUUID=${rootPartUUID} rootfstype=ext4 rw console=ttyS0 loglevel=4'"
            " -drive file=${image}/thermos.raw,if=none,id=d0,format=raw,snapshot=on -device virtio-blk-pci,drive=d0"
            " -netdev vde,id=vlan1,sock=$QEMU_VDE_SOCKET_1"
            " -device virtio-net-pci,netdev=vlan1,mac=52:54:00:12:01:02"
        )

        ssh_opts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

        with thermos_vm("thermos", start_command) as thermos:
            client.wait_until_succeeds(
                f"ssh {ssh_opts} root@192.168.1.2 true",
                timeout=120
            )

            result = client.succeed(f"ssh {ssh_opts} root@192.168.1.2 cat /etc/hostname")
            assert "thermos" in result, f"unexpected hostname: {result}"

            result = client.succeed(f"ssh {ssh_opts} root@192.168.1.2 whoami")
            assert "root" in result, f"unexpected user: {result}"
      '';
    };

  # The same image boots off nvme/ahci/usb/scsi by PARTUUID (udev modalias
  # autoload via /core/initrd-storage). The cmdline is identical across
  # controllers; no case names a device node. Sequential boots.
  storageMatrix =
    let
      inherit
        (sshArtifacts {
          "/core/initrd-storage" = {
            enable = true;
          };
        })
        kernel
        initrd
        image
        rootPartUUID
        ;
    in
    pkgs.testers.runNixOSTest {
      name = "thermos-storage-matrix";

      nodes.client =
        { pkgs, ... }:
        {
          environment.systemPackages = [ pkgs.openssh ];
          virtualisation.vlans = [ 1 ];
          virtualisation.memorySize = 3072;
        };

      testScript = thermosLib.pythonPreamble + ''
        start_all()
        client.wait_for_unit("multi-user.target")
        client.succeed("mkdir -p /root/.ssh && chmod 700 /root/.ssh")
        client.succeed("cp ${sshKeys.snakeOilEd25519PrivateKey} /root/.ssh/id_ed25519")
        client.succeed("chmod 600 /root/.ssh/id_ed25519")

        ssh_opts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

        base = (
            "${pkgs.qemu_kvm}/bin/qemu-system-x86_64"
            " -m 1024 -enable-kvm"
            " -kernel ${kernel}/bzImage"
            " -initrd ${initrd}/initrd"
            " -append 'root=PARTUUID=${rootPartUUID} rootfstype=ext4 rw console=ttyS0 loglevel=4'"
            " -netdev vde,id=vlan1,sock=$QEMU_VDE_SOCKET_1"
            " -device virtio-net-pci,netdev=vlan1,mac=52:54:00:12:01:02"
        )

        img = "${image}/thermos.raw"
        # snapshot=on keeps the store image read-only across cases.
        controllers = {
            "nvme": f" -drive file={img},if=none,id=d0,format=raw,snapshot=on -device nvme,drive=d0,serial=thermos",
            "ahci": f" -drive file={img},if=none,id=d0,format=raw,snapshot=on -device ich9-ahci,id=ahci -device ide-hd,drive=d0,bus=ahci.0",
            "usb": f" -drive file={img},if=none,id=d0,format=raw,snapshot=on -device qemu-xhci,id=xhci -device usb-storage,drive=d0,bus=xhci.0",
            "scsi": f" -drive file={img},if=none,id=d0,format=raw,snapshot=on -device virtio-scsi-pci,id=scsi -device scsi-hd,drive=d0,bus=scsi.0",
        }
        # Each VM exposes only one controller (no virtio-blk fallback), so booting
        # to SSH proves discovery happened on that controller.
        # PARTUUID confirms root is the actual image partition
        # TODO: Make this faster; currently 4 sequential boots.
        for ctrl, disk in controllers.items():
            with thermos_vm(ctrl, base + disk):
                client.wait_until_succeeds(f"ssh {ssh_opts} root@192.168.1.2 true", timeout=180)
                partuuid = client.succeed(f"ssh {ssh_opts} root@192.168.1.2 findmnt -n -o PARTUUID /").strip()
                assert partuuid == "${rootPartUUID}", f"{ctrl}: root mounted from {partuuid!r}, expected ${rootPartUUID}"
                print(f"thermos booted via {ctrl}; root PARTUUID={partuuid}")
      '';
    };
}
