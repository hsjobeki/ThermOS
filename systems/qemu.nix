let
  thermos = import ../default.nix;
in
thermos.configure {
  options = {
    "/core/base" = {
      # Password: thermos
      rootHashedPassword = "$6$thermos$H0ll22GovTVsmgXyGSxBB1rAwU.QF6D/nFspidCXj0vFJ6YzUUzhs1r8/mEiXnb0IUUP8t2tChAmwA.vEXH9G/";
    };
    # Force-load af_packet in the initrd (it persists across switch_root) so the
    # AF_PACKET socket family is available to systemd-networkd's DHCP client.
    # The kernel ships it as a module (CONFIG_PACKET=m); without this load,
    # socket(AF_PACKET) returns EAFNOSUPPORT and DHCP silently fails. Publishes
    # {af_packet, initrd, force} to /contracts/kernel-modules.
    "/core/initrd-network" = {
      enable = true;
    };
    # QEMU user-mode (SLIRP) runs a built-in DHCP server.
    "/services/networkd" = {
      enable = true;
      useDHCP = true;
    };
    "/services/getty" = {
      ttys = [ ];
      serialTtys = [ "ttyS0" ];
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
}
