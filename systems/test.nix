let
  thermos = import ../default.nix { };
  system = thermos.configure {
    options = {
      "/core/base" = {
        # Password: thermos
        rootHashedPassword = "$6$thermos$H0ll22GovTVsmgXyGSxBB1rAwU.QF6D/nFspidCXj0vFJ6YzUUzhs1r8/mEiXnb0IUUP8t2tChAmwA.vEXH9G/";
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
in
{
  rootfs = (system.modules.builders.modules.rootfs { }).derivation;
}
