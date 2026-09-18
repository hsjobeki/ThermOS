let
  thermos = import ../default.nix { };
  system = thermos.configure {
    modules = [
      # Panel getty + autologin
      "/services/getty"
      "/services/dbus"
      "/services/openssh"
      "/services/networkd"
      "/hardware/initrd-network"
      # Broad storage controllers (usb-storage, uas, xhci, ahci, nvme, sd_mod) so
      # the initrd can find the root partition on a USB stick or an internal disk.
      "/hardware/initrd-storage"
      # Keyboard, pointer, HID for the running system. Without this the stage-2
      # /lib/modules is empty and the PS/2 keyboard (i8042/atkbd) cannot load.
      "/hardware/system-input"
    ];
    options = {
      "/core/base" = {
        # Password: thermos. Console login fallback when there is no network yet.
        rootHashedPassword = "$6$thermos$H0ll22GovTVsmgXyGSxBB1rAwU.QF6D/nFspidCXj0vFJ6YzUUzhs1r8/mEiXnb0IUUP8t2tChAmwA.vEXH9G/";
      };
      "/services/networkd" = {
        useDHCP = true;
      };
      "/services/getty" = {
        ttys = [ "tty1" ];
        serialTtys = [ ];
        autologinUser = "root";
      };
      "/services/openssh" = {
        authorizedKeys = {
          root = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGLuev3+8kF+pd1YnCRR7Kw9i9DswOMvGhvdQq6dEIJF johannes@hsjobeki"
          ];
        };
      };
    };
  };

  rootPartUUID = (system.modules.builders.modules.image { }).rootPartUUID;

  # console=tty0 last = the panel (/dev/console); console=ttyS0 first so kernel boot
  # logs also reach serial used as capture path for OVMF boot test).
  cmdline = "root=PARTUUID=${rootPartUUID} console=ttyS0,115200 console=tty0 rw";

  uki = (system.modules.builders.modules.uki { inherit cmdline; }).derivation;
in
{
  /**
    Flashable artifact

    ```
    sudo dd if=result/thermos.raw of=/dev/sda bs=4M conv=fsync status=progress
    sync
    ```
  */
  image = (system.modules.builders.modules.image { espUki = "${uki}/thermos.efi"; }).derivation;
  inherit uki;
}
