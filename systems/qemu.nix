import ../default.nix {
  options = {
    "/core/base" = {
      # Password: thermos
      rootHashedPassword = "$6$thermos$H0ll22GovTVsmgXyGSxBB1rAwU.QF6D/nFspidCXj0vFJ6YzUUzhs1r8/mEiXnb0IUUP8t2tChAmwA.vEXH9G/";
    };
    # Static IP on QEMU user-mode (SLIRP) net. DHCP needs AF_PACKET, which the
    # kernel lacks (CONFIG_PACKET=m, unloaded), so DHCP cannot work yet.
    "/services/networkd" = {
      enable = true;
      useDHCP = false;
      addresses = [ "10.0.2.15/24" ];
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
