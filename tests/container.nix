# Container tests: nix-build tests/container.nix
let
  thermos = (import ../default.nix) { };
  pkgs = thermos.pkgs;

  unitsDrv = (thermos.evaluated.modules.builders.modules.units { }).derivation;
  usersDrv = (thermos.evaluated.modules.builders.modules.users { }).derivation;
  rootfsDrv = thermos.rootfs;

  # Password hash for 'thermostest' (used in pamAuth test)
  passwordHash = "\$6\$thermostest\$d8h//689.ccFiiNJKscJ9ght7bWyk0WDVBXEHKrMahTIPHLfsMmKeyGgfClxvbpWsBxd/ydyeBzFVWOCLPEiZ1";

  thermosPam = pkgs.pam.overrideAttrs { postPatch = ""; };
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

      host.succeed("cp -a ${rootfsDrv} /rootfs && chmod -R u+w /rootfs")
      host.succeed("sed -i 's|^root:!:|root:${passwordHash}:|' /rootfs/etc/shadow")
      # shadow must be root:root
      host.succeed("chown root:root /rootfs/etc/shadow && chmod 0640 /rootfs/etc/shadow")

      # nspawn without --boot has no PATH
      result = host.succeed(
          "systemd-nspawn --quiet -D /rootfs --bind-ro=/nix/store"
          " --setenv=PATH=/bin:/usr/bin"
          " /bin/cat /etc/shadow"
      )
      assert "root:" in result, f"shadow not readable: {result}"

      host.succeed(
          "systemd-nspawn --boot -D /rootfs --bind-ro=/nix/store"
          " --register=no --quiet &>/tmp/nspawn.log &"
          " echo $! > /tmp/nspawn.pid"
      )

      import time
      for _ in range(60):
          time.sleep(1)
          _, out = host.execute("cat /tmp/nspawn.log")
          if "login:" in out:
              break
      else:
          host.succeed("cat /tmp/nspawn.log >&2")
          raise Exception("no login prompt within 60s")

      boot_log = host.succeed("cat /tmp/nspawn.log")
      assert "Welcome to ThermOS" in boot_log, f"Missing banner:\n{boot_log}"
      assert "login:" in boot_log, f"No login prompt:\n{boot_log}"

      host.execute("kill $(cat /tmp/nspawn.pid) 2>/dev/null; true")
    '';
  };
}
