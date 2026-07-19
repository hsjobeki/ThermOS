let
  thermos = import ../default.nix { };
  system = thermos.configure {
    options = {
      "/core/base" = {
        # Password: thermos
        rootHashedPassword = "$6$thermos$H0ll22GovTVsmgXyGSxBB1rAwU.QF6D/nFspidCXj0vFJ6YzUUzhs1r8/mEiXnb0IUUP8t2tChAmwA.vEXH9G/";
      };
      "/services/getty" = {
        ttys = [ "tty1" ];
        serialTtys = [ "ttyS0" ];
        autologinUser = "root";
      };
      "/core/graphics" = {
        enable = true;
      };
      "/core/system-input" = {
        enable = true;
      };
      "/services/desktop" = {
        enable = true;
      };
      "/services/thermos-daemon" = {
        enable = true;
      };
      "/services/polkit" = {
        enable = true;
      };
    };
  };

  initrdResult = system.modules.builders.modules.initrd { };
  kernel = initrdResult.kernel;
  initrd = initrdResult.derivation;
in
{
  image = (system.modules.builders.modules.image { }).derivation;
  rootfs = (system.modules.builders.modules.rootfs { }).derivation;
  inherit kernel initrd;
}
